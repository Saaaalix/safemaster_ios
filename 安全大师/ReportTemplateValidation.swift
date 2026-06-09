//
//  ReportTemplateValidation.swift
//  安全大师
//

import Foundation

enum ReportTemplateValidationSeverity: String, CaseIterable, Codable, Hashable {
    case error
    case warning

    var title: String {
        switch self {
        case .error:
            return "必须补充"
        case .warning:
            return "建议补充"
        }
    }

    var explanation: String {
        switch self {
        case .error:
            return "影响正式报告生成"
        case .warning:
            return "不影响生成，但建议完善"
        }
    }
}

struct ReportTemplateValidationIssue: Identifiable, Equatable, Hashable {
    let id = UUID()
    var severity: ReportTemplateValidationSeverity
    var moduleTitle: String
    var title: String
    var message: String
}

enum ReportTemplateValidator {
    static func validate(
        template: ReportTemplate,
        previewData: ReportTemplatePreviewData,
        editableFields: ReportTemplateEditableFields,
        documentKind: ReportDocumentKind = .rectificationReply
    ) -> [ReportTemplateValidationIssue] {
        var issues: [ReportTemplateValidationIssue] = []

        appendTitleIssueIfNeeded(editableFields: editableFields, template: template, issues: &issues)

        switch documentKind {
        case .hazardNotice:
            validateHazardNotice(template: template, previewData: previewData, editableFields: editableFields, issues: &issues)
        case .rectificationReply:
            validateRectificationReply(template: template, previewData: previewData, editableFields: editableFields, issues: &issues)
        case .safetyEducationRecord:
            validateSafetyEducationRecord(template: template, editableFields: editableFields, issues: &issues)
        case .monthlyReport:
            validateMonthlyReport(template: template, previewData: previewData, editableFields: editableFields, issues: &issues)
        }

        return issues.sorted {
            if $0.severity == $1.severity {
                return $0.moduleTitle.localizedStandardCompare($1.moduleTitle) == .orderedAscending
            }
            return $0.severity == .error
        }
    }

    private static func validateHazardNotice(
        template: ReportTemplate,
        previewData: ReportTemplatePreviewData,
        editableFields: ReportTemplateEditableFields,
        issues: inout [ReportTemplateValidationIssue]
    ) {
        let infoModule = moduleTitle(.basicInfo, in: template, fallback: "基本信息")
        if isEnabled(.basicInfo, in: template) {
            appendMissingEditableFieldIssue(value: editableFields.inspectionUnit, fieldName: "检查单位", moduleTitle: infoModule, severity: .error, issues: &issues)
            appendMissingEditableFieldIssue(value: editableFields.inspectedUnit, fieldName: "受检单位", moduleTitle: infoModule, severity: .error, issues: &issues)
            appendMissingEditableFieldIssue(value: editableFields.inspectionDate, fieldName: "检查时间", moduleTitle: infoModule, severity: .error, issues: &issues)
            appendMissingEditableFieldIssue(value: editableFields.rectificationDeadline, fieldName: "整改期限", moduleTitle: infoModule, severity: .error, issues: &issues)
            appendMissingEditableFieldIssue(value: editableFields.inspector, fieldName: "检查人", moduleTitle: infoModule, severity: .warning, issues: &issues)
            appendMissingEditableFieldIssue(value: editableFields.receiver, fieldName: "接收人", moduleTitle: infoModule, severity: .warning, issues: &issues)
        }

        guard isEnabled(.rectificationList, in: template) else { return }
        let listModule = moduleTitle(.rectificationList, in: template, fallback: "整改清单")
        guard !previewData.rectificationItems.isEmpty else {
            appendIssue(.error, moduleTitle: listModule, title: "缺少隐患记录", message: "隐患排查通知单需要列出需要整改的隐患问题。", issues: &issues)
            return
        }
        for item in previewData.rectificationItems {
            appendMissingRecordIssue(value: item.issueDescription, recordIndex: item.index, fieldName: "隐患描述", moduleTitle: listModule, severity: .error, issues: &issues)
            appendMissingRecordIssue(value: item.deadline, recordIndex: item.index, fieldName: "整改期限", moduleTitle: listModule, severity: .error, issues: &issues)
            appendMissingRecordIssue(value: item.responsibleParty, recordIndex: item.index, fieldName: "责任人", moduleTitle: listModule, severity: .error, issues: &issues)
        }
    }

    private static func validateRectificationReply(
        template: ReportTemplate,
        previewData: ReportTemplatePreviewData,
        editableFields: ReportTemplateEditableFields,
        issues: inout [ReportTemplateValidationIssue]
    ) {
        let signatureModule = moduleTitle(.signature, in: template, fallback: "签字确认")
        if isEnabled(.signature, in: template) {
            appendMissingEditableFieldIssue(value: editableFields.rectificationResponsiblePerson, fieldName: "整改负责人", moduleTitle: signatureModule, severity: .warning, issues: &issues)
        }

        guard isEnabled(.rectificationList, in: template) else { return }
        let listModule = moduleTitle(.rectificationList, in: template, fallback: "整改清单")
        guard !previewData.rectificationItems.isEmpty else {
            appendIssue(.error, moduleTitle: listModule, title: "缺少隐患记录", message: "隐患整改回复单需要展示整改问题和整改情况。", issues: &issues)
            return
        }
        for item in previewData.rectificationItems {
            appendMissingRecordIssue(value: item.rectificationStatus, recordIndex: item.index, fieldName: "整改情况", moduleTitle: listModule, severity: .error, issues: &issues)
        }

        if isEnabled(.photoComparison, in: template) {
            let photoModule = moduleTitle(.photoComparison, in: template, fallback: "照片对比")
            for item in previewData.photoComparisons where item.afterPhotoData == nil {
                appendIssue(.warning, moduleTitle: photoModule, title: "第 \(item.index) 条缺少整改后照片", message: "整改回复单建议补充整改后照片，便于体现闭合结果。", issues: &issues)
            }
        }

        if isEnabled(.notes, in: template) {
            appendMissingEditableFieldIssue(value: editableFields.reviewOpinion, fieldName: "复查意见", moduleTitle: moduleTitle(.notes, in: template, fallback: "备注"), severity: .warning, issues: &issues)
        }
    }

    private static func validateSafetyEducationRecord(
        template: ReportTemplate,
        editableFields: ReportTemplateEditableFields,
        issues: inout [ReportTemplateValidationIssue]
    ) {
        let infoModule = moduleTitle(.basicInfo, in: template, fallback: "基本信息")
        if isEnabled(.basicInfo, in: template) {
            appendMissingEditableFieldIssue(value: editableFields.educationTopic, fieldName: "教育主题", moduleTitle: infoModule, severity: .error, issues: &issues)
            appendMissingEditableFieldIssue(value: editableFields.educationDate, fieldName: "教育时间", moduleTitle: infoModule, severity: .error, issues: &issues)
            appendMissingEditableFieldIssue(value: editableFields.educationLocation, fieldName: "教育地点", moduleTitle: infoModule, severity: .warning, issues: &issues)
            appendMissingEditableFieldIssue(value: editableFields.lecturer, fieldName: "主讲人", moduleTitle: infoModule, severity: .warning, issues: &issues)
            appendMissingEditableFieldIssue(value: editableFields.participants, fieldName: "参加人员或签字说明", moduleTitle: infoModule, severity: .warning, issues: &issues)
        }
        if isEnabled(.notes, in: template) {
            appendMissingEditableFieldIssue(value: editableFields.educationContent, fieldName: "教育内容", moduleTitle: moduleTitle(.notes, in: template, fallback: "备注"), severity: .error, issues: &issues)
        }
    }

    private static func validateMonthlyReport(
        template: ReportTemplate,
        previewData: ReportTemplatePreviewData,
        editableFields: ReportTemplateEditableFields,
        issues: inout [ReportTemplateValidationIssue]
    ) {
        let infoModule = moduleTitle(.basicInfo, in: template, fallback: "基本信息")
        if isEnabled(.basicInfo, in: template) {
            appendMissingEditableFieldIssue(value: editableFields.reportMonth, fieldName: "月份", moduleTitle: infoModule, severity: .error, issues: &issues)
            if isMissing(editableFields.monthlyHazardCount), previewData.basicInfo.recordCount == 0 {
                appendMissingEditableFieldIssue(value: editableFields.narrativeText, fieldName: "本月隐患数量或统计说明", moduleTitle: infoModule, severity: .warning, issues: &issues)
            }
            appendMissingEditableFieldIssue(value: editableFields.monthlyRectifiedCount, fieldName: "本月整改情况", moduleTitle: infoModule, severity: .warning, issues: &issues)
        }
        if isEnabled(.notes, in: template) {
            appendMissingEditableFieldIssue(value: editableFields.nextMonthPlan.isEmpty ? editableFields.additionalNotes : editableFields.nextMonthPlan, fieldName: "下月计划或备注", moduleTitle: moduleTitle(.notes, in: template, fallback: "备注"), severity: .warning, issues: &issues)
        }
    }

    private static func appendTitleIssueIfNeeded(
        editableFields: ReportTemplateEditableFields,
        template: ReportTemplate,
        issues: inout [ReportTemplateValidationIssue]
    ) {
        guard isEnabled(.basicInfo, in: template) else { return }
        appendMissingEditableFieldIssue(
            value: editableFields.reportTitle,
            fieldName: "报告标题",
            moduleTitle: moduleTitle(.basicInfo, in: template, fallback: "基本信息"),
            severity: .error,
            issues: &issues
        )
    }

    private static func appendMissingEditableFieldIssue(
        value: String,
        fieldName: String,
        moduleTitle: String,
        severity: ReportTemplateValidationSeverity,
        issues: inout [ReportTemplateValidationIssue]
    ) {
        guard isMissing(value) else { return }
        appendIssue(severity, moduleTitle: moduleTitle, title: "\(fieldName)未填写", message: "请补充\(fieldName)，避免导出的文书内容不完整。", issues: &issues)
    }

    private static func appendMissingRecordIssue(
        value: String,
        recordIndex: Int,
        fieldName: String,
        moduleTitle: String,
        severity: ReportTemplateValidationSeverity,
        issues: inout [ReportTemplateValidationIssue]
    ) {
        guard isMissing(value) else { return }
        appendIssue(severity, moduleTitle: moduleTitle, title: "第 \(recordIndex) 条\(fieldName)缺失", message: "建议补充第 \(recordIndex) 条记录的\(fieldName)。", issues: &issues)
    }

    private static func appendIssue(
        _ severity: ReportTemplateValidationSeverity,
        moduleTitle: String,
        title: String,
        message: String,
        issues: inout [ReportTemplateValidationIssue]
    ) {
        issues.append(
            ReportTemplateValidationIssue(
                severity: severity,
                moduleTitle: moduleTitle,
                title: title,
                message: message
            )
        )
    }

    private static func isEnabled(_ type: ReportModuleType, in template: ReportTemplate) -> Bool {
        template.modules.first { $0.type == type }?.isEnabled == true
    }

    private static func moduleTitle(_ type: ReportModuleType, in template: ReportTemplate, fallback: String) -> String {
        template.modules.first { $0.type == type }?.title ?? fallback
    }

    private static func isMissing(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        return ["未填写", "暂无备注", "无", "—", "-", "N/A", "n/a"].contains(normalized)
    }
}
