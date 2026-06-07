//
//  ReportTemplatePresets.swift
//  安全大师
//

import Foundation

enum ReportTemplatePresets {
    static var builtInTemplates: [SavedReportTemplate] {
        ReportDocumentKind.allCases.map { defaultTemplate(for: $0) }
    }

    static func defaultTemplate(for kind: ReportDocumentKind) -> SavedReportTemplate {
        switch kind {
        case .hazardNotice:
            return makeTemplate(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                kind: kind,
                name: "隐患排查通知单",
                description: "用于检查方给受检单位下发隐患整改通知。",
                narrativeText: "经现场安全检查，发现以下安全隐患和管理问题。请受检单位按照要求制定整改措施，明确责任人和整改期限，按期完成整改并反馈整改情况。",
                reviewOpinion: "请按期完成整改并反馈整改情况。",
                additionalNotes: "请根据现场检查要求补充整改期限、检查人和接收人。"
            ) { fields in
                fields.rectificationDeadline = "未填写"
                fields.inspector = "未填写"
                fields.receiver = "未填写"
            }
        case .rectificationReply:
            return makeTemplate(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                kind: kind,
                name: "隐患整改回复单",
                description: "用于受检单位向检查单位反馈整改完成情况。",
                narrativeText: "根据隐患排查整改通知要求，项目部对检查发现的问题进行了整改落实，现将整改完成情况回复如下。",
                reviewOpinion: "暂无复查意见",
                additionalNotes: "请根据实际整改情况补充说明。"
            )
        case .safetyEducationRecord:
            return makeTemplate(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                kind: kind,
                name: "安全教育记录",
                description: "用于记录安全教育、班前教育、专项安全培训。",
                narrativeText: "根据安全生产管理要求，组织相关人员开展安全教育培训，现将教育培训情况记录如下。",
                reviewOpinion: "暂无复查意见",
                additionalNotes: "请补充签到、签字或培训效果说明。"
            ) { fields in
                fields.educationTopic = "未填写"
                fields.educationDate = "未填写"
                fields.educationLocation = "未填写"
                fields.lecturer = "未填写"
                fields.participants = "未填写"
                fields.educationContent = "未填写"
            }
        case .monthlyReport:
            return makeTemplate(
                id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                kind: kind,
                name: "安全生产月报",
                description: "用于生成月度隐患排查、整改闭合、安全教育等汇总报告。",
                narrativeText: "本月项目围绕安全生产、隐患排查治理、教育培训和整改闭合等工作开展管理活动，现将本月安全生产工作情况汇总如下。",
                reviewOpinion: "暂无复查意见",
                additionalNotes: "请补充本月整改闭合情况和管理亮点。"
            ) { fields in
                fields.reportMonth = "未填写"
                fields.monthlyInspectionCount = "未填写"
                fields.monthlyHazardCount = "未填写"
                fields.monthlyRectifiedCount = "未填写"
                fields.monthlyUnrectifiedCount = "未填写"
                fields.monthlyEducationCount = "未填写"
                fields.nextMonthPlan = "请填写下月安全生产工作计划。"
            }
        }
    }

    private static func makeTemplate(
        id: UUID,
        kind: ReportDocumentKind,
        name: String,
        description: String,
        narrativeText: String,
        reviewOpinion: String,
        additionalNotes: String,
        configureFields: (inout ReportTemplateEditableFields) -> Void = { _ in }
    ) -> SavedReportTemplate {
        let enabledTypes = kind.recommendedModuleTypes
        let modules = ReportTemplate.defaultModules.enumerated().map { index, module in
            var copy = module
            copy.id = UUID()
            copy.isEnabled = enabledTypes.contains(copy.type)
            copy.sortIndex = enabledTypes.firstIndex(of: copy.type) ?? (enabledTypes.count + index)
            return copy
        }
        let orderOffset = ReportDocumentKind.allCases.firstIndex(of: kind) ?? 0
        let now = Date(timeIntervalSince1970: 1_735_689_600 - Double(orderOffset))
        let template = ReportTemplate(
            id: id,
            name: name,
            modules: modules,
            createdAt: now,
            updatedAt: now
        )
        var editableFields = ReportTemplateEditableFields(
            projectName: "未填写",
            inspectionUnit: "未填写",
            inspectedUnit: "未填写",
            inspectionDate: "未填写",
            reportTitle: kind.defaultReportTitle,
            narrativeText: narrativeText,
            rectificationResponsiblePerson: "未填写",
            safetyDirector: "未填写",
            projectManager: "未填写",
            reviewer: "未填写",
            signatureDate: "未填写",
            reviewOpinion: reviewOpinion,
            additionalNotes: additionalNotes
        )
        configureFields(&editableFields)
        return SavedReportTemplate(
            id: id,
            name: name,
            description: description,
            documentKind: kind,
            template: template,
            editableFields: editableFields,
            updatedAt: now
        )
    }
}
