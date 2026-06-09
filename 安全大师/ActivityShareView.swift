//
//  ActivityShareView.swift
//  安全大师
//

#if os(iOS)
import CoreData
import QuickLook
import SwiftUI
import UIKit

struct ActivityShareView: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 报告生成：摘要预览 + QuickLook + 分享

struct GeneratedReportPreviewSheet: View {
    let findings: [InspectionFinding]
    let kind: ShareableReportKind

    @Environment(\.dismiss) private var dismiss

    @State private var shareItems: [Any] = []
    @State private var previewURL: URL?
    @State private var isLoading = true
    @State private var showShareSheet = false
    @State private var showFullScreenPreview = false
    @State private var errorMessage: String?
    @State private var exportCheckResult: ReportExportGuardResult?
    @State private var showBlockingExportAlert = false
    @State private var showSuggestedExportAlert = false
    @State private var supplementFindingObjectID: NSManagedObjectID?
    @State private var showSupplementDetail = false
    @State private var archiveMessage: String?
    @State private var showArchiveAlert = false
    @State private var showAIReportReview = false

    private var sortedFindings: [InspectionFinding] {
        DaySummaryBuilder.sortedForReport(findings)
    }

    private var template: ReportTemplateSettings {
        ReportTemplateSettings.current
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在生成报告…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "无法生成报告",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else {
                    reportReadyBody
                }
            }
            .navigationTitle(kind.coverTitle)
            .inlineNavigationTitleMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        requestShare()
                    } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    .disabled(shareItems.isEmpty)
                }
            }
        }
        .task(id: taskToken) {
            await prepareExport()
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityShareView(items: shareItems)
        }
        .sheet(isPresented: $showSupplementDetail) {
            if let supplementFindingObjectID {
                NavigationStack {
                    RecordDetailView(findingObjectID: supplementFindingObjectID)
                }
            }
        }
        .sheet(isPresented: $showAIReportReview) {
            AIReportReviewView(
                findings: sortedFindings,
                kind: kind,
                exportCheckResult: exportCheckResult ?? ReportExportGuard.validate(findings: sortedFindings, kind: kind)
            )
        }
        .alert("报告存在必填项缺失，补充后才能导出。", isPresented: $showBlockingExportAlert) {
            Button("去补充", role: .cancel) {
                openFirstSupplementTarget()
            }
        } message: {
            Text(exportIssueMessage(level: .required))
        }
        .alert(suggestedExportTitle, isPresented: $showSuggestedExportAlert) {
            Button("去补充", role: .cancel) {
                openFirstSupplementTarget()
            }
            Button("继续导出") {
                ReportExportEventStore.recordGenerated(findings: sortedFindings)
                showShareSheet = true
            }
        } message: {
            Text(exportIssueMessage(level: .suggested))
        }
        .alert("报告存档", isPresented: $showArchiveAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(archiveMessage ?? "")
        }
        .fullScreenCover(isPresented: $showFullScreenPreview) {
            if let previewURL {
                NavigationStack {
                    QuickLookPreview(url: previewURL)
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle("文档预览")
                        .inlineNavigationTitleMode()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("完成") { showFullScreenPreview = false }
                            }
                        }
                }
            }
        }
    }

    private var taskToken: String {
        let ids = findings.map { $0.objectID.uriRepresentation().absoluteString }.joined(separator: ",")
        return "\(kind)-\(ids)-\(template.exportSignature)"
    }

    @ViewBuilder
    private var reportReadyBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summarySection
                    if previewURL == nil {
                        Text("当前为文本/图片组合导出，可点击下方「分享」发送。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            if let previewURL {
                Divider()
                QuickLookPreview(url: previewURL)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                Button {
                    showFullScreenPreview = true
                } label: {
                    Label("全屏预览", systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            reportActionBar
        }
    }

    @ViewBuilder
    private var reportActionBar: some View {
        VStack(spacing: 10) {
            Button {
                showAIReportReview = true
            } label: {
                Label("AI 审查报告", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(sortedFindings.isEmpty)

            Button {
                archiveCurrentReport()
            } label: {
                Label("存档报告", systemImage: "archivebox")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(previewURL == nil)

            Button {
                requestShare()
            } label: {
                Label("分享报告", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(shareItems.isEmpty)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var summarySection: some View {
        let count = sortedFindings.count
        let dateLine = DaySummaryBuilder.reportHeaderDateLine(for: sortedFindings)
        let fileLabel = previewURL.map { $0.lastPathComponent } ?? "文本与现场照片"
        return VStack(alignment: .leading, spacing: 14) {
            previewCard(title: "导出概览", systemImage: "doc.richtext") {
                previewRow("报告类型", kind.coverTitle, systemImage: "doc.text")
                previewRow("报告模板", template.displayTemplateName, systemImage: "slider.horizontal.3")
                previewRow("照片布局", template.photoLayout.rawValue, systemImage: "photo")
                previewRow("启用字段", template.enabledDetailFieldLabels.joined(separator: "、"), systemImage: "checklist")
                previewRow("导出格式", exportFormatLabel(fileLabel: fileLabel), systemImage: "square.and.arrow.up")
                previewRow("检查日期", dateLine, systemImage: "calendar")
                previewRow("项目名称", ReportProjectSettingsStore.coverProjectName(for: sortedFindings), systemImage: "building.2")
                previewRow("检查人", ReportProjectSettingsStore.coverInspectorName(for: sortedFindings), systemImage: "person")
                previewRow("记录数量", "\(count) 条隐患", systemImage: "list.bullet.rectangle")
                previewRow("文件", fileLabel, systemImage: "doc")
            }

            exportCheckSection

            ForEach(Array(sortedFindings.enumerated()), id: \.element.objectID) { index, finding in
                exportFindingPreviewCard(finding: finding, index: index + 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exportFindingPreviewCard(finding: InspectionFinding, index: Int) -> some View {
        previewCard(title: "隐患 \(index)", systemImage: "exclamationmark.triangle") {
            previewRow("项目名称", finding.recordProjectNameDisplay)
            previewRow("检查人", finding.recordInspectorNameDisplay)
            previewRow("发现时间", discoveredAtText(for: finding))
            previewRow("地点", finding.reportLocationPart)
            if template.includeRiskLevel {
                previewRow("风险等级", finding.reportRiskLevelDisplay)
            }
            if template.includeAccidentCategory {
                previewRow("事故类别", finding.reportAccidentCategoryDisplay)
            }
            previewRow("隐患描述", previewText(finding.reportAIHazardDescriptionDisplay()))
            previewRow("整改措施", previewText(finding.reportRectificationRequirement))
            if template.includeLegalBasis {
                previewRow("整改依据", previewText(finding.reportLegalBasisReferenceSummary()))
            }
            if template.includeDeadline {
                previewRow("整改期限", finding.reportDeadlineLine)
            }
            previewRow("整改情况", rectificationSummary(for: finding))
            previewRow("照片情况", photoSummary(for: finding))

            if kind == .rectification {
                previewRow("整改责任人", finding.reportResponsibleParty)
                previewRow("实际整改说明", previewText(finding.reportRectificationSituation))
            }
        }
    }

    private func previewCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
    }

    private func previewRow(_ title: String, _ value: String, systemImage: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .padding(.top, 2)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func exportFormatLabel(fileLabel: String) -> String {
        if fileLabel.hasSuffix(".docx") { return "Word 文档（.docx）" }
        if fileLabel.hasSuffix(".pdf") { return "PDF 文档（.pdf）" }
        if fileLabel.hasSuffix(".txt") { return "文本文件（.txt）" }
        return fileLabel
    }

    private func discoveredAtText(for finding: InspectionFinding) -> String {
        guard let date = finding.discoveredAt ?? finding.createdAt else { return "—" }
        return Self.dateTimeFormatter.string(from: date)
    }

    private func rectificationSummary(for finding: InspectionFinding) -> String {
        let rounds = finding.rectificationRoundsArray
        guard !rounds.isEmpty else { return "尚无整改轮次" }
        return "\(rounds.count) 轮，\(finding.rectificationClosureSummary.badgeText)"
    }

    private func photoSummary(for finding: InspectionFinding) -> String {
        let beforeCount = finding.sitePhotoDatasOrdered.count
        let afterCount = finding.reportAfterRectificationPhotoData == nil ? 0 : 1
        return "现场照片 \(beforeCount) 张，整改后照片 \(afterCount) 张"
    }

    private func previewText(_ raw: String, maxLength: Int = 90) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "—" }
        guard text.count > maxLength else { return text }
        let end = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<end]) + "…"
    }

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    @MainActor
    private func prepareExport() async {
        isLoading = true
        errorMessage = nil
        shareItems = []
        previewURL = nil
        exportCheckResult = nil

        let list = sortedFindings
        guard !list.isEmpty else {
            errorMessage = "请先选择至少一条记录。"
            isLoading = false
            return
        }

        if kind == .inspection {
            NoticeReportBatchStore.recordInspectionBatch(for: list)
        }

        await Task.yield()
        let items = ShareableInspectionReportExporter.activityItems(findings: list, kind: kind)
        guard !items.isEmpty else {
            errorMessage = "报告生成失败，请稍后重试。"
            isLoading = false
            return
        }

        shareItems = items
        previewURL = ShareableInspectionReportExporter.primaryPreviewURL(findings: list, kind: kind)
            ?? items.compactMap { $0 as? URL }.first
        exportCheckResult = ReportExportGuard.validate(findings: list, kind: kind)
        isLoading = false
    }

    @ViewBuilder
    private var exportCheckSection: some View {
        let result = exportCheckResult ?? ReportExportGuard.validate(findings: sortedFindings, kind: kind)
        previewCard(title: "导出前检查", systemImage: result.hasBlockingIssues ? "exclamationmark.triangle.fill" : "checkmark.seal") {
            if result.issues.isEmpty {
                Label("关键字段已满足导出要求", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                exportIssueGroup("必须补充：影响正式报告生成", issues: result.requiredIssues)
                exportIssueGroup("建议补充：不影响生成，但建议完善", issues: result.suggestedIssues)
            }
        }
    }

    @ViewBuilder
    private func exportIssueGroup(_ title: String, issues: [ReportExportIssue]) -> some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(title.hasPrefix("必须") ? .red : .orange)
                ForEach(issues.prefix(6)) { issue in
                    Button {
                        openSupplementTarget(for: issue)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(issue.title)
                                    .font(.caption)
                                if issue.findingObjectID != nil {
                                    Image(systemName: "arrow.right.circle")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let recordLabel = issue.recordLabel {
                                Text(recordLabel)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(issue.findingObjectID == nil)
                }
                if issues.count > 6 {
                    Text("另有 \(issues.count - 6) 项")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var suggestedExportTitle: String {
        let count = exportCheckResult?.suggestedCount ?? 0
        return "报告还有 \(count) 项建议补充"
    }

    private func requestShare() {
        let result = ReportExportGuard.validate(findings: sortedFindings, kind: kind)
        exportCheckResult = result
        if result.hasBlockingIssues {
            showBlockingExportAlert = true
        } else if !result.suggestedIssues.isEmpty {
            showSuggestedExportAlert = true
        } else {
            ReportExportEventStore.recordGenerated(findings: sortedFindings)
            showShareSheet = true
        }
    }

    private func archiveCurrentReport() {
        guard let previewURL else {
            archiveMessage = "当前没有可存档的报告文件。"
            showArchiveAlert = true
            return
        }
        do {
            let report = try ReportArchiveStore.archive(
                sourceURL: previewURL,
                kindTitle: kind.coverTitle,
                projectName: ReportProjectSettingsStore.coverProjectName(for: sortedFindings),
                recordCount: sortedFindings.count
            )
            ReportExportEventStore.recordGenerated(findings: sortedFindings)
            archiveMessage = "已存档：\(report.fileName)"
        } catch {
            archiveMessage = "存档失败，请稍后重试。"
        }
        showArchiveAlert = true
    }

    private func openFirstSupplementTarget() {
        let first = exportCheckResult?.requiredIssues.first(where: { $0.findingObjectID != nil })
            ?? exportCheckResult?.suggestedIssues.first(where: { $0.findingObjectID != nil })
        guard let first else {
            dismiss()
            return
        }
        openSupplementTarget(for: first)
    }

    private func openSupplementTarget(for issue: ReportExportIssue) {
        guard let objectID = issue.findingObjectID else { return }
        supplementFindingObjectID = objectID
        showSupplementDetail = true
    }

    private func exportIssueMessage(level: ReportExportIssueLevel) -> String {
        let issues: [ReportExportIssue]
        switch level {
        case .required:
            issues = exportCheckResult?.requiredIssues ?? []
        case .suggested:
            issues = exportCheckResult?.suggestedIssues ?? []
        }
        let shown = issues.prefix(8).map { issue in
            if let label = issue.recordLabel {
                return "\(issue.title)\n\(label)"
            }
            return issue.title
        }.joined(separator: "\n")
        let more = issues.count > 8 ? "\n另有 \(issues.count - 8) 项" : ""
        return shown + more
    }

    private func exportGuardError(for list: [InspectionFinding]) -> String? {
        let projectNames = Set(list.map(normalizedProjectName(for:)).filter { !$0.isEmpty })
        if projectNames.isEmpty {
            return missingMessage(title: "所选记录未填写项目名称", findings: list)
        }
        if projectNames.count > 1 {
            return "检测到当前勾选记录来自多个项目，请按项目分别导出。"
        }

        let missingInspector = list.filter { $0.recordInspectorNameSnapshot == nil }
        if !missingInspector.isEmpty {
            return missingMessage(title: "以下记录未填写检查人", findings: missingInspector)
        }

        let missingLocation = list.filter {
            ($0.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        }
        if !missingLocation.isEmpty {
            return missingMessage(title: "以下记录未填写部位/地点", findings: missingLocation)
        }

        let pendingAnalysis = list.filter(\.needsPendingAnalysis)
        if !pendingAnalysis.isEmpty {
            return missingMessage(
                title: "以下记录仍是待补分析，不能直接导出正式文件",
                findings: pendingAnalysis,
                guidance: "请先进入记录详情点击「按所选项智能优化」，或手动改写并确认隐患详情后再导出。"
            )
        }

        let missingFormalFields = list.filter { !$0.hasConfirmedDetailFields }
        if !missingFormalFields.isEmpty {
            return missingMessage(
                title: "以下记录未完成隐患详情确认",
                findings: missingFormalFields,
                guidance: "请先补齐项目名称、检查人、存在问题、整改要求并点击「确定隐患详情」后再导出。"
            )
        }

        if kind == .rectification {
            if let batchGuardError = NoticeReportBatchStore.rectificationBatchGuardError(for: list) {
                return batchGuardError
            }
            let missingAfterPhoto = list.filter { $0.reportAfterRectificationPhotoData == nil }
            if !missingAfterPhoto.isEmpty {
                return missingMessage(title: "以下记录缺少整改后照片", findings: missingAfterPhoto)
            }
            let missingOwner = list.filter {
                $0.reportResponsibleParty.trimmingCharacters(in: .whitespacesAndNewlines) == "—"
            }
            if !missingOwner.isEmpty {
                return missingMessage(title: "以下记录未填写整改责任人", findings: missingOwner)
            }
        }
        return nil
    }

    private func normalizedProjectName(for finding: InspectionFinding) -> String {
        finding.recordProjectNameSnapshot ?? ""
    }

    private func missingMessage(
        title: String,
        findings: [InspectionFinding],
        guidance: String = "请先进入对应记录详情补齐后再导出。"
    ) -> String {
        let shown = findings.prefix(3).map(recordLabel(for:)).joined(separator: "\n")
        let more = findings.count > 3 ? "\n…另有 \(findings.count - 3) 条" : ""
        return "\(title)：\n\(shown)\(more)\n\(guidance)"
    }

    private func recordLabel(for finding: InspectionFinding) -> String {
        let location = finding.reportLocationPart
        let issue = finding.recordListHazardSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(location)：\(issue.isEmpty ? "未填写隐患摘要" : issue)"
    }
}

// MARK: - Quick Look

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#endif
