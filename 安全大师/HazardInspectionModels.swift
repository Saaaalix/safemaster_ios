//
//  HazardInspectionModels.swift
//  安全大师
//

import Foundation

/// 隐患识别页「整改安排」：仅立即 / 限期；保存时均会建立第 1 轮整改。
enum HazardRectificationIntent: String, Hashable, CaseIterable {
    case immediate
    case scheduled

    var shortLabel: String {
        switch self {
        case .immediate: return "立即"
        case .scheduled: return "限期"
        }
    }
}

struct HazardAnalysisResult: Equatable, Hashable {
    var hazardDescription: String
    var rectificationMeasures: String
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
    /// 限期整改时的计划完成日；仅 `rectificationIntent == .scheduled` 时使用。
    var rectificationPlannedDueAt: Date?
    /// 立即整改：在识别页填写的现场说明（写入第 1 轮 `actionTaken`）。
    var prefillRectificationActionNote: String = ""
    /// 立即整改：在识别页选择的整改后/现场照片（写入第 1 轮 `evidencePhotoData`）。
    var prefillRectificationPhotoData: Data?
    /// 限期整改：是否在保存成功后写入系统日历提醒。
    var addDeadlineToDeviceCalendar: Bool = false
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
            hazard = "【离线/手工记录】\(place)。\(photoNote)隐患情况以照片为准，请后续补充文字说明或重新分析。"
        } else {
            hazard = "【离线/手工记录】地点：\(place)。\(photoNote)\n现场简述：\(userDesc)"
        }

        return HazardAnalysisResult(
            hazardDescription: hazard,
            rectificationMeasures: "（待联网后使用「开始排查」对同类内容重新分析以生成措施，或在记录详情中手填。）",
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
