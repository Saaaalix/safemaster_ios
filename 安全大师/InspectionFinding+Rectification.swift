//
//  InspectionFinding+Rectification.swift
//  安全大师
//

import CoreData
import Foundation

enum RectificationMode: String {
    case immediate
    case scheduled
}

enum RectificationStatus: String {
    case inProgress = "in_progress"
    case pendingVerification = "pending_verification"
    case passed
    case failed
}

extension RectificationStatus {
    init?(stored: String?) {
        guard let stored, let v = RectificationStatus(rawValue: stored) else { return nil }
        self = v
    }
}

/// 整改闭环在界面上的阶段（不落库，与导出报告解耦）。
enum RectificationClosureSummary: Equatable {
    case notStarted
    case inProgress(round: Int)
    case awaitingVerification(round: Int)
    case closed(lastRound: Int)
    /// 最近一轮验收不通过，尚未新建下一轮。
    case failedPendingNewRound(round: Int)

    var badgeText: String {
        switch self {
        case .notStarted:
            return "待进入整改"
        case .inProgress(let r):
            return "第 \(r) 轮整改中"
        case .awaitingVerification(let r):
            return "第 \(r) 轮待验收"
        case .closed(let r):
            return "已闭环（第 \(r) 轮通过）"
        case .failedPendingNewRound(let r):
            return "第 \(r) 轮未通过，待开新轮"
        }
    }

    var compactBadgeText: String {
        switch self {
        case .notStarted:
            return "待安排"
        case .inProgress(let r):
            return "第 \(r) 轮整改中"
        case .awaitingVerification(let r):
            return "第 \(r) 轮待验收"
        case .closed(let r):
            return "第 \(r) 轮已闭环"
        case .failedPendingNewRound(let r):
            return "第 \(r) 轮未通过"
        }
    }
}

extension InspectionFinding {
    var rectificationRoundsArray: [RectificationRound] {
        guard let raw = rectificationRounds else { return [] }
        return raw.array
            .compactMap { $0 as? RectificationRound }
            .sorted { $0.roundIndex < $1.roundIndex }
    }

    var latestRectificationRound: RectificationRound? {
        rectificationRoundsArray.last
    }

    /// 子实体 `RectificationRound` 状态变更时通知 SwiftUI / FRC：父记录的 to-many 关系已更新。
    func notifyRectificationRelationshipChanged() {
        willChangeValue(forKey: #keyPath(InspectionFinding.rectificationRounds))
        didChangeValue(forKey: #keyPath(InspectionFinding.rectificationRounds))
    }

    var rectificationClosureSummary: RectificationClosureSummary {
        guard let latest = latestRectificationRound else { return .notStarted }
        let r = Int(latest.roundIndex)
        switch RectificationStatus(stored: latest.status) ?? .inProgress {
        case .inProgress:
            return .inProgress(round: r)
        case .pendingVerification:
            return .awaitingVerification(round: r)
        case .passed:
            return .closed(lastRound: r)
        case .failed:
            return .failedPendingNewRound(round: r)
        }
    }

    /// 最近一轮验收已通过（`rectificationClosureSummary == .closed`）。
    var isRectificationClosed: Bool {
        if case .closed = rectificationClosureSummary { return true }
        return false
    }

    /// 待整改：未闭环（含未开整改、整改中、待验收、验收未通过待新轮）。
    var isPendingRectification: Bool {
        !isRectificationClosed
    }

    /// 整改流程列表口径：只要未闭环就应进入整改流程，字段完整性留给正式报告导出前校验。
    var shouldAppearInRectificationWorkflow: Bool {
        isPendingRectification
    }

    /// 待整改（用于整改功能计数）：仅统计已确认隐患详情且未闭环的记录。
    var isPendingRectificationAfterDetailConfirmed: Bool {
        hasConfirmedDetailFields && isPendingRectification
    }

    /// 新建第一轮整改（立即 / 限期）。
    @discardableResult
    func startFirstRectificationRound(
        mode: RectificationMode,
        plannedDueAt: Date?,
        context: NSManagedObjectContext
    ) -> RectificationRound? {
        guard rectificationRoundsArray.isEmpty else { return nil }
        let round = RectificationRound(context: context)
        round.createdAt = Date()
        round.roundIndex = 1
        round.mode = mode.rawValue
        round.status = RectificationStatus.inProgress.rawValue
        round.plannedDueAt = mode == .scheduled ? plannedDueAt : nil
        addToRectificationRounds(round)
        notifyRectificationRelationshipChanged()
        return round
    }

    /// 在「验收不通过」后开启下一轮。
    @discardableResult
    func startNextRectificationRoundAfterFailure(context: NSManagedObjectContext) -> RectificationRound? {
        guard let latest = latestRectificationRound,
              RectificationStatus(stored: latest.status) == .failed
        else { return nil }
        let nextIndex = Int32(rectificationRoundsArray.map { Int($0.roundIndex) }.max() ?? 0) + 1
        let round = RectificationRound(context: context)
        round.createdAt = Date()
        round.roundIndex = nextIndex
        round.mode = latest.mode ?? RectificationMode.scheduled.rawValue
        round.plannedDueAt = latest.plannedDueAt
        round.responsibleParty = latest.responsibleParty
        round.status = RectificationStatus.inProgress.rawValue
        addToRectificationRounds(round)
        notifyRectificationRelationshipChanged()
        return round
    }
}

extension RectificationRound {
    var statusEnum: RectificationStatus {
        RectificationStatus(stored: status) ?? .inProgress
    }

    var modeEnum: RectificationMode {
        RectificationMode(rawValue: mode ?? "") ?? .scheduled
    }

    private func notifyParentRectificationChanged() {
        finding?.notifyRectificationRelationshipChanged()
    }

    func submitForVerification() throws {
        let text = (actionTaken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw RectificationSaveError.missingActionDescription
        }
        guard let photo = evidencePhotoData, !photo.isEmpty else {
            throw RectificationSaveError.missingEvidencePhoto
        }
        status = RectificationStatus.pendingVerification.rawValue
        notifyParentRectificationChanged()
    }

    func markVerificationPassed(note: String?) throws {
        status = RectificationStatus.passed.rawValue
        verifiedAt = Date()
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        verifierNote = trimmed.isEmpty ? nil : trimmed
        notifyParentRectificationChanged()
    }

    func markVerificationFailed(note: String) throws {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RectificationSaveError.missingFailReason
        }
        status = RectificationStatus.failed.rawValue
        verifiedAt = Date()
        verifierNote = trimmed
        notifyParentRectificationChanged()
    }
}

enum RectificationSaveError: LocalizedError {
    case missingActionDescription
    case missingEvidencePhoto
    case missingFailReason

    var errorDescription: String? {
        switch self {
        case .missingActionDescription:
            return "请先填写「实际整改说明」后再提交验收。"
        case .missingEvidencePhoto:
            return "请先上传「整改后照片」后再提交验收。"
        case .missingFailReason:
            return "验收不通过时请填写原因说明。"
        }
    }
}
