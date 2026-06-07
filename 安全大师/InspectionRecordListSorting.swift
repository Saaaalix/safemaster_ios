//
//  InspectionRecordListSorting.swift
//  安全大师
//

import CoreData
import Foundation

/// 隐患排查记录列表排序方式。
enum InspectionRecordSortMode: String, CaseIterable, Identifiable {
    case time
    case project
    case inspector
    case responsible

    var id: String { rawValue }

    var label: String {
        switch self {
        case .time: return "按时间"
        case .project: return "按项目"
        case .inspector: return "按检查人"
        case .responsible: return "按责任人"
        }
    }

    static let storageKey = "safemasterInspectionRecordSortMode"
}

enum InspectionRecordListSorting {
    /// 同一主键下按发现/创建时间新→旧。
    private static func secondaryTimeDescending(_ a: InspectionFinding, _ b: InspectionFinding) -> Bool {
        let a0 = a.effectiveArchiveDate ?? a.createdAt ?? .distantPast
        let a1 = b.effectiveArchiveDate ?? b.createdAt ?? .distantPast
        if a0 != a1 { return a0 > a1 }
        return (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast)
    }

    private static func localizedAscending(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    static func sorted(_ findings: [InspectionFinding], mode: InspectionRecordSortMode) -> [InspectionFinding] {
        switch mode {
        case .time:
            return findings.sorted(by: secondaryTimeDescending)
        case .project:
            return findings.sorted { a, b in
                let ka = a.recordProjectNameDisplay
                let kb = b.recordProjectNameDisplay
                if ka != kb { return localizedAscending(ka, kb) }
                return secondaryTimeDescending(a, b)
            }
        case .inspector:
            return findings.sorted { a, b in
                let ka = a.recordInspectorNameDisplay
                let kb = b.recordInspectorNameDisplay
                if ka != kb { return localizedAscending(ka, kb) }
                return secondaryTimeDescending(a, b)
            }
        case .responsible:
            return findings.sorted { a, b in
                let ka = a.latestResponsiblePartyDisplay
                let kb = b.latestResponsiblePartyDisplay
                if ka != kb { return localizedAscending(ka, kb) }
                return secondaryTimeDescending(a, b)
            }
        }
    }

    static func matchesSearch(_ finding: InspectionFinding, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        let haystack = [
            finding.location,
            finding.supplementaryText,
            finding.hazardDescription,
            finding.recordProjectNameDisplay,
            finding.recordInspectorNameDisplay,
            finding.latestRectificationRound?.responsibleParty
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
        return haystack.localizedStandardContains(q)
    }

    static func filtered(
        _ findings: [InspectionFinding],
        searchText: String
    ) -> [InspectionFinding] {
        findings.filter { matchesSearch($0, query: searchText) }
    }

    // MARK: - 分组（二级列表）

    static func sectionKey(for finding: InspectionFinding, mode: InspectionRecordSortMode) -> String {
        switch mode {
        case .time:
            let cal = Calendar.current
            let day = cal.startOfDay(for: finding.effectiveArchiveDate ?? finding.createdAt ?? .distantPast)
            return "time-\(day.timeIntervalSince1970)"
        case .project:
            return "project-\(finding.recordProjectNameDisplay)"
        case .inspector:
            return "inspector-\(finding.recordInspectorNameDisplay)"
        case .responsible:
            return "responsible-\(finding.latestResponsiblePartyDisplay)"
        }
    }

    static func sectionTitle(for finding: InspectionFinding, mode: InspectionRecordSortMode) -> String {
        switch mode {
        case .time:
            let raw = finding.effectiveArchiveDate ?? finding.createdAt ?? .distantPast
            return InspectionRecordListFormatting.dayHeader(from: raw)
        case .project:
            return finding.recordProjectNameDisplay
        case .inspector:
            return finding.recordInspectorNameDisplay
        case .responsible:
            return finding.latestResponsiblePartyDisplay
        }
    }

    /// 已按 `mode` 排序的条目 → 按当前排序维度分 Section（顺序与排序一致）。
    static func grouped(
        _ findings: [InspectionFinding],
        mode: InspectionRecordSortMode
    ) -> [InspectionRecordListSection] {
        guard !findings.isEmpty else { return [] }
        var sections: [InspectionRecordListSection] = []
        var currentKey: String?
        var currentTitle: String?
        var bucket: [InspectionFinding] = []

        func flush() {
            guard let key = currentKey, let title = currentTitle, !bucket.isEmpty else { return }
            sections.append(InspectionRecordListSection(sectionKey: key, title: title, findings: bucket))
            bucket = []
        }

        for finding in findings {
            let key = sectionKey(for: finding, mode: mode)
            let title = sectionTitle(for: finding, mode: mode)
            if key != currentKey {
                flush()
                currentKey = key
                currentTitle = title
                bucket = [finding]
            } else {
                bucket.append(finding)
            }
        }
        flush()
        return sections
    }
}

struct InspectionRecordListSection: Identifiable {
    var id: String { sectionKey }
    let sectionKey: String
    let title: String
    let findings: [InspectionFinding]
}

enum InspectionRecordListFormatting {
    private static let dayHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    static func dayHeader(from date: Date) -> String {
        dayHeaderFormatter.string(from: date)
    }

    static func dayLine(from finding: InspectionFinding) -> String {
        let raw = finding.effectiveArchiveDate ?? finding.createdAt ?? Date()
        return dayHeader(from: raw)
    }

    static func condensed(_ text: String, maxLength: Int = 140) -> String {
        guard text.count > maxLength else { return text }
        let end = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<end]) + "…"
    }
}

extension InspectionFinding {
    /// 列表行「隐患内容摘要」：优先用户补充，否则 AI 描述（截断）。
    var recordListHazardSummary: String {
        let sup = (supplementaryText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !sup.isEmpty {
            return InspectionRecordListFormatting.condensed(sup)
        }
        let hazard = (hazardDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !hazard.isEmpty {
            return InspectionRecordListFormatting.condensed(hazard)
        }
        return "（无隐患描述）"
    }
}
