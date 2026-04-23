//
//  HazardAnalysisService.swift
//  安全大师
//

import Foundation

protocol HazardAnalysisService {
    /// `secondaryPhotoData` 为第二张现场图；与 `photoData` 合计至多 2 张。
    func analyze(photoData: Data?, secondaryPhotoData: Data?, supplementaryText: String, location: String) async throws -> HazardAnalysisResult
}

enum HazardAnalysisError: LocalizedError {
    case missingInput
    case network(String)
    case apiStatus(Int, String)
    case emptyModelReply
    case jsonDecodeFailed
    /// 云端扣次 / 登录配置相关（在请求分析接口之前）
    case cloudCredits(String)

    var errorDescription: String? {
        switch self {
        case .missingInput:
            return "请先填写「隐患描述」（可无照片）后再开始排查。"
        case .network(let msg):
            return "网络错误：\(msg)"
        case .apiStatus(let code, let msg):
            return "分析服务错误（\(code)）：\(msg)"
        case .emptyModelReply:
            return "模型未返回有效内容，请稍后重试。"
        case .jsonDecodeFailed:
            return "无法解析模型返回的 JSON，请重试。"
        case .cloudCredits(let msg):
            return msg
        }
    }
}

/// 未配置密钥时使用；与云端结果格式一致，便于联调 UI。
struct MockHazardAnalysisService: HazardAnalysisService {
    func analyze(photoData: Data?, secondaryPhotoData: Data?, supplementaryText: String, location: String) async throws -> HazardAnalysisResult {
        let text = supplementaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            throw HazardAnalysisError.missingInput
        }
        let hasPhoto1 = photoData != nil && !(photoData?.isEmpty ?? true)
        let hasPhoto2 = secondaryPhotoData != nil && !(secondaryPhotoData?.isEmpty ?? true)
        let hasPhoto = hasPhoto1 || hasPhoto2

        try await Task.sleep(nanoseconds: 600_000_000)

        let place = location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "该作业区域" : location
        let contextHint = hasPhoto ? "结合现场影像" : "根据文字描述"
        return HazardAnalysisResult(
            hazardDescription: "\(contextHint)，在「\(place)」可见典型建筑施工安全隐患：洞口或临边防护不到位、警示标识缺失，存在人员坠落或物体打击可能。",
            rectificationMeasures: "1. 立即设置符合 JGJ 80 要求的临边/洞口防护栏杆及安全网。\n2. 补充夜间与通道口警示灯及反光标识。\n3. 作业前安全技术交底并设专人巡查。",
            riskLevel: "较大风险",
            accidentCategoryMajor: "高处与建筑施工类",
            accidentCategoryMinor: "高处坠落",
            legalBasis: "《建筑施工高处作业安全技术规范》JGJ 80-2016 第4.1.1条（摘录）：「临边作业的防护栏杆应由横杆、立杆及挡脚板组成……防护栏杆应为两道横杆，上杆距地面高度应为1.2m，下杆应在上杆和挡脚板中间设置。」\n《建筑施工安全检查标准》JGJ 59-2011 相关条款（示例）：临边、洞口防护应符合规范要求并经验收。\n\n（以上为应用内演示文本；已在「我的」完成 API 地址与 Apple 同步时将走服务端云端分析。）"
        )
    }
}

enum HazardAnalysisServiceFactory {
    static func makeDefault() -> HazardAnalysisService {
        let base = SafeMasterAPIConfiguration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = KeychainStore.safemasterAccessToken()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !base.isEmpty, !token.isEmpty {
            return CloudHazardAnalysisService()
        }
        return MockHazardAnalysisService()
    }
}
