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
        additionalNotes: String
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
    }

    init(previewData: ReportTemplatePreviewData, reportTitle: String = "安全隐患整改报告") {
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
    }

    func displayValue(_ keyPath: KeyPath<ReportTemplateEditableFields, String>, fallback: String = "未填写") -> String {
        let value = self[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? fallback : value
    }
}
