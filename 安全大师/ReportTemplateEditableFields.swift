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
