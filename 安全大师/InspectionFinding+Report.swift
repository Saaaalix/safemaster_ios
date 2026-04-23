//
//  InspectionFinding+Report.swift
//  安全大师
//

import CoreData
import Foundation

extension InspectionFinding {
    /// 用于列表归档与「某日详情」筛选：有「发现时间」则按发现日，否则按创建日（与详情里可编辑的发现时间一致）。
    var effectiveArchiveDate: Date? {
        discoveredAt ?? createdAt
    }

    /// 现场主图、副图（各至多一张，顺序固定）；用于展示、导出与重新分析。
    var sitePhotoDatasOrdered: [Data] {
        var a: [Data] = []
        if let d = photoData, !d.isEmpty { a.append(d) }
        if let d = secondaryPhotoData, !d.isEmpty { a.append(d) }
        return a
    }

    /// 将云端/演示分析结果写回本条记录（不修改照片、地点、补充说明与创建时间）。
    func applyReanalysis(_ result: HazardAnalysisResult) {
        hazardDescription = result.hazardDescription
        rectificationMeasures = result.rectificationMeasures
        riskLevel = result.riskLevel
        accidentCategoryMajor = result.accidentCategoryMajor
        accidentCategoryMinor = result.accidentCategoryMinor
        legalBasis = result.legalBasis
    }

    /// 是否与「开始排查」相同的最低输入（至少照片或文字其一）。
    func hasMinimumInputForAnalysis() -> Bool {
        let hasPhoto = !sitePhotoDatasOrdered.isEmpty
        let text = (supplementaryText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return hasPhoto || !text.isEmpty
    }

    /// - Returns: 是否已成功持久化；失败时已 `rollback`，不会留下半成品对象。
    @discardableResult
    static func savePayload(
        _ payload: HazardResultPayload,
        context: NSManagedObjectContext
    ) -> Bool {
        let f = InspectionFinding(context: context)
        f.findingId = UUID().uuidString
        let now = Date()
        f.createdAt = now
        f.discoveredAt = now
        let loc = payload.location.trimmingCharacters(in: .whitespacesAndNewlines)
        f.location = loc.isEmpty ? nil : loc
        f.photoData = payload.photoData
        f.secondaryPhotoData = payload.secondaryPhotoData
        let sup = payload.supplementaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        f.supplementaryText = sup.isEmpty ? nil : sup
        f.hazardDescription = payload.analysis.hazardDescription
        f.rectificationMeasures = payload.analysis.rectificationMeasures
        f.riskLevel = payload.analysis.riskLevel
        f.accidentCategoryMajor = payload.analysis.accidentCategoryMajor
        f.accidentCategoryMinor = payload.analysis.accidentCategoryMinor
        f.legalBasis = payload.analysis.legalBasis

        switch payload.rectificationIntent {
        case .immediate:
            if let r = f.startFirstRectificationRound(mode: .immediate, plannedDueAt: nil, context: context) {
                InspectionFinding.applyRectificationPrefill(to: r, from: payload)
            }
        case .scheduled:
            let due = payload.rectificationPlannedDueAt
                ?? Calendar.current.date(byAdding: .day, value: 7, to: now)
                ?? now
            _ = f.startFirstRectificationRound(mode: .scheduled, plannedDueAt: due, context: context)
        }

        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            return false
        }
    }

    /// 将识别页「立即整改」弹窗中的说明与照片写入首轮整改。
    fileprivate static func applyRectificationPrefill(to round: RectificationRound, from payload: HazardResultPayload) {
        let raw = payload.prefillRectificationActionNote.trimmingCharacters(in: .whitespacesAndNewlines)
        round.actionTaken = raw.isEmpty ? nil : raw
        if let d = payload.prefillRectificationPhotoData, !d.isEmpty {
            round.evidencePhotoData = d
        }
    }
}

enum DaySummaryBuilder {
    static func summaries(from findings: [InspectionFinding]) -> [DayInspectionSummary] {
        let cal = Calendar.current
        let withDates = findings.filter { $0.effectiveArchiveDate != nil }
        let grouped = Dictionary(grouping: withDates) { f in
            cal.startOfDay(for: f.effectiveArchiveDate!)
        }

        return grouped.keys.sorted(by: >).map { day in
            let rows = grouped[day]!
            let locs = rows.compactMap { $0.location?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let unique = Array(Set(locs))
            let locText: String
            if unique.isEmpty {
                locText = "未填写地点"
            } else if unique.count == 1 {
                locText = unique[0]
            } else {
                locText = "多地（\(unique.prefix(2).joined(separator: "、"))等）"
            }
            return DayInspectionSummary(calendarDay: day, displayLocation: locText, hazardCount: rows.count)
        }
    }

    static func findings(on day: Date, from all: [InspectionFinding]) -> [InspectionFinding] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return all.filter { f in
            guard let t = f.effectiveArchiveDate else { return false }
            return t >= start && t < end
        }.sorted {
            let a0 = $0.effectiveArchiveDate ?? .distantPast
            let a1 = $1.effectiveArchiveDate ?? .distantPast
            if a0 != a1 { return a0 < a1 }
            return ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }
    }

    static func reportText(for findings: [InspectionFinding], day: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateStyle = .long
        let title = fmt.string(from: day)
        var lines: [String] = [
            "安全大师 · 隐患排查文字报告",
            "日期：\(title)",
            "共 \(findings.count) 条记录",
            String(repeating: "—", count: 24),
            ""
        ]
        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "zh_CN")
        timeFmt.dateStyle = .medium
        timeFmt.timeStyle = .short
        for (i, f) in findings.enumerated() {
            let loc = f.location?.isEmpty == false ? f.location! : "（未填地点）"
            lines.append("【条目 \(i + 1)】地点：\(loc)")
            let disc = f.discoveredAt ?? f.createdAt
            if let disc {
                lines.append("发现时间：\(timeFmt.string(from: disc))")
            }
            let extra = f.supplementaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            lines.append(extra.isEmpty ? "文字说明：（本条未填写）" : "文字说明：\(extra)")
            lines.append("隐患描述：\(f.hazardDescription ?? "")")
            lines.append("整改措施：\(f.rectificationMeasures ?? "")")
            lines.append("风险等级：\(f.riskLevel ?? "")")
            let maj = f.accidentCategoryMajor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let mino = f.accidentCategoryMinor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !maj.isEmpty || !mino.isEmpty {
                lines.append("事故类别：\(maj.isEmpty ? "—" : maj) / \(mino.isEmpty ? "—" : mino)")
            }
            lines.append("整改依据：\(f.legalBasis ?? "")")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
