//
//  ReportDocumentKind.swift
//  安全大师
//

import Foundation

enum ReportDocumentKind: String, CaseIterable, Codable, Identifiable, Hashable {
    case hazardNotice
    case rectificationReply
    case safetyEducationRecord
    case monthlyReport

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hazardNotice:
            return "隐患排查通知单"
        case .rectificationReply:
            return "隐患整改回复单"
        case .safetyEducationRecord:
            return "安全教育记录"
        case .monthlyReport:
            return "月报"
        }
    }

    var summary: String {
        switch self {
        case .hazardNotice:
            return "用于检查方给受检单位下发隐患整改通知。"
        case .rectificationReply:
            return "用于受检单位向检查单位反馈整改完成情况。"
        case .safetyEducationRecord:
            return "用于记录安全教育、班前教育、专项安全培训。"
        case .monthlyReport:
            return "用于生成月度隐患排查、整改闭合、安全教育等汇总报告。"
        }
    }

    var defaultReportTitle: String {
        switch self {
        case .hazardNotice:
            return "隐患排查整改通知单"
        case .rectificationReply:
            return "隐患整改回复单"
        case .safetyEducationRecord:
            return "安全教育记录"
        case .monthlyReport:
            return "安全生产月报"
        }
    }

    var recommendedModuleTypes: [ReportModuleType] {
        switch self {
        case .hazardNotice:
            return [.basicInfo, .narrative, .rectificationList, .signature, .notes]
        case .rectificationReply:
            return [.basicInfo, .narrative, .rectificationList, .photoComparison, .signature, .notes]
        case .safetyEducationRecord:
            return [.basicInfo, .narrative, .signature, .notes]
        case .monthlyReport:
            return [.basicInfo, .narrative, .rectificationList, .notes]
        }
    }

    var needsHazardRecords: Bool {
        switch self {
        case .hazardNotice, .rectificationReply, .monthlyReport:
            return true
        case .safetyEducationRecord:
            return false
        }
    }

    var needsRectificationRecords: Bool {
        self == .rectificationReply || self == .monthlyReport
    }

    var needsEducationRecordData: Bool {
        self == .safetyEducationRecord
    }

    var needsMonthlySummaryData: Bool {
        self == .monthlyReport
    }
}
