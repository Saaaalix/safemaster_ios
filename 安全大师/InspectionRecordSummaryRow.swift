//
//  InspectionRecordSummaryRow.swift
//  安全大师
//

import SwiftUI

/// 排查记录列表：单条隐患的结构化摘要行。
struct InspectionRecordSummaryRow: View {
    let finding: InspectionFinding
    var status: InspectionRecordSummaryStatus?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                InspectionRecordSummaryMetaLine(
                    label: "时间",
                    value: InspectionRecordListFormatting.dayLine(from: finding)
                )
                InspectionRecordSummaryMetaLine(
                    label: "项目",
                    value: finding.recordProjectNameDisplay
                )
                InspectionRecordSummaryMetaLine(
                    label: "责任人",
                    value: finding.latestResponsiblePartyDisplay
                )
                InspectionRecordSummaryMetaLine(
                    label: "检查人",
                    value: finding.recordInspectorNameDisplay
                )
                InspectionRecordSummaryMetaLine(
                    label: "来源",
                    value: finding.sourceDisplayLabel
                )
                InspectionRecordSummaryMetaLine(
                    label: "期限",
                    value: RectificationDueStatus.status(for: finding).text,
                    tint: RectificationDueStatus.status(for: finding).tint
                )
                Text(finding.recordListHazardSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
            Spacer(minLength: 8)
            if let status {
                status.badge
            }
        }
        .padding(.vertical, 2)
    }
}

enum InspectionRecordSummaryStatus {
    case rectification(open: Bool)
    case pending
    case completed
    case workflow(text: String, tint: Color)

    static func workflow(for finding: InspectionFinding) -> InspectionRecordSummaryStatus {
        if finding.needsPendingAnalysis {
            return .workflow(text: "待补分析", tint: .orange)
        }
        switch finding.rectificationClosureSummary {
        case .notStarted:
            return .workflow(text: "待安排", tint: .orange)
        case .inProgress:
            let due = RectificationDueStatus.status(for: finding)
            return .workflow(text: due.text, tint: due.tint)
        case .awaitingVerification:
            return .workflow(text: finding.rectificationClosureSummary.compactBadgeText, tint: .blue)
        case .closed:
            return .workflow(text: "已闭环", tint: .green)
        case .failedPendingNewRound:
            return .workflow(text: "验收未通过", tint: .red)
        }
    }

    @ViewBuilder
    var badge: some View {
        switch self {
        case .rectification(let open):
            Text(open ? "已整改" : "未整改")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((open ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                .foregroundStyle(open ? .green : .orange)
        case .pending:
            Text("待整改")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.15), in: Capsule())
                .foregroundStyle(.orange)
        case .completed:
            Text("已整改")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.15), in: Capsule())
                .foregroundStyle(.green)
        case .workflow(let text, let tint):
            Text(text)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(0.15), in: Capsule())
                .foregroundStyle(tint)
        }
    }
}

private struct InspectionRecordSummaryMetaLine: View {
    let label: String
    let value: String
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(label)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .trailing)
            Text(value)
                .font(.caption)
                .foregroundStyle(tint)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
