//
//  ReportTemplatePreviewData.swift
//  安全大师
//

import Foundation

struct ReportTemplatePreviewData {
    var basicInfo: ReportBasicInfoPreviewData
    var narrative: String
    var rectificationItems: [ReportRectificationItemPreviewData]
    var photoComparisons: [ReportPhotoComparisonPreviewData]
    var signature: ReportSignaturePreviewData
    var notes: ReportNotesPreviewData

    init(findings: [InspectionFinding], reportDate: Date = Date()) {
        let sortedFindings = findings.sorted {
            let left = $0.effectiveArchiveDate ?? $0.createdAt ?? .distantPast
            let right = $1.effectiveArchiveDate ?? $1.createdAt ?? .distantPast
            return left < right
        }
        let recordCount = sortedFindings.count

        basicInfo = ReportBasicInfoPreviewData(
            projectName: "未填写",
            inspectionUnit: "未填写",
            inspectedUnit: "未填写",
            inspectionTime: Self.dateTimeText(sortedFindings.first?.effectiveArchiveDate ?? reportDate),
            reportDate: Self.dateText(reportDate),
            recordCount: recordCount
        )
        narrative = "根据安全生产检查要求，检查组对项目现场安全生产、文明施工、临时用电等情况进行了检查。本次共记录隐患 \(recordCount) 项，现将检查及整改情况报告如下。"
        rectificationItems = sortedFindings.enumerated().map { index, finding in
            ReportRectificationItemPreviewData(
                index: index + 1,
                issueDescription: Self.nonEmpty(finding.hazardDescription, fallback: "未填写"),
                rectificationStatus: Self.nonEmpty(finding.latestRectificationRound?.actionTaken ?? finding.rectificationMeasures, fallback: "未填写"),
                riskLevel: Self.nonEmpty(finding.riskLevel, fallback: "未填写"),
                accidentCategory: Self.accidentCategoryText(finding),
                deadline: Self.deadlineText(finding.latestRectificationRound),
                responsibleParty: Self.nonEmpty(finding.latestRectificationRound?.responsibleParty, fallback: "未填写")
            )
        }
        photoComparisons = sortedFindings.enumerated().map { index, finding in
            ReportPhotoComparisonPreviewData(
                index: index + 1,
                beforePhotoData: finding.sitePhotoDatasOrdered.first,
                afterPhotoData: finding.latestRectificationRound?.evidencePhotoData,
                issueDescription: Self.nonEmpty(finding.hazardDescription, fallback: "未填写"),
                rectificationDescription: Self.nonEmpty(finding.latestRectificationRound?.actionTaken ?? finding.rectificationMeasures, fallback: "未填写")
            )
        }
        signature = ReportSignaturePreviewData(
            rectificationResponsible: Self.firstNonEmpty(sortedFindings.compactMap { $0.latestRectificationRound?.responsibleParty }) ?? "未填写",
            safetyDirector: "未填写",
            projectManager: "未填写",
            reviewer: "未填写",
            date: Self.dateText(reportDate)
        )
        notes = ReportNotesPreviewData(
            reviewOpinion: Self.firstNonEmpty(sortedFindings.compactMap { $0.latestRectificationRound?.verifierNote }) ?? "暂无备注",
            supplementaryNotes: Self.firstNonEmpty(sortedFindings.compactMap { $0.supplementaryText }) ?? "暂无备注"
        )
    }

    static var sample: ReportTemplatePreviewData {
        ReportTemplatePreviewData(
            basicInfo: ReportBasicInfoPreviewData(
                projectName: "示例项目",
                inspectionUnit: "安全生产检查组",
                inspectedUnit: "示例受检项目部",
                inspectionTime: dateTimeText(Date()),
                reportDate: dateText(Date()),
                recordCount: 2
            ),
            narrative: "根据安全生产检查要求，检查组对项目现场安全生产、文明施工、临时用电等情况进行了检查。本次共记录隐患 2 项，现将检查及整改情况报告如下。",
            rectificationItems: [
                ReportRectificationItemPreviewData(index: 1, issueDescription: "临边防护缺失", rectificationStatus: "已补设防护栏杆", riskLevel: "一般风险", accidentCategory: "高处坠落", deadline: "立即整改", responsibleParty: "施工班组"),
                ReportRectificationItemPreviewData(index: 2, issueDescription: "材料堆放不整齐", rectificationStatus: "已完成分类码放", riskLevel: "低风险", accidentCategory: "物体打击", deadline: "未填写", responsibleParty: "未填写")
            ],
            photoComparisons: [
                ReportPhotoComparisonPreviewData(index: 1, beforePhotoData: nil, afterPhotoData: nil, issueDescription: "临边防护缺失", rectificationDescription: "已补设防护栏杆")
            ],
            signature: ReportSignaturePreviewData(rectificationResponsible: "施工班组", safetyDirector: "未填写", projectManager: "未填写", reviewer: "未填写", date: dateText(Date())),
            notes: ReportNotesPreviewData(reviewOpinion: "验收通过", supplementaryNotes: "暂无备注")
        )
    }

    private init(
        basicInfo: ReportBasicInfoPreviewData,
        narrative: String,
        rectificationItems: [ReportRectificationItemPreviewData],
        photoComparisons: [ReportPhotoComparisonPreviewData],
        signature: ReportSignaturePreviewData,
        notes: ReportNotesPreviewData
    ) {
        self.basicInfo = basicInfo
        self.narrative = narrative
        self.rectificationItems = rectificationItems
        self.photoComparisons = photoComparisons
        self.signature = signature
        self.notes = notes
    }

    private static func nonEmpty(_ raw: String?, fallback: String) -> String {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? fallback : value
    }

    private static func firstNonEmpty(_ values: [String]) -> String? {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func accidentCategoryText(_ finding: InspectionFinding) -> String {
        let major = finding.accidentCategoryMajor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let minor = finding.accidentCategoryMinor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if major.isEmpty, minor.isEmpty { return "未填写" }
        if major.isEmpty { return minor }
        if minor.isEmpty { return major }
        return "\(major) / \(minor)"
    }

    private static func deadlineText(_ round: RectificationRound?) -> String {
        guard let round else { return "未填写" }
        if round.mode == RectificationMode.immediate.rawValue { return "立即整改" }
        guard let plannedDueAt = round.plannedDueAt else { return "未填写" }
        return dateText(plannedDueAt)
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年MM月dd日"
        return formatter.string(from: date)
    }

    private static func dateTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年MM月dd日 HH:mm"
        return formatter.string(from: date)
    }
}

struct ReportBasicInfoPreviewData {
    var projectName: String
    var inspectionUnit: String
    var inspectedUnit: String
    var inspectionTime: String
    var reportDate: String
    var recordCount: Int
}

struct ReportRectificationItemPreviewData: Identifiable {
    var id: Int { index }
    var index: Int
    var issueDescription: String
    var rectificationStatus: String
    var riskLevel: String
    var accidentCategory: String
    var deadline: String
    var responsibleParty: String
}

struct ReportPhotoComparisonPreviewData: Identifiable {
    var id: Int { index }
    var index: Int
    var beforePhotoData: Data?
    var afterPhotoData: Data?
    var issueDescription: String
    var rectificationDescription: String
}

struct ReportSignaturePreviewData {
    var rectificationResponsible: String
    var safetyDirector: String
    var projectManager: String
    var reviewer: String
    var date: String
}

struct ReportNotesPreviewData {
    var reviewOpinion: String
    var supplementaryNotes: String
}
