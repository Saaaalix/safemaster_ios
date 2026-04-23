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
}

extension InspectionFinding {
    var rectificationRoundsArray: [RectificationRound] {
        guard let raw = rectificationRounds else { return [] }
        let ordered = raw as? NSOrderedSet ?? NSOrderedSet()
        return ordered.compactMap { $0 as? RectificationRound }
    }

    var latestRectificationRound: RectificationRound? {
        rectificationRoundsArray.last
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

    /// 新建第一轮整改（立即 / 限期）。
    @discardableResult
    func startFirstRectificationRound(
        mode: RectificationMode,
        plannedDueAt: Date?,
        context: NSManagedObjectContext
    ) -> RectificationRound? {
        guard rectificationRoundsArray.isEmpty else { return nil }
        let round = RectificationRound(context: context)
        round.finding = self
        round.createdAt = Date()
        round.roundIndex = 1
        round.mode = mode.rawValue
        round.status = RectificationStatus.inProgress.rawValue
        round.plannedDueAt = mode == .scheduled ? plannedDueAt : nil
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
        round.finding = self
        round.createdAt = Date()
        round.roundIndex = nextIndex
        round.mode = latest.mode ?? RectificationMode.scheduled.rawValue
        round.plannedDueAt = latest.plannedDueAt
        round.responsibleParty = latest.responsibleParty
        round.status = RectificationStatus.inProgress.rawValue
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

    func submitForVerification() throws {
        let text = (actionTaken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw RectificationSaveError.missingActionDescription
        }
        status = RectificationStatus.pendingVerification.rawValue
    }

    func markVerificationPassed(note: String?) throws {
        status = RectificationStatus.passed.rawValue
        verifiedAt = Date()
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        verifierNote = trimmed.isEmpty ? nil : trimmed
    }

    func markVerificationFailed(note: String) throws {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RectificationSaveError.missingFailReason
        }
        status = RectificationStatus.failed.rawValue
        verifiedAt = Date()
        verifierNote = trimmed
    }
}

enum RectificationSaveError: LocalizedError {
    case missingActionDescription
    case missingFailReason

    var errorDescription: String? {
        switch self {
        case .missingActionDescription:
            return "请先填写「实际整改说明」后再提交验收。"
        case .missingFailReason:
            return "验收不通过时请填写原因说明。"
        }
    }
}
