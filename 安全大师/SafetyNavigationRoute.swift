//
//  SafetyNavigationRoute.swift
//  安全大师
//
//  全应用共用一个导航路径类型，避免嵌套 NavigationStack 使用不同路径类型时，
//  SwiftUI 在分栏/列状态下触发 AnyNavigationPath.comparisonTypeMismatch 崩溃。

import Foundation

enum SafetyNavigationRoute: Hashable {
    case hazardInspection
    case profile
    case hazardResult(id: UUID, payload: HazardResultPayload)
    /// 主页「隐患整改」：待整改 / 整改完成双入口根页。
    case hazardRecords
    /// 从工作台指标直接进入整改分类列表（待整改/已闭环）。
    case hazardRecordsCategory(InspectionRecordListCategory)
    /// 工作台：高风险隐患快速入口。
    case highRiskFindings
    /// 工作台：今日新增（排查/教育）快速入口。
    case todayActivities
    /// 隐患识别页底部「排查记录」：按条展示的扁平列表。
    case inspectionRecordFlatList
    /// 安全教育：拍照留痕、生成教育记录。
    case safetyEducation
    /// 月度工作总结：汇总排查、整改和教育数据。
    case monthlySummary
    /// 文书中心：导入文件、套用模板、查看存档报告。
    case documentCenter
    /// 报告模板：配置导出标题、字段、照片布局与签字栏。
    case reportTemplate
    /// 报告存档：查看、预览和分享已经生成并保存的报告。
    case reportArchive
    case hazardLibrary
    /// 导入箱：先存文件，再选择是否识别与建档。
    case importedNoticeInbox
}
