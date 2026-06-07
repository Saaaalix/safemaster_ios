//
//  SafeMasterAPIClient.swift
//  安全大师
//

import Foundation

enum SafeMasterAPIError: LocalizedError {
    case invalidBaseURL
    case httpError(Int, String?)
    case serverMessage(String)
    case decoding
    /// 云端次数不够（HTTP 402）
    case insufficientCredits(remaining: Int?)
    /// 未配置 API 地址或未保存 accessToken
    case cloudSessionMissing

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "API 地址无效，请检查是否以 http:// 或 https:// 开头。"
        case .httpError(let code, let body):
            if let body, !body.isEmpty { return "请求失败（\(code)）：\(body)" }
            return "请求失败（HTTP \(code)）。"
        case .serverMessage(let s):
            return s
        case .decoding:
            return "无法解析服务器返回内容。"
        case .insufficientCredits(let r):
            if let r { return "今日 AI 额度不足（剩余 \(r) 点）。" }
            return "今日 AI 额度不足。"
        case .cloudSessionMissing:
            return "请先使用 Apple 登录完成账号同步（在「我的」页面）。"
        }
    }
}

private struct AuthAppleBody: Encodable {
    let identityToken: String
}

private struct AuthAppleResponse: Decodable {
    let ok: Bool?
    let accessToken: String?
    let credits: Int?
    let subscription: CloudSubscriptionSnapshot?
    let error: String?
}

private struct MeResponse: Decodable {
    let ok: Bool?
    let credits: Int?
    let subscription: CloudSubscriptionSnapshot?
    let error: String?
}

private struct VerifyAppleSubscriptionBody: Encodable {
    let productId: String
    let signedTransactionInfo: String
}

private struct VerifyAppleSubscriptionResponse: Decodable {
    let ok: Bool?
    let credits: Int?
    let subscription: CloudSubscriptionSnapshot?
    let error: String?
}

private struct ConsumeBody: Encodable {
    let amount: Int
}

private struct ConsumeResponse: Decodable {
    let ok: Bool?
    let credits: Int?
    let error: String?
}

/// 请求体：`POST /v1/hazard/analyze`（与 Node 端字段一致）。
struct HazardAnalyzeRequestBody: Encodable {
    var hasPhoto: Bool
    var location: String
    var supplementaryText: String
    var visionBlock: String
    /// 行业域：construction / chemical / all。当前默认 construction。
    var industryDomain: String
}

struct CloudSubscriptionSnapshot: Decodable {
    let active: Bool?
    let status: String?
    let expiresAt: String?
    let dailyLimit: Int?
    let dailyUsed: Int?
    let dailyRemaining: Int?
    let dailyQuotaDate: String?
    let reportUnlimited: Bool?
    let monthlyPriceCNY: Int?
}

struct CloudAccountSnapshot {
    let remainingDailyQuota: Int
    let subscription: CloudSubscriptionSnapshot?
}

private struct HazardAnalyzeAPIResponse: Decodable {
    let ok: Bool?
    let credits: Int?
    let error: String?
    let analysis: HazardAnalyzeAnalysisDTO?
}

private struct ImportedNoticeParseBody: Encodable {
    let text: String
    let fileName: String
}

private struct ImportedNoticeParseResponse: Decodable {
    let ok: Bool?
    let credits: Int?
    let error: String?
    let draft: ImportedNoticeDraftDTO?
}

private struct ImportedNoticeFieldDTO: Decodable {
    let value: String?
    let confidence: Double?
    let sourceSnippet: String?
    let source_snippet: String?
    let needsReview: Bool?
    let needs_review: Bool?

    func toRecognizedField(isRequired: Bool) -> ImportedNoticeRecognizedField {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let score = confidence ?? (trimmed.isEmpty ? 0 : 0.9)
        return ImportedNoticeRecognizedField(
            value: trimmed,
            confidence: score,
            sourceSnippet: sourceSnippet ?? source_snippet,
            needsReview: isRequired && (needsReview ?? needs_review ?? (trimmed.isEmpty || score < 0.85))
        )
    }
}

private struct ImportedNoticeHazardDraftDTO: Decodable {
    let location: ImportedNoticeFieldDTO?
    let description: ImportedNoticeFieldDTO?
    let requirement: ImportedNoticeFieldDTO?
    let dueDate: ImportedNoticeFieldDTO?
    let due_date: ImportedNoticeFieldDTO?
    let responsibleParty: ImportedNoticeFieldDTO?
    let responsible_party: ImportedNoticeFieldDTO?

    func toDraft() -> ImportedNoticeHazardDraft {
        ImportedNoticeHazardDraft(
            location: (location ?? .empty).toRecognizedField(isRequired: false),
            description: (description ?? .empty).toRecognizedField(isRequired: true),
            requirement: (requirement ?? .empty).toRecognizedField(isRequired: true),
            dueDate: (dueDate ?? due_date ?? .empty).toRecognizedField(isRequired: false),
            responsibleParty: (responsibleParty ?? responsible_party ?? .empty).toRecognizedField(isRequired: false)
        )
    }
}

private struct ImportedNoticeDraftDTO: Decodable {
    let documentType: String?
    let document_type: String?
    let projectName: ImportedNoticeFieldDTO?
    let project_name: ImportedNoticeFieldDTO?
    let issuer: ImportedNoticeFieldDTO?
    let inspectedUnit: ImportedNoticeFieldDTO?
    let inspected_unit: ImportedNoticeFieldDTO?
    let noticeNo: ImportedNoticeFieldDTO?
    let notice_no: ImportedNoticeFieldDTO?
    let noticeDate: ImportedNoticeFieldDTO?
    let notice_date: ImportedNoticeFieldDTO?
    let rectificationDeadline: ImportedNoticeFieldDTO?
    let rectification_deadline: ImportedNoticeFieldDTO?
    let hazards: [ImportedNoticeHazardDraftDTO]?
    let legalBasis: ImportedNoticeFieldDTO?
    let legal_basis: ImportedNoticeFieldDTO?
    let summary: String?
    let confidence: Double?
    let warnings: [String]?

    func toDraft(documentID: UUID) -> ImportedNoticeDraft {
        let typeValue = (documentType ?? document_type ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let type = ImportedNoticeDocumentType(rawValue: typeValue) ?? .hazardNotice
        return ImportedNoticeDraft(
            documentID: documentID,
            documentType: type,
            projectName: (projectName ?? project_name ?? .empty).toRecognizedField(isRequired: type.isRequired(.projectName)),
            issuer: (issuer ?? .empty).toRecognizedField(isRequired: type.isRequired(.issuer)),
            inspectedUnit: (inspectedUnit ?? inspected_unit ?? .empty).toRecognizedField(isRequired: type.isRequired(.inspectedUnit)),
            noticeNo: (noticeNo ?? notice_no ?? .empty).toRecognizedField(isRequired: type.isRequired(.noticeNo)),
            noticeDate: (noticeDate ?? notice_date ?? .empty).toRecognizedField(isRequired: type.isRequired(.noticeDate)),
            rectificationDeadline: (rectificationDeadline ?? rectification_deadline ?? .empty).toRecognizedField(isRequired: type.isRequired(.rectificationDeadline)),
            hazards: (hazards ?? []).map { $0.toDraft() },
            legalBasis: (legalBasis ?? legal_basis ?? .empty).toRecognizedField(isRequired: type.isRequired(.legalBasis)),
            summary: summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            confidence: confidence ?? 0.9,
            warnings: warnings ?? []
        )
    }
}

private extension ImportedNoticeFieldDTO {
    static let empty = ImportedNoticeFieldDTO(
        value: nil,
        confidence: nil,
        sourceSnippet: nil,
        source_snippet: nil,
        needsReview: nil,
        needs_review: nil
    )
}

private struct HazardAnalyzeAnalysisDTO: Decodable {
    let hazard_description: String?
    let hazardDescription: String?
    let rectification_measures: String?
    let rectificationMeasures: String?
    let rectification_reply_draft: String?
    let rectificationReplyDraft: String?
    let risk_level: String?
    let riskLevel: String?
    let accident_category_major: String?
    let accidentCategoryMajor: String?
    let accident_category_minor: String?
    let accidentCategoryMinor: String?
    let legal_basis: String?
    let legalBasis: String?

    private static func pick(_ a: String?, _ b: String?) -> String {
        let t = (a ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return (b ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func toResult() -> HazardAnalysisResult {
        let hazard = Self.pick(hazard_description, hazardDescription)
        var measures = Self.pick(rectification_measures, rectificationMeasures)
        if measures.isEmpty, !hazard.isEmpty {
            measures = """
            （本次模型未返回整改措施正文。请结合上方隐患描述与整改依据现场落实，或点击「重新分析（需联网）」重试。）
            1. 对照隐患描述逐项消除：如移除影响散热/检修的遮盖物，规范电缆与箱体布置。
            2. 对间距、防护等级等需实测项，现场测定后采取隔离、警戒或移位等措施直至符合规范。
            3. 完成整改后复查并留存记录。
            """
        }
        let risk = Self.pick(risk_level, riskLevel)
        return HazardAnalysisResult(
            hazardDescription: hazard,
            rectificationMeasures: measures,
            rectificationReplyDraft: Self.pick(rectification_reply_draft, rectificationReplyDraft),
            riskLevel: risk.isEmpty ? "一般风险" : risk,
            accidentCategoryMajor: Self.pick(accident_category_major, accidentCategoryMajor),
            accidentCategoryMinor: Self.pick(accident_category_minor, accidentCategoryMinor),
            legalBasis: Self.pick(legal_basis, legalBasis)
        )
    }
}

private struct APIErrorBody: Decodable {
    let error: String?
    let credits: Int?
}

/// 与自建 `safemaster-api` 通信（`/v1/auth/apple`、`/v1/me`）。
struct SafeMasterAPIClient {
    let baseURL: String

    private var root: URL? {
        let t = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        var s = t
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    /// `POST /v1/auth/apple`，返回服务端 `accessToken` 与账号快照（会员状态 + 每日剩余次数）。
    func signInWithApple(identityToken: String) async throws -> (accessToken: String, account: CloudAccountSnapshot) {
        guard let root else { throw SafeMasterAPIError.invalidBaseURL }
        guard let url = URL(string: root.absoluteString + "/v1/auth/apple") else {
            throw SafeMasterAPIError.invalidBaseURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(AuthAppleBody(identityToken: identityToken))

        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(data: data, response: resp)

        let decoded = try JSONDecoder().decode(AuthAppleResponse.self, from: data)
        if decoded.ok == false || decoded.accessToken == nil {
            throw SafeMasterAPIError.serverMessage(decoded.error ?? "登录失败")
        }
        guard let token = decoded.accessToken else { throw SafeMasterAPIError.decoding }
        let left = decoded.subscription?.dailyRemaining ?? decoded.credits ?? 0
        return (token, CloudAccountSnapshot(remainingDailyQuota: left, subscription: decoded.subscription))
    }

    /// `GET /v1/me`，需 Bearer。
    func fetchMe(accessToken: String) async throws -> CloudAccountSnapshot {
        guard let root else { throw SafeMasterAPIError.invalidBaseURL }
        guard let url = URL(string: root.absoluteString + "/v1/me") else {
            throw SafeMasterAPIError.invalidBaseURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(data: data, response: resp)

        let decoded = try JSONDecoder().decode(MeResponse.self, from: data)
        if decoded.ok == false {
            throw SafeMasterAPIError.serverMessage(decoded.error ?? "获取次数失败")
        }
        let left = decoded.subscription?.dailyRemaining ?? decoded.credits
        guard let c = left else { throw SafeMasterAPIError.decoding }
        return CloudAccountSnapshot(remainingDailyQuota: c, subscription: decoded.subscription)
    }

    /// `POST /v1/credits/consume`，成功返回扣减后的剩余次数。
    func consumeCredits(accessToken: String, amount: Int = 1) async throws -> Int {
        guard let root else { throw SafeMasterAPIError.invalidBaseURL }
        guard let url = URL(string: root.absoluteString + "/v1/credits/consume") else {
            throw SafeMasterAPIError.invalidBaseURL
        }
        let n = min(10, max(1, amount))
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(ConsumeBody(amount: n))

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw SafeMasterAPIError.httpError(-1, nil)
        }

        if http.statusCode == 402 {
            let decoded = try? JSONDecoder().decode(ConsumeResponse.self, from: data)
            throw SafeMasterAPIError.insufficientCredits(remaining: decoded?.credits)
        }

        try throwIfNeeded(data: data, response: resp)

        let decoded = try JSONDecoder().decode(ConsumeResponse.self, from: data)
        if decoded.ok == false {
            throw SafeMasterAPIError.serverMessage(decoded.error ?? "扣次失败")
        }
        guard let c = decoded.credits else { throw SafeMasterAPIError.decoding }
        return c
    }

    /// `POST /v1/hazard/analyze`：服务端扣 1 次并代调模型。
    func analyzeHazard(accessToken: String, body: HazardAnalyzeRequestBody) async throws -> (credits: Int, analysis: HazardAnalysisResult) {
        guard let root else { throw SafeMasterAPIError.invalidBaseURL }
        guard let url = URL(string: root.absoluteString + "/v1/hazard/analyze") else {
            throw SafeMasterAPIError.invalidBaseURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 120

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw SafeMasterAPIError.httpError(-1, nil)
        }

        if http.statusCode == 402 {
            let err = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            throw SafeMasterAPIError.insufficientCredits(remaining: err?.credits)
        }

        if http.statusCode == 401 {
            let err = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            throw SafeMasterAPIError.serverMessage(err?.error ?? "需要重新登录")
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let err = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            let fallback = String(data: data, encoding: .utf8)
            throw SafeMasterAPIError.httpError(http.statusCode, err?.error ?? fallback)
        }

        let decoded = try JSONDecoder().decode(HazardAnalyzeAPIResponse.self, from: data)
        if decoded.ok == false {
            throw SafeMasterAPIError.serverMessage(decoded.error ?? "分析失败")
        }
        guard let block = decoded.analysis else {
            throw SafeMasterAPIError.serverMessage(decoded.error ?? "服务器未返回分析结果")
        }
        guard let credits = decoded.credits else { throw SafeMasterAPIError.decoding }
        return (credits, block.toResult())
    }

    /// `POST /v1/subscription/apple/verify`：上传 StoreKit2 交易凭证，换取最新会员状态。
    func verifyAppleSubscription(
        accessToken: String,
        productId: String,
        signedTransactionInfo: String
    ) async throws -> CloudAccountSnapshot {
        guard let root else { throw SafeMasterAPIError.invalidBaseURL }
        guard let url = URL(string: root.absoluteString + "/v1/subscription/apple/verify") else {
            throw SafeMasterAPIError.invalidBaseURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(
            VerifyAppleSubscriptionBody(
                productId: productId,
                signedTransactionInfo: signedTransactionInfo
            )
        )

        let (data, resp) = try await URLSession.shared.data(for: req)
        try throwIfNeeded(data: data, response: resp)

        let decoded = try JSONDecoder().decode(VerifyAppleSubscriptionResponse.self, from: data)
        if decoded.ok == false {
            throw SafeMasterAPIError.serverMessage(decoded.error ?? "订阅验票失败")
        }
        let left = decoded.subscription?.dailyRemaining ?? decoded.credits
        guard let c = left else { throw SafeMasterAPIError.decoding }
        return CloudAccountSnapshot(remainingDailyQuota: c, subscription: decoded.subscription)
    }

    /// `POST /v1/import/extract-text`：上传文档并请求服务端提取文本（含 AI 清洗兜底）。
    func extractImportedText(
        accessToken: String,
        fileURL: URL,
        fileName: String,
        cleanWithAI: Bool = true
    ) async throws -> String {
        guard let root else { throw SafeMasterAPIError.invalidBaseURL }
        guard let url = URL(string: root.absoluteString + "/v1/import/extract-text") else {
            throw SafeMasterAPIError.invalidBaseURL
        }
        let fileData = try Data(contentsOf: fileURL)
        let boundary = "----SafeMasterBoundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120

        var body = Data()
        func append(_ s: String) {
            body.append(Data(s.utf8))
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"cleanWithAI\"\r\n\r\n")
        append(cleanWithAI ? "1" : "0")
        append("\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(fileData)
        append("\r\n")
        append("--\(boundary)--\r\n")
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw SafeMasterAPIError.httpError(-1, nil)
        }
        if !(200 ... 299).contains(http.statusCode) {
            let fallback = String(data: data, encoding: .utf8)
            let decoded = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            throw SafeMasterAPIError.httpError(http.statusCode, decoded?.error ?? fallback)
        }
        struct ImportExtractResponse: Decodable {
            let ok: Bool?
            let text: String?
            let error: String?
        }
        let decoded = try JSONDecoder().decode(ImportExtractResponse.self, from: data)
        if decoded.ok == false {
            throw SafeMasterAPIError.serverMessage(decoded.error ?? "文档提取失败")
        }
        let text = decoded.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty {
            throw SafeMasterAPIError.serverMessage("文档提取为空")
        }
        return text
    }

    /// `POST /v1/import/parse-notice`：把已提取正文交给云端 AI 解析为通知单草稿字段。
    func parseImportedNoticeDraft(
        accessToken: String,
        extraction: ImportedNoticeExtraction,
        fileName: String
    ) async throws -> ImportedNoticeDraft {
        guard let root else { throw SafeMasterAPIError.invalidBaseURL }
        guard let url = URL(string: root.absoluteString + "/v1/import/parse-notice") else {
            throw SafeMasterAPIError.invalidBaseURL
        }

        let body = ImportedNoticeParseBody(
            text: extraction.cleanedText,
            fileName: fileName
        )
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 120
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw SafeMasterAPIError.httpError(-1, nil)
        }
        if !(200 ... 299).contains(http.statusCode) {
            let decoded = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            if http.statusCode == 402 {
                throw SafeMasterAPIError.insufficientCredits(remaining: decoded?.credits)
            }
            throw SafeMasterAPIError.httpError(http.statusCode, decoded?.error ?? String(data: data, encoding: .utf8))
        }

        let decoded = try JSONDecoder().decode(ImportedNoticeParseResponse.self, from: data)
        if decoded.ok == false {
            throw SafeMasterAPIError.serverMessage(decoded.error ?? "通知单识别失败")
        }
        guard let draft = decoded.draft else {
            throw SafeMasterAPIError.decoding
        }
        let documentID = extraction.documentID ?? UUID()
        if let credits = decoded.credits {
            NotificationCenter.default.post(
                name: .safemasterCreditsDidChange,
                object: nil,
                userInfo: ["credits": credits]
            )
        }
        return draft.toDraft(documentID: documentID)
    }

    private func throwIfNeeded(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw SafeMasterAPIError.httpError(http.statusCode, body)
        }
    }
}
