//
//  HazardRiskLevel.swift
//  安全大师
//

import Foundation

/// 四档风险等级：录入、语音、记录详情与报告导出统一口径。
enum HazardRiskLevel {
    static let canonicalOptions = ["重大风险", "较大风险", "一般风险", "低风险"]

    /// 将语音/手输别名规范为存储用四档之一；无法识别时返回 `nil`。
    static func normalizedForStorage(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        if canonicalOptions.contains(trimmed) { return trimmed }
        switch trimmed {
        case "重大隐患": return "重大风险"
        case "较大隐患": return "较大风险"
        case "一般隐患": return "一般风险"
        default: return nil
        }
    }

    /// 保存/展示：用户指定优先，否则用 AI 分析结果。
    static func effectiveLevel(userOverride: String?, aiLevel: String) -> String {
        if let user = normalizedForStorage(userOverride) { return user }
        if let ai = normalizedForStorage(aiLevel) { return ai }
        let aiTrim = aiLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        return aiTrim.isEmpty ? "一般风险" : aiTrim
    }
}
