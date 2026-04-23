//
//  CloudHazardAnalysisService.swift
//  安全大师
//

import Foundation

/// 本机完成 Vision 与法规检索，模型推理由自建服务端 `POST /v1/hazard/analyze` 代调（密钥不在 App 内）。
struct CloudHazardAnalysisService: HazardAnalysisService {
    /// 弱网场景下避免长时间无响应：整段分析超过此时长则失败并提示使用「无网先记录」。
    private static let analysisWallClockTimeoutSeconds: UInt64 = 75

    func analyze(photoData: Data?, secondaryPhotoData: Data?, supplementaryText: String, location: String) async throws -> HazardAnalysisResult {
        try Task.checkCancellation()
        let text = supplementaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            throw HazardAnalysisError.missingInput
        }

        return try await withThrowingTaskGroup(of: HazardAnalysisResult.self) { group in
            group.addTask {
                try await self.runFullCloudAnalysis(
                    photoData: photoData,
                    secondaryPhotoData: secondaryPhotoData,
                    supplementaryText: supplementaryText,
                    location: location
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.analysisWallClockTimeoutSeconds * 1_000_000_000)
                throw HazardAnalysisError.network(
                    "分析超时（约 \(Self.analysisWallClockTimeoutSeconds) 秒）。隧道或弱网时可点「无网先记录」保存本条，有网后再重新分析。"
                )
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    private func runFullCloudAnalysis(photoData: Data?, secondaryPhotoData: Data?, supplementaryText: String, location: String) async throws -> HazardAnalysisResult {
        let chunks: [Data] = [photoData, secondaryPhotoData].compactMap { d in
            guard let d, !d.isEmpty else { return nil }
            return d
        }
        let hasPhoto = !chunks.isEmpty
        let text = supplementaryText.trimmingCharacters(in: .whitespacesAndNewlines)

        var visionBlock = ""
        if hasPhoto {
            try Task.checkCancellation()
            visionBlock = await VisionImageContext.summarizePhotoDatas(chunks, supplementaryText: text)
            try Task.checkCancellation()
        }

        let place = location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未填写" : location
        let userExtra = text.isEmpty ? "（用户未填写补充文字）" : text

        let retrievalQuery = """
        \(place)
        \(userExtra)
        \(visionBlock)
        """

        try Task.checkCancellation()
        let playbookRows = await LawEvidenceRetriever.shared.retrievePlaybook(query: retrievalQuery, topK: 8)
        let basisRows = await LawEvidenceRetriever.shared.retrieveBasis(
            query: retrievalQuery,
            userEmphasis: text,
            topK: 12
        )
        try Task.checkCancellation()
        let playbookBlock = LawEvidenceRetriever.formatPlaybookBlock(playbookRows)
        let basisBlock = LawEvidenceRetriever.formatBasisBlock(basisRows)

        let baseRaw = SafeMasterAPIConfiguration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if baseRaw.isEmpty {
            throw HazardAnalysisError.cloudCredits(SafeMasterAPIError.cloudSessionMissing.errorDescription ?? "请先完成账号同步。")
        }
        guard let token = KeychainStore.safemasterAccessToken(),
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw HazardAnalysisError.cloudCredits(
                "使用云端分析前，请在「我的」使用 Apple 登录完成同步。也可先用「无网先记录」保存现场。"
            )
        }

        let body = HazardAnalyzeRequestBody(
            hasPhoto: hasPhoto,
            location: location,
            supplementaryText: supplementaryText,
            visionBlock: visionBlock,
            playbookBlock: playbookBlock,
            lawEvidenceBlock: basisBlock
        )

        do {
            let client = SafeMasterAPIClient(baseURL: baseRaw)
            let (credits, analysis) = try await client.analyzeHazard(accessToken: token, body: body)
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .safemasterCreditsDidChange,
                    object: nil,
                    userInfo: ["credits": credits]
                )
            }
            return analysis
        } catch let sm as SafeMasterAPIError {
            switch sm {
            case .insufficientCredits:
                throw HazardAnalysisError.cloudCredits(sm.localizedDescription)
            case .cloudSessionMissing:
                throw HazardAnalysisError.cloudCredits(sm.localizedDescription)
            default:
                throw HazardAnalysisError.network(sm.localizedDescription)
            }
        } catch {
            throw HazardAnalysisError.network("请求分析服务失败：\(error.localizedDescription)")
        }
    }
}
