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
            return "严重缺失"
        case .warning:
            return "建议补充"
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
        editableFields: ReportTemplateEditableFields
    ) -> [ReportTemplateValidationIssue] {
        var issues: [ReportTemplateValidationIssue] = []

        if isEnabled(.basicInfo, in: template) {
            let module = moduleTitle(.basicInfo, in: template, fallback: "基本信息")
            appendMissingEditableFieldIssue(
                value: editableFields.reportTitle,
                fieldName: "报告标题",
                moduleTitle: module,
                severity: .error,
                issues: &issues
            )
            appendMissingEditableFieldIssue(
                value: editableFields.projectName,
                fieldName: "项目名称",
                moduleTitle: module,
                severity: .error,
                issues: &issues
            )
            appendMissingEditableFieldIssue(
                value: editableFields.inspectionUnit,
                fieldName: "检查单位",
                moduleTitle: module,
                severity: .error,
                issues: &issues
            )
            appendMissingEditableFieldIssue(
                value: editableFields.inspectedUnit,
                fieldName: "受检单位",
                moduleTitle: module,
                severity: .error,
                issues: &issues
            )
            appendMissingEditableFieldIssue(
                value: editableFields.inspectionDate,
                fieldName: "检查时间",
                moduleTitle: module,
                severity: .error,
                issues: &issues
            )
        }

        if isEnabled(.narrative, in: template) {
            let module = moduleTitle(.narrative, in: template, fallback: "隐患描述")
            appendMissingEditableFieldIssue(
                value: editableFields.narrativeText,
                fieldName: "正文说明",
                moduleTitle: module,
                severity: .warning,
                issues: &issues
            )
        }

        if isEnabled(.rectificationList, in: template) {
            validateRectificationList(
                items: previewData.rectificationItems,
                moduleTitle: moduleTitle(.rectificationList, in: template, fallback: "整改清单"),
                issues: &issues
            )
        }

        if isEnabled(.photoComparison, in: template) {
            validatePhotoComparisons(
                items: previewData.photoComparisons,
                moduleTitle: moduleTitle(.photoComparison, in: template, fallback: "照片对比"),
                issues: &issues
            )
        }

        if isEnabled(.signature, in: template) {
            let module = moduleTitle(.signature, in: template, fallback: "签字确认")
            [
                ("整改负责人", editableFields.rectificationResponsiblePerson),
                ("安全总监", editableFields.safetyDirector),
                ("项目负责人", editableFields.projectManager),
                ("复查人", editableFields.reviewer),
                ("日期", editableFields.signatureDate)
            ].forEach { fieldName, value in
                appendMissingEditableFieldIssue(
                    value: value,
                    fieldName: fieldName,
                    moduleTitle: module,
                    severity: .warning,
                    issues: &issues
                )
            }
        }

        if isEnabled(.notes, in: template) {
            let module = moduleTitle(.notes, in: template, fallback: "备注")
            appendMissingEditableFieldIssue(
                value: editableFields.reviewOpinion,
                fieldName: "复查意见",
                moduleTitle: module,
                severity: .warning,
                issues: &issues
            )
            appendMissingEditableFieldIssue(
                value: editableFields.additionalNotes,
                fieldName: "补充说明",
                moduleTitle: module,
                severity: .warning,
                issues: &issues
            )
        }

        return issues.sorted {
            if $0.severity == $1.severity {
                return $0.moduleTitle.localizedStandardCompare($1.moduleTitle) == .orderedAscending
            }
            return $0.severity == .error
        }
    }

    private static func validateRectificationList(
        items: [ReportRectificationItemPreviewData],
        moduleTitle: String,
        issues: inout [ReportTemplateValidationIssue]
    ) {
        guard !items.isEmpty else {
            issues.append(
                ReportTemplateValidationIssue(
                    severity: .error,
                    moduleTitle: moduleTitle,
                    title: "缺少隐患记录",
                    message: "当前模板启用了整改清单，但没有可展示的隐患记录。"
                )
            )
            return
        }

        for item in items {
            appendMissingRecordIssue(
                value: item.issueDescription,
                recordIndex: item.index,
                fieldName: "隐患描述",
                moduleTitle: moduleTitle,
                severity: .error,
                issues: &issues
            )
            appendMissingRecordIssue(
                value: item.rectificationStatus,
                recordIndex: item.index,
                fieldName: "整改措施/整改情况",
                moduleTitle: moduleTitle,
                severity: .error,
                issues: &issues
            )
            appendMissingRecordIssue(
                value: item.responsibleParty,
                recordIndex: item.index,
                fieldName: "责任人",
                moduleTitle: moduleTitle,
                severity: .warning,
                issues: &issues
            )
            appendMissingRecordIssue(
                value: item.riskLevel,
                recordIndex: item.index,
                fieldName: "风险等级",
                moduleTitle: moduleTitle,
                severity: .warning,
                issues: &issues
            )
        }
    }

    private static func validatePhotoComparisons(
        items: [ReportPhotoComparisonPreviewData],
        moduleTitle: String,
        issues: inout [ReportTemplateValidationIssue]
    ) {
        guard !items.isEmpty else {
            issues.append(
                ReportTemplateValidationIssue(
                    severity: .warning,
                    moduleTitle: moduleTitle,
                    title: "缺少图文对比记录",
                    message: "当前模板启用了图文对比，但没有可展示的隐患记录。"
                )
            )
            return
        }

        for item in items {
            if item.beforePhotoData == nil {
                issues.append(
                    ReportTemplateValidationIssue(
                        severity: .warning,
                        moduleTitle: moduleTitle,
                        title: "第 \(item.index) 条缺少整改前照片",
                        message: "建议补充整改前照片，便于在报告中对比问题现场。"
                    )
                )
            }
            if item.afterPhotoData == nil {
                issues.append(
                    ReportTemplateValidationIssue(
                        severity: .warning,
                        moduleTitle: moduleTitle,
                        title: "第 \(item.index) 条缺少整改后照片",
                        message: "建议补充整改后照片，便于体现整改闭合情况。"
                    )
                )
            }
            appendMissingRecordIssue(
                value: item.rectificationDescription,
                recordIndex: item.index,
                fieldName: "整改说明",
                moduleTitle: moduleTitle,
                severity: .warning,
                issues: &issues
            )
        }
    }

    private static func appendMissingEditableFieldIssue(
        value: String,
        fieldName: String,
        moduleTitle: String,
        severity: ReportTemplateValidationSeverity,
        issues: inout [ReportTemplateValidationIssue]
    ) {
        guard isMissing(value) else { return }
        issues.append(
            ReportTemplateValidationIssue(
                severity: severity,
                moduleTitle: moduleTitle,
                title: "\(fieldName)未填写",
                message: "请补充\(fieldName)，避免导出的报告内容不完整。"
            )
        )
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
        issues.append(
            ReportTemplateValidationIssue(
                severity: severity,
                moduleTitle: moduleTitle,
                title: "第 \(recordIndex) 条\(fieldName)缺失",
                message: "建议补充第 \(recordIndex) 条记录的\(fieldName)。"
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
