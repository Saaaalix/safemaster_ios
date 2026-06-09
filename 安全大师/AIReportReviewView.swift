//
//  AIReportReviewView.swift
//  安全大师
//

#if os(iOS)
import SwiftUI
import UIKit

struct AIReportReviewView: View {
    let findings: [InspectionFinding]
    let kind: ShareableReportKind
    let exportCheckResult: ReportExportGuardResult

    @Environment(\.dismiss) private var dismiss
    @State private var didCopySuggestions = false

    private var review: AIReportReviewResult {
        AIReportReviewEngine.review(
            findings: findings,
            kind: kind,
            exportCheckResult: exportCheckResult
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section("总体判断") {
                    Label(review.verdict.rawValue, systemImage: review.verdict.systemImage)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(review.verdict.tint)
                    Text(review.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("问题列表") {
                    if review.issues.isEmpty {
                        Label("未发现明显问题", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        ForEach(review.issues) { issue in
                            VStack(alignment: .leading, spacing: 6) {
                                Label(issue.title, systemImage: issue.systemImage)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(issue.tint)
                                if !issue.detail.isEmpty {
                                    Text(issue.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                Section("修改建议") {
                    ForEach(review.suggestions, id: \.self) { suggestion in
                        Text(suggestion)
                            .font(.subheadline)
                    }

                    Button {
                        UIPasteboard.general.string = review.copyText
                        didCopySuggestions = true
                    } label: {
                        Label(didCopySuggestions ? "已复制建议文案" : "复制建议文案", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("AI 审查报告")
            .inlineNavigationTitleMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

private struct AIReportReviewResult {
    var verdict: AIReportReviewVerdict
    var summary: String
    var issues: [AIReportReviewIssue]
    var suggestions: [String]

    var copyText: String {
        let issueText = issues.isEmpty
            ? "问题列表：未发现明显问题"
            : "问题列表：\n" + issues.map { "- \($0.title)：\($0.detail)" }.joined(separator: "\n")
        let suggestionText = "修改建议：\n" + suggestions.map { "- \($0)" }.joined(separator: "\n")
        return "总体判断：\(verdict.rawValue)\n\(summary)\n\n\(issueText)\n\n\(suggestionText)"
    }
}

private enum AIReportReviewVerdict: String {
    case canSubmit = "可以提交"
    case shouldRevise = "建议修改"
    case obviousRisk = "存在明显风险"

    var systemImage: String {
        switch self {
        case .canSubmit:
            return "checkmark.seal.fill"
        case .shouldRevise:
            return "exclamationmark.bubble.fill"
        case .obviousRisk:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .canSubmit:
            return .green
        case .shouldRevise:
            return .orange
        case .obviousRisk:
            return .red
        }
    }
}

private struct AIReportReviewIssue: Identifiable {
    enum Severity {
        case risk
        case warning
        case suggestion
    }

    let id = UUID()
    var severity: Severity
    var title: String
    var detail: String

    var systemImage: String {
        switch severity {
        case .risk:
            return "xmark.octagon.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .suggestion:
            return "lightbulb.fill"
        }
    }

    var tint: Color {
        switch severity {
        case .risk:
            return .red
        case .warning:
            return .orange
        case .suggestion:
            return .blue
        }
    }
}

private enum AIReportReviewEngine {
    static func review(
        findings: [InspectionFinding],
        kind: ShareableReportKind,
        exportCheckResult: ReportExportGuardResult
    ) -> AIReportReviewResult {
        var issues = exportCheckResult.issues.map { issue in
            AIReportReviewIssue(
                severity: issue.level == .required ? .risk : .warning,
                title: issue.title,
                detail: issue.recordLabel ?? issue.level.explanation
            )
        }

        let rows = DaySummaryBuilder.sortedForReport(findings)
        appendQualityIssues(for: rows, kind: kind, issues: &issues)

        let verdict: AIReportReviewVerdict
        if issues.contains(where: { $0.severity == .risk }) {
            verdict = .obviousRisk
        } else if issues.contains(where: { $0.severity == .warning || $0.severity == .suggestion }) {
            verdict = .shouldRevise
        } else {
            verdict = .canSubmit
        }

        return AIReportReviewResult(
            verdict: verdict,
            summary: summary(for: verdict, count: rows.count),
            issues: issues,
            suggestions: suggestions(for: rows, kind: kind, issues: issues)
        )
    }

    private static func appendQualityIssues(
        for findings: [InspectionFinding],
        kind: ShareableReportKind,
        issues: inout [AIReportReviewIssue]
    ) {
        let pendingAnalysisCount = findings.filter(\.needsPendingAnalysis).count
        if pendingAnalysisCount > 0 {
            issues.append(AIReportReviewIssue(
                severity: .warning,
                title: "\(pendingAnalysisCount) 条记录仍是待补分析状态",
                detail: "建议补齐正式隐患描述、整改要求和依据后再提交。"
            ))
        }

        let noPhotoCount = findings.filter { $0.sitePhotoDatasOrdered.isEmpty }.count
        if noPhotoCount > 0 {
            issues.append(AIReportReviewIssue(
                severity: .suggestion,
                title: "\(noPhotoCount) 条记录缺少现场照片",
                detail: "照片不是所有报告的强制项，但会影响现场佐证力度。"
            ))
        }

        if kind == .rectification {
            let noAcceptedRoundCount = findings.filter {
                !$0.rectificationRoundsArray.contains { $0.statusEnum == .passed }
            }.count
            if noAcceptedRoundCount > 0 {
                issues.append(AIReportReviewIssue(
                    severity: .warning,
                    title: "\(noAcceptedRoundCount) 条整改记录缺少验收通过轮次",
                    detail: "整改回复报告建议以验收通过轮次作为闭环依据。"
                ))
            }
        }
    }

    private static func summary(for verdict: AIReportReviewVerdict, count: Int) -> String {
        switch verdict {
        case .canSubmit:
            return "本次共审查 \(count) 条隐患记录，关键字段和表达完整性较好。"
        case .shouldRevise:
            return "本次共审查 \(count) 条隐患记录，报告可以继续导出，但建议先处理下方问题。"
        case .obviousRisk:
            return "本次共审查 \(count) 条隐患记录，存在会影响正式提交的明显风险。"
        }
    }

    private static func suggestions(
        for findings: [InspectionFinding],
        kind: ShareableReportKind,
        issues: [AIReportReviewIssue]
    ) -> [String] {
        if issues.isEmpty {
            return [
                "导出前再次核对项目名称、检查人、日期和签字栏是否符合单位格式。",
                kind == .inspection
                    ? "提交通知单前确认接收单位、整改期限和责任人已线下确认。"
                    : "提交回复报告前确认整改后照片、验收意见和复查日期完整。"
            ]
        }

        var result: [String] = []
        if issues.contains(where: { $0.severity == .risk }) {
            result.append("先补齐标记为必须补充的字段，再进行正式导出。")
        }
        if findings.contains(where: \.needsPendingAnalysis) {
            result.append("对待补分析记录执行 AI 辅助分析或手动改写，避免报告正文出现占位语。")
        }
        if findings.contains(where: { $0.reportLegalBasisReferenceSummary() == "—" }) {
            result.append("为每条隐患补充至少一条规范依据，正文中保留规范名称和条文号即可。")
        }
        if kind == .rectification {
            result.append("整改回复报告建议逐条核对整改后照片、验收结论、复查人和复查日期。")
        } else {
            result.append("整改通知单建议重点核对隐患描述、整改要求、责任人和整改期限。")
        }
        return result
    }
}

#Preview {
    AIReportReviewView(
        findings: [],
        kind: .inspection,
        exportCheckResult: ReportExportGuardResult(issues: [])
    )
}
#endif
