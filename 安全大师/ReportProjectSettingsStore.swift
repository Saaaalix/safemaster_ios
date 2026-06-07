//
//  ReportProjectSettingsStore.swift
//  安全大师
//

import Foundation

/// 报告封面项目信息（隐患识别页填写后写入 UserDefaults，导出 Word/PDF 读取）。
enum ReportProjectSettingsStore {
    static let projectNameKey = "safemasterReportProjectName"
    static let inspectorNameKey = "safemasterReportInspectorName"
    static let projectAbbreviationKey = "safemasterProjectAbbreviation"

    private static func trimmedValue(forKey key: String) -> String {
        UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func displayName(forKey key: String) -> String {
        let t = trimmedValue(forKey: key)
        return t.isEmpty ? "（未填写）" : t
    }

    static var projectName: String { displayName(forKey: projectNameKey) }
    static var inspectorName: String { displayName(forKey: inspectorNameKey) }
    static var projectAbbreviation: String { displayName(forKey: projectAbbreviationKey) }

    static func legacyProjectNameFallback(emptyPlaceholder: String = "（未填写项目）") -> String {
        let t = trimmedValue(forKey: projectNameKey)
        return t.isEmpty ? emptyPlaceholder : t
    }

    static func legacyInspectorNameFallback(emptyPlaceholder: String = "（未填写检查人）") -> String {
        let t = trimmedValue(forKey: inspectorNameKey)
        return t.isEmpty ? emptyPlaceholder : t
    }

    static func coverProjectName(for findings: [InspectionFinding]) -> String {
        coverValue(
            from: findings.compactMap(\.recordProjectNameSnapshot),
            fallback: projectName,
            multiSuffix: "个项目"
        )
    }

    static func coverInspectorName(for findings: [InspectionFinding]) -> String {
        coverValue(
            from: findings.compactMap(\.recordInspectorNameSnapshot),
            fallback: inspectorName,
            multiSuffix: "名检查人"
        )
    }

    private static func coverValue(from snapshots: [String], fallback: String, multiSuffix: String) -> String {
        let unique = Array(Set(snapshots)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        switch unique.count {
        case 0:
            return fallback
        case 1:
            return unique[0]
        default:
            return "\(unique[0])等 \(unique.count) \(multiSuffix)"
        }
    }

    /// 写入 Core Data 快照用（空则存 nil）。
    static var projectNameRaw: String {
        trimmedValue(forKey: projectNameKey)
    }

    static var inspectorNameRaw: String {
        trimmedValue(forKey: inspectorNameKey)
    }

    static var projectAbbreviationRaw: String {
        trimmedValue(forKey: projectAbbreviationKey)
    }

    static func normalizedProjectAbbreviation(_ raw: String?) -> String? {
        let source = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !source.isEmpty else { return nil }
        let cleaned = source
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(
                of: "[^\\p{Han}A-Za-z0-9-]",
                with: "",
                options: .regularExpression
            )
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(8)).uppercased()
    }

    /// 仅写入非空字段，避免隐患识别页留空离开时覆盖 UserDefaults 中已有封面信息。
    static func persistIfNonEmpty(
        projectName: String,
        inspectorName: String,
        projectAbbreviation: String? = nil
    ) {
        let p = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !p.isEmpty {
            UserDefaults.standard.set(p, forKey: projectNameKey)
        }
        let i = inspectorName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !i.isEmpty {
            UserDefaults.standard.set(i, forKey: inspectorNameKey)
        }
        if let abbreviation = normalizedProjectAbbreviation(projectAbbreviation) {
            UserDefaults.standard.set(abbreviation, forKey: projectAbbreviationKey)
        }
    }
}
