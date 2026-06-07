//
//  ReportTemplateEditableFields.swift
//  安全大师
//

import Foundation

struct ReportTemplateEditableFields: Codable, Equatable, Hashable {
    var projectName: String
    var inspectionUnit: String
    var inspectedUnit: String
    var inspectionDate: String
    var reportTitle: String
    var narrativeText: String
    var rectificationResponsiblePerson: String
    var safetyDirector: String
    var projectManager: String
    var reviewer: String
    var signatureDate: String
    var reviewOpinion: String
    var additionalNotes: String
    var noticeNumber: String
    var rectificationDeadline: String
    var inspector: String
    var receiver: String
    var educationTopic: String
    var educationDate: String
    var educationLocation: String
    var lecturer: String
    var participants: String
    var educationContent: String
    var reportMonth: String
    var monthlyInspectionCount: String
    var monthlyHazardCount: String
    var monthlyRectifiedCount: String
    var monthlyUnrectifiedCount: String
    var monthlyEducationCount: String
    var nextMonthPlan: String

    init(
        projectName: String,
        inspectionUnit: String,
        inspectedUnit: String,
        inspectionDate: String,
        reportTitle: String,
        narrativeText: String,
        rectificationResponsiblePerson: String,
        safetyDirector: String,
        projectManager: String,
        reviewer: String,
        signatureDate: String,
        reviewOpinion: String,
        additionalNotes: String,
        noticeNumber: String = "",
        rectificationDeadline: String = "",
        inspector: String = "",
        receiver: String = "",
        educationTopic: String = "",
        educationDate: String = "",
        educationLocation: String = "",
        lecturer: String = "",
        participants: String = "",
        educationContent: String = "",
        reportMonth: String = "",
        monthlyInspectionCount: String = "",
        monthlyHazardCount: String = "",
        monthlyRectifiedCount: String = "",
        monthlyUnrectifiedCount: String = "",
        monthlyEducationCount: String = "",
        nextMonthPlan: String = ""
    ) {
        self.projectName = projectName
        self.inspectionUnit = inspectionUnit
        self.inspectedUnit = inspectedUnit
        self.inspectionDate = inspectionDate
        self.reportTitle = reportTitle
        self.narrativeText = narrativeText
        self.rectificationResponsiblePerson = rectificationResponsiblePerson
        self.safetyDirector = safetyDirector
        self.projectManager = projectManager
        self.reviewer = reviewer
        self.signatureDate = signatureDate
        self.reviewOpinion = reviewOpinion
        self.additionalNotes = additionalNotes
        self.noticeNumber = noticeNumber
        self.rectificationDeadline = rectificationDeadline
        self.inspector = inspector
        self.receiver = receiver
        self.educationTopic = educationTopic
        self.educationDate = educationDate
        self.educationLocation = educationLocation
        self.lecturer = lecturer
        self.participants = participants
        self.educationContent = educationContent
        self.reportMonth = reportMonth
        self.monthlyInspectionCount = monthlyInspectionCount
        self.monthlyHazardCount = monthlyHazardCount
        self.monthlyRectifiedCount = monthlyRectifiedCount
        self.monthlyUnrectifiedCount = monthlyUnrectifiedCount
        self.monthlyEducationCount = monthlyEducationCount
        self.nextMonthPlan = nextMonthPlan
    }

    init(previewData: ReportTemplatePreviewData, reportTitle: String = "安全隐患整改报告") {
        let rectifiedCount = previewData.rectificationItems.filter {
            !$0.rectificationStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.rectificationStatus != "未填写"
        }.count
        self.projectName = previewData.basicInfo.projectName
        self.inspectionUnit = previewData.basicInfo.inspectionUnit
        self.inspectedUnit = previewData.basicInfo.inspectedUnit
        self.inspectionDate = previewData.basicInfo.inspectionTime
        self.reportTitle = reportTitle
        self.narrativeText = previewData.narrative
        self.rectificationResponsiblePerson = previewData.signature.rectificationResponsible
        self.safetyDirector = previewData.signature.safetyDirector
        self.projectManager = previewData.signature.projectManager
        self.reviewer = previewData.signature.reviewer
        self.signatureDate = previewData.signature.date
        self.reviewOpinion = previewData.notes.reviewOpinion
        self.additionalNotes = previewData.notes.supplementaryNotes
        self.noticeNumber = ""
        self.rectificationDeadline = previewData.rectificationItems.first?.deadline ?? ""
        self.inspector = ""
        self.receiver = ""
        self.educationTopic = ""
        self.educationDate = previewData.basicInfo.inspectionTime
        self.educationLocation = ""
        self.lecturer = ""
        self.participants = ""
        self.educationContent = ""
        self.reportMonth = Self.monthText(Date())
        self.monthlyInspectionCount = previewData.basicInfo.recordCount > 0 ? "1" : "0"
        self.monthlyHazardCount = "\(previewData.basicInfo.recordCount)"
        self.monthlyRectifiedCount = "\(rectifiedCount)"
        self.monthlyUnrectifiedCount = "\(max(0, previewData.basicInfo.recordCount - rectifiedCount))"
        self.monthlyEducationCount = ""
        self.nextMonthPlan = ""
    }

    func displayValue(_ keyPath: KeyPath<ReportTemplateEditableFields, String>, fallback: String = "未填写") -> String {
        let value = self[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? fallback : value
    }

    private enum CodingKeys: String, CodingKey {
        case projectName
        case inspectionUnit
        case inspectedUnit
        case inspectionDate
        case reportTitle
        case narrativeText
        case rectificationResponsiblePerson
        case safetyDirector
        case projectManager
        case reviewer
        case signatureDate
        case reviewOpinion
        case additionalNotes
        case noticeNumber
        case rectificationDeadline
        case inspector
        case receiver
        case educationTopic
        case educationDate
        case educationLocation
        case lecturer
        case participants
        case educationContent
        case reportMonth
        case monthlyInspectionCount
        case monthlyHazardCount
        case monthlyRectifiedCount
        case monthlyUnrectifiedCount
        case monthlyEducationCount
        case nextMonthPlan
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.projectName = try container.decodeIfPresent(String.self, forKey: .projectName) ?? ""
        self.inspectionUnit = try container.decodeIfPresent(String.self, forKey: .inspectionUnit) ?? ""
        self.inspectedUnit = try container.decodeIfPresent(String.self, forKey: .inspectedUnit) ?? ""
        self.inspectionDate = try container.decodeIfPresent(String.self, forKey: .inspectionDate) ?? ""
        self.reportTitle = try container.decodeIfPresent(String.self, forKey: .reportTitle) ?? ""
        self.narrativeText = try container.decodeIfPresent(String.self, forKey: .narrativeText) ?? ""
        self.rectificationResponsiblePerson = try container.decodeIfPresent(String.self, forKey: .rectificationResponsiblePerson) ?? ""
        self.safetyDirector = try container.decodeIfPresent(String.self, forKey: .safetyDirector) ?? ""
        self.projectManager = try container.decodeIfPresent(String.self, forKey: .projectManager) ?? ""
        self.reviewer = try container.decodeIfPresent(String.self, forKey: .reviewer) ?? ""
        self.signatureDate = try container.decodeIfPresent(String.self, forKey: .signatureDate) ?? ""
        self.reviewOpinion = try container.decodeIfPresent(String.self, forKey: .reviewOpinion) ?? ""
        self.additionalNotes = try container.decodeIfPresent(String.self, forKey: .additionalNotes) ?? ""
        self.noticeNumber = try container.decodeIfPresent(String.self, forKey: .noticeNumber) ?? ""
        self.rectificationDeadline = try container.decodeIfPresent(String.self, forKey: .rectificationDeadline) ?? ""
        self.inspector = try container.decodeIfPresent(String.self, forKey: .inspector) ?? ""
        self.receiver = try container.decodeIfPresent(String.self, forKey: .receiver) ?? ""
        self.educationTopic = try container.decodeIfPresent(String.self, forKey: .educationTopic) ?? ""
        self.educationDate = try container.decodeIfPresent(String.self, forKey: .educationDate) ?? ""
        self.educationLocation = try container.decodeIfPresent(String.self, forKey: .educationLocation) ?? ""
        self.lecturer = try container.decodeIfPresent(String.self, forKey: .lecturer) ?? ""
        self.participants = try container.decodeIfPresent(String.self, forKey: .participants) ?? ""
        self.educationContent = try container.decodeIfPresent(String.self, forKey: .educationContent) ?? ""
        self.reportMonth = try container.decodeIfPresent(String.self, forKey: .reportMonth) ?? ""
        self.monthlyInspectionCount = try container.decodeIfPresent(String.self, forKey: .monthlyInspectionCount) ?? ""
        self.monthlyHazardCount = try container.decodeIfPresent(String.self, forKey: .monthlyHazardCount) ?? ""
        self.monthlyRectifiedCount = try container.decodeIfPresent(String.self, forKey: .monthlyRectifiedCount) ?? ""
        self.monthlyUnrectifiedCount = try container.decodeIfPresent(String.self, forKey: .monthlyUnrectifiedCount) ?? ""
        self.monthlyEducationCount = try container.decodeIfPresent(String.self, forKey: .monthlyEducationCount) ?? ""
        self.nextMonthPlan = try container.decodeIfPresent(String.self, forKey: .nextMonthPlan) ?? ""
    }

    private static func monthText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年MM月"
        return formatter.string(from: date)
    }
}
