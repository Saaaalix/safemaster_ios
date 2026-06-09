//
//  RectificationDueStatus.swift
//  安全大师
//

import Foundation
import SwiftUI

enum RectificationDueStatus: Equatable {
    case remaining(days: Int)
    case dueToday
    case overdue(days: Int)
    case noDeadline
    case closed

    var text: String {
        switch self {
        case .remaining(let days):
            return "剩余 \(days) 天"
        case .dueToday:
            return "今天到期"
        case .overdue(let days):
            return "已逾期 \(days) 天"
        case .noDeadline:
            return "未设置期限"
        case .closed:
            return "已闭环"
        }
    }

    var tint: Color {
        switch self {
        case .remaining(let days):
            return days <= 3 ? .orange : .blue
        case .dueToday:
            return .orange
        case .overdue:
            return .red
        case .noDeadline:
            return .secondary
        case .closed:
            return .green
        }
    }

    var priority: Int {
        switch self {
        case .overdue: return 0
        case .dueToday: return 1
        case .remaining(let days) where days <= 3: return 2
        case .noDeadline: return 3
        case .remaining: return 4
        case .closed: return 9
        }
    }

    static func status(for finding: InspectionFinding, calendar: Calendar = .current, today: Date = Date()) -> RectificationDueStatus {
        if finding.isRectificationClosed { return .closed }
        guard let dueAt = finding.latestRectificationRound?.plannedDueAt else { return .noDeadline }
        let startOfToday = calendar.startOfDay(for: today)
        let dueDay = calendar.startOfDay(for: dueAt)
        let days = calendar.dateComponents([.day], from: startOfToday, to: dueDay).day ?? 0
        if days > 0 { return .remaining(days: days) }
        if days == 0 { return .dueToday }
        return .overdue(days: abs(days))
    }
}

