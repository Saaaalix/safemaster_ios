//
//  HazardInspectionModels.swift
//  安全大师
//

import Foundation

/// 离线/手工保存时写入分析结论的标记，供列表「待补分析」识别。
enum HazardOfflineMarkers {
    static let recordPrefix = "【离线/手工记录】"
}

/// 隐患识别页「整改安排」：立即处理，或先保存后在详情里安排。
enum HazardRectificationIntent: String, Hashable, CaseIterable {
    case immediate
    case scheduled

    var shortLabel: String {
        switch self {
        case .immediate: return "立即整改"
        case .scheduled: return "稍后安排"
        }
    }
}

enum SafetyInspectionScene: String, Hashable, CaseIterable {
    case dormitory = "生活区/宿舍"
    case office = "办公区"
    case construction = "施工现场"
    case other = "其他"
}

struct HazardAnalysisResult: Equatable, Hashable {
    var hazardDescription: String
    var rectificationMeasures: String
    /// 整改闭环「一键采用」草稿；分析时生成，写入 `InspectionFinding`，不自动写入 `actionTaken`。
    var rectificationReplyDraft: String = ""
    var riskLevel: String
    /// 对应《企业职工伤亡事故分类》等常用归类：六大类之一。
    var accidentCategoryMajor: String
    /// 该大类下的具体事故类型（须与 major 对应）。
    var accidentCategoryMinor: String
    var legalBasis: String
}

struct HazardResultPayload: Hashable {
    var photoData: Data?
    /// 第二张现场照片（与 `photoData` 合计最多 2 张）；用于多角度说明同一隐患。
    var secondaryPhotoData: Data? = nil
    var location: String
    var supplementaryText: String
    var analysis: HazardAnalysisResult
    /// 与排查页「整改安排」一致；默认立即。
    var rectificationIntent: HazardRectificationIntent = .immediate
    /// 稍后安排时的计划完成日；识别页可为空，详情页再补。
    var rectificationPlannedDueAt: Date?
    /// 立即整改：在识别页填写的现场说明（写入第 1 轮 `actionTaken`）。
    var prefillRectificationActionNote: String = ""
    /// 立即整改：在识别页选择的整改后/现场照片（写入第 1 轮 `evidencePhotoData`）。
    var prefillRectificationPhotoData: Data?
    /// 稍后安排时：如已选择计划完成日，可在保存成功后写入系统日历提醒。
    var addDeadlineToDeviceCalendar: Bool = false
    /// 用户口述或识别页手选的风险等级；写入 Core Data 时优先于 `analysis.riskLevel`。
    var userRiskLevelOverride: String? = nil
    /// 用户选择的地点分类；用于约束 AI 语境和正式报告用语。
    var sceneType: SafetyInspectionScene = .construction
    /// 用户快记时选择的隐患类型标签；用于详情展示和辅助正式报告语境。
    var hazardTypeTags: [String] = []
    /// 识别页当次填写的项目名称（快照写入 Core Data，与 UserDefaults 封面设置解耦展示）。
    var reportProjectName: String? = nil
    /// 识别页当次填写的检查人。
    var reportInspectorName: String? = nil
    /// 识别页当次填写或带出的整改责任人 / 班组。
    var rectificationResponsiblePerson: String? = nil
    /// 识别页当次填写或带出的责任单位。
    var rectificationResponsibleUnit: String? = nil
}

extension HazardResultPayload {
    /// 主图 + 副图（顺序与录入一致，至多 2 张）。
    var sitePhotoDatasOrdered: [Data] {
        var a: [Data] = []
        if let d = photoData, !d.isEmpty { a.append(d) }
        if let d = secondaryPhotoData, !d.isEmpty { a.append(d) }
        return a
    }
}

extension HazardAnalysisResult {
    /// 无网络或需抢先记录下一处隐患时使用：不调用云端模型与法规检索，便于先落库、有网后再补分析或手改。
    static func offlineManualRecord(supplementaryText: String, location: String, hasPhoto: Bool) -> HazardAnalysisResult {
        let place = location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "（未填地点）" : location
        let userDesc = supplementaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let photoNote = hasPhoto ? "附带现场照片。" : "无照片，仅凭文字记录。"

        let hazard: String
        if userDesc.isEmpty {
            hazard = "\(HazardOfflineMarkers.recordPrefix)\(place)。\(photoNote)隐患情况以照片为准，请后续补充文字说明或重新分析。"
        } else {
            hazard = "\(HazardOfflineMarkers.recordPrefix)地点：\(place)。\(photoNote)\n现场简述：\(userDesc)"
        }

        let draft: String
        if userDesc.isEmpty {
            draft = hasPhoto
                ? "已按现场情况完成初步整改，整改后照片见附件，具体措施待联网重新分析后核对。"
                : ""
        } else {
            draft = hasPhoto
                ? "已针对「\(userDesc)」落实现场整改并完成复查，整改后照片见附件。"
                : "已针对「\(userDesc)」落实整改，具体措施待联网重新分析后核对。"
        }

        return HazardAnalysisResult(
            hazardDescription: hazard,
            rectificationMeasures: "（待联网后使用「AI 辅助分析」对同类内容重新分析以生成措施，或在记录详情中手填。）",
            rectificationReplyDraft: draft,
            riskLevel: "一般风险",
            accidentCategoryMajor: "",
            accidentCategoryMinor: "",
            legalBasis: "（离线记录：未检索法规库、未调用云端模型。恢复网络后可重新分析或对照项目制度。）"
        )
    }
}

struct DayInspectionSummary: Identifiable, Hashable {
    var id: Date { calendarDay }
    var calendarDay: Date
    var displayLocation: String
    var hazardCount: Int
}
