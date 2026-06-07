//
//  ReportTemplatePresets.swift
//  安全大师
//

import Foundation

enum ReportTemplatePresets {
    static var builtInTemplates: [SavedReportTemplate] {
        [
            rectificationReply,
            fieldRectificationList,
            safetyInspectionAssessment
        ]
    }

    private static var rectificationReply: SavedReportTemplate {
        makeTemplate(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "整改回复报告",
            description: "适合向检查单位提交整改完成情况，包含正文说明、整改清单、图文对比和签字审批。",
            enabledTypes: [.basicInfo, .narrative, .rectificationList, .photoComparison, .signature, .notes],
            reportTitle: "安全生产检查问题整改回复报告",
            narrativeText: "根据安全生产检查要求，项目部对检查发现的问题进行了认真梳理和整改落实，现将整改情况报告如下。",
            reviewOpinion: "暂无复查意见",
            additionalNotes: "请根据实际整改情况补充说明。"
        )
    }

    private static var fieldRectificationList: SavedReportTemplate {
        makeTemplate(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "现场隐患整改清单",
            description: "适合导出现场问题清单，重点展示问题描述、整改情况、整改前后照片。",
            enabledTypes: [.basicInfo, .rectificationList, .photoComparison, .notes],
            reportTitle: "现场隐患问题整改回复清单",
            narrativeText: "",
            reviewOpinion: "暂无复查意见",
            additionalNotes: "本清单用于记录现场隐患问题及整改闭合情况。"
        )
    }

    private static var safetyInspectionAssessment: SavedReportTemplate {
        makeTemplate(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "安全生产检查考核记录表",
            description: "适合正式检查考核记录，包含基本信息、正文说明、限期整改问题、签字审批和复查意见。",
            enabledTypes: [.basicInfo, .narrative, .rectificationList, .signature, .notes],
            reportTitle: "安全生产检查考核记录表",
            narrativeText: "根据安全生产管理要求，检查组对项目安全生产、职业健康、文明施工、临时用电等情况进行了检查，现将检查情况记录如下。",
            reviewOpinion: "整改完成后由复查人员填写闭合意见。",
            additionalNotes: "暂无备注"
        )
    }

    private static func makeTemplate(
        id: UUID,
        name: String,
        description: String,
        enabledTypes: [ReportModuleType],
        reportTitle: String,
        narrativeText: String,
        reviewOpinion: String,
        additionalNotes: String
    ) -> SavedReportTemplate {
        let modules = ReportTemplate.defaultModules.enumerated().map { index, module in
            var copy = module
            copy.id = UUID()
            copy.isEnabled = enabledTypes.contains(copy.type)
            copy.sortIndex = enabledTypes.firstIndex(of: copy.type) ?? (enabledTypes.count + index)
            return copy
        }
        let now = Date(timeIntervalSince1970: 1_735_689_600)
        let template = ReportTemplate(
            id: id,
            name: name,
            modules: modules,
            createdAt: now,
            updatedAt: now
        )
        let editableFields = ReportTemplateEditableFields(
            projectName: "未填写",
            inspectionUnit: "未填写",
            inspectedUnit: "未填写",
            inspectionDate: "未填写",
            reportTitle: reportTitle,
            narrativeText: narrativeText,
            rectificationResponsiblePerson: "未填写",
            safetyDirector: "未填写",
            projectManager: "未填写",
            reviewer: "未填写",
            signatureDate: "未填写",
            reviewOpinion: reviewOpinion,
            additionalNotes: additionalNotes
        )
        return SavedReportTemplate(
            id: id,
            name: name,
            description: description,
            template: template,
            editableFields: editableFields,
            updatedAt: now
        )
    }
}
