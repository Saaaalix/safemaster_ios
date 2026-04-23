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
            if let r { return "今日分析次数不足（剩余 \(r) 次）。" }
            return "今日分析次数不足。"
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
    var playbookBlock: String
    var lawEvidenceBlock: String
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

private struct HazardAnalyzeAnalysisDTO: Decodable {
    let hazard_description: String?
    let hazardDescription: String?
    let rectification_measures: String?
    let rectificationMeasures: String?
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

    private func throwIfNeeded(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw SafeMasterAPIError.httpError(http.statusCode, body)
        }
    }
}
