//
//  RecordDetailView.swift
//  安全大师
//

import CoreData
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private extension Notification.Name {
    static let recordDetailShouldSaveDrafts = Notification.Name("recordDetailShouldSaveDrafts")
}

/// 记录详情内多行/多条的输入焦点（键盘工具栏「完成」）。
private enum RecordEditorFocus: Hashable {
    case projectName(NSManagedObjectID)
    case inspectorName(NSManagedObjectID)
    case location(NSManagedObjectID)
    case supplementary(NSManagedObjectID)
}

struct RecordDetailView: View {
    enum DisplayMode {
        case editable
        case rectificationReadonly
    }

    /// 报告抬头用归档日；单条模式下由 `reportArchiveDay` 从该条记录推导。
    private let day: Date
    private let displayMode: DisplayMode

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest private var findings: FetchedResults<InspectionFinding>
    @State private var showDetailPreview = false
    @State private var showReportTemplateEditor = false
    @State private var reanalyzingObjectID: NSManagedObjectID?
    @State private var reanalyzeError: String?
    @State private var showDeleteConfirmation = false
    @State private var deleteError: String?
    @FocusState private var editorFocus: RecordEditorFocus?

    /// 按自然日展示当天全部排查记录（排查记录等场景仍可用）。
    init(day: Date) {
        self.day = day
        self.displayMode = .editable
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        // 优先按发现时间归档；无发现时间的老数据按创建时间。
        _findings = FetchRequest(
            sortDescriptors: [
                NSSortDescriptor(keyPath: \InspectionFinding.discoveredAt, ascending: true),
                NSSortDescriptor(keyPath: \InspectionFinding.createdAt, ascending: true)
            ],
            predicate: NSPredicate(
                format: "(discoveredAt != nil AND discoveredAt >= %@ AND discoveredAt < %@) OR (discoveredAt == nil AND createdAt >= %@ AND createdAt < %@)",
                start as NSDate, end as NSDate, start as NSDate, end as NSDate
            )
        )
    }

    /// 单条隐患详情（待整改 / 整改完成列表点进仅展示本条）。
    init(finding: InspectionFinding) {
        self.init(findingObjectID: finding.objectID, displayMode: .editable)
    }

    init(findingObjectID: NSManagedObjectID, displayMode: DisplayMode = .editable) {
        self.day = Calendar.current.startOfDay(for: Date())
        self.displayMode = displayMode
        _findings = FetchRequest(
            sortDescriptors: [
                NSSortDescriptor(keyPath: \InspectionFinding.discoveredAt, ascending: true),
                NSSortDescriptor(keyPath: \InspectionFinding.createdAt, ascending: true)
            ],
            predicate: NSPredicate(format: "self == %@", findingObjectID)
        )
    }

    private var reportArchiveDay: Date {
        if let f = findings.first {
            let raw = f.effectiveArchiveDate ?? f.createdAt ?? Date()
            return Calendar.current.startOfDay(for: raw)
        }
        return day
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if findings.isEmpty {
                    ContentUnavailableView("当天无记录", systemImage: "tray")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else {
                    ForEach(Array(findings.enumerated()), id: \.element.objectID) { i, f in
                        InspectionRecordSectionView(
                            finding: f,
                            recordIndex: i + 1,
                            editorFocus: $editorFocus,
                            reanalyzingObjectID: $reanalyzingObjectID,
                            onReanalyzeError: { reanalyzeError = $0 },
                            readOnly: displayMode == .rectificationReadonly
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(navigationTitleText)
        .inlineNavigationTitleMode()
#if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        .onScrollPhaseChange { oldPhase, newPhase in
            if oldPhase == .idle, newPhase != .idle {
                editorFocus = nil
            }
        }
        .toolbar {
            if !findings.isEmpty {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("编辑报告模板") {
                        showReportTemplateEditor = true
                    }
                    Button("预览") {
                        NotificationCenter.default.post(name: .recordDetailShouldSaveDrafts, object: nil)
                        showDetailPreview = true
                    }
                }
            }
            if editorFocus != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    Button("完成") {
                        editorFocus = nil
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                }
            }
        }
#endif
#if os(macOS)
        .toolbar {
            if !findings.isEmpty {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("编辑报告模板") {
                        showReportTemplateEditor = true
                    }
                    Button("预览") {
                        NotificationCenter.default.post(name: .recordDetailShouldSaveDrafts, object: nil)
                        showDetailPreview = true
                    }
                }
            }
        }
#endif
        .confirmationDialog(
            InspectionFindingDeletionCopy.dayPageTitle(count: findings.count),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("永久删除", role: .destructive) {
                deleteDisplayedFindings()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(InspectionFindingDeletionCopy.dayPageMessage(count: findings.count))
        }
        .onChange(of: findings.count) { _, count in
            if count == 0 {
                dismiss()
            }
        }
        .alert("删除失败", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("好的", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .alert("提示", isPresented: Binding(
            get: { reanalyzeError != nil },
            set: { if !$0 { reanalyzeError = nil } }
        )) {
            Button("好的", role: .cancel) { reanalyzeError = nil }
        } message: {
            Text(reanalyzeError ?? "")
        }
#if os(iOS)
        .sheet(isPresented: $showDetailPreview) {
            if displayMode == .rectificationReadonly {
                GeneratedReportPreviewSheet(findings: Array(findings), kind: .rectification)
            } else {
                HazardDetailPreviewSheet(findings: Array(findings))
            }
        }
#else
        .alert("预览内容", isPresented: $showDetailPreview) {
            Button("取消", role: .cancel) {}
        } message: {
            Text(displayMode == .rectificationReadonly ? rectificationReportPlainText : reportPlainText)
        }
#endif
        .sheet(isPresented: $showReportTemplateEditor) {
            NavigationStack {
                ReportTemplateEditorView(
                    previewData: ReportTemplatePreviewData(
                        findings: Array(findings),
                        reportDate: day
                    )
                )
            }
        }
    }

    private var navigationTitleText: String {
        if displayMode == .rectificationReadonly {
            return "整改详情"
        }
        return findings.count == 1 ? "隐患详情" : "记录详情"
    }

    private var deleteMenuTitle: String {
        findings.count == 1 ? "删除本条记录" : "删除本页全部记录"
    }

    private func deleteDisplayedFindings() {
        let targets = Array(findings)
        guard !targets.isEmpty else { return }
        do {
            try viewContext.deleteInspectionFindings(targets)
        } catch {
            viewContext.rollback()
            deleteError = error.localizedDescription
        }
    }

    @MainActor
    private func reanalyze(finding: InspectionFinding) async {
        reanalyzeError = nil
        guard finding.hasMinimumInputForAnalysis() else {
            reanalyzeError = "该条无照片且无文字说明，无法分析。"
            return
        }
        let objectID = finding.objectID
        reanalyzingObjectID = objectID
        defer { reanalyzingObjectID = nil }
        do {
            guard let persisted = try? viewContext.existingObject(with: objectID) as? InspectionFinding else {
                reanalyzeError = "无法写回：该条记录可能已被删除。"
                return
            }
            try await persisted.performReanalysis(context: viewContext)
        } catch {
            viewContext.rollback()
            reanalyzeError = error.localizedDescription
        }
    }

    private var reportPlainText: String {
        DaySummaryBuilder.reportText(for: Array(findings), day: reportArchiveDay)
    }

    private var rectificationReportPlainText: String {
        DaySummaryBuilder.reportText(for: Array(findings), kind: .rectification)
    }

}

// MARK: - 单条记录（可编辑说明 / 发现时间）

private struct InspectionRecordSectionView: View {
    @ObservedObject var finding: InspectionFinding
    @Environment(\.managedObjectContext) private var viewContext

    let recordIndex: Int
    var editorFocus: FocusState<RecordEditorFocus?>.Binding
    @Binding var reanalyzingObjectID: NSManagedObjectID?
    let onReanalyzeError: (String) -> Void
    let readOnly: Bool

    @State private var locationDraft = ""
    @State private var projectNameDraft = ""
    @State private var inspectorNameDraft = ""
    @State private var supplementaryDraft = ""
    @State private var issueDraft = ""
    @State private var requirementDraft = ""
    @State private var legalBasisDraft = ""
    @State private var riskLevelDraft = InspectionRecordSectionView.defaultRiskLevel
    @State private var discoveredAtDraft = Date()
    @State private var editSaveHint: String?
    @State private var deepSeekConfigured = false
    @State private var optimizeIssueEnabled = true
    @State private var optimizeRequirementEnabled = true
    @State private var optimizeLegalBasisEnabled = true
    @State private var optimizeInteractionHint: String?
    @State private var showOptimizationTargetAlert = false
    @State private var issueWasOptimized = false
    @State private var requirementWasOptimized = false
    @State private var legalBasisWasOptimized = false
    @State private var issueBeforeOptimization: String?
    @State private var requirementBeforeOptimization: String?
    @State private var legalBasisBeforeOptimization: String?
    @State private var isDetailConfirmed = false
    @State private var issueFieldOpacity: Double = 1
    @State private var requirementFieldOpacity: Double = 1
    @State private var legalBasisFieldOpacity: Double = 1
    @State private var showReadonlyReference = false

#if os(iOS) || os(visionOS) || os(macOS)
    @StateObject private var voiceTranscriber = HazardVoiceTranscriber()
#endif

    private static let riskLevelOptions = HazardRiskLevel.canonicalOptions
    private static let defaultRiskLevel = "一般风险"
    private static let productivityAccent = Color(red: 0.95, green: 0.65, blue: 0.3)

    private static let discoveredAtDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy年MM月dd日HH时mm分"
        return f
    }()

    private var anyAnalyzing: Bool { reanalyzingObjectID != nil }
    private var thisAnalyzing: Bool { reanalyzingObjectID == finding.objectID }
    private var hasMinimumInputForOptimization: Bool {
        !finding.sitePhotoDatasOrdered.isEmpty
            || !supplementaryDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasFormalFieldGaps: Bool {
        issueDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || requirementDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || legalBasisDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        recordAndRectificationSections
            .onAppear {
                syncDraftsFromFinding()
                refreshCloudAnalysisConfiguredFlag()
                isDetailConfirmed = readOnly
                    ? isDetailReadyForConfirmation
                    : initialDetailConfirmedState
            }
            .onReceive(NotificationCenter.default.publisher(for: .safemasterAccessTokenDidChange)) { _ in
                refreshCloudAnalysisConfiguredFlag()
            }
            .onReceive(NotificationCenter.default.publisher(for: .appleUserSessionDidChange)) { _ in
                refreshCloudAnalysisConfiguredFlag()
            }
            .onChange(of: finding.objectID) { _, _ in
                syncDraftsFromFinding()
                isDetailConfirmed = readOnly
                    ? isDetailReadyForConfirmation
                    : initialDetailConfirmedState
            }
            .onReceive(NotificationCenter.default.publisher(for: .recordDetailShouldSaveDrafts)) { _ in
                saveEdits(silent: true)
            }
#if os(iOS) || os(visionOS) || os(macOS)
            .onDisappear {
                voiceTranscriber.stopSessionIfNeeded()
            }
#endif
            .alert("请先开启优化项", isPresented: $showOptimizationTargetAlert) {
                Button("好的", role: .cancel) {}
            } message: {
                Text("请先打开「存在问题 / 整改要求 / 整改依据」中的至少一个开关，再执行智能优化。")
            }
    }

    @ViewBuilder
    private var recordAndRectificationSections: some View {
        Group {
            if readOnly {
                detailCard(title: "排查依据（只读）", systemImage: "doc.text.magnifyingglass") {
                    readonlyReferenceDisclosure
                }

                detailCard(title: "整改执行与验收", systemImage: "checkmark.seal") {
                    rectificationEntryCard
                }
            } else {
                detailCard(title: "记录与优化", systemImage: "photo.on.rectangle") {
                    recordSitePhotoGallery
                    siteFactsEditor
                    riskLevelEditor
                    siteDescriptionEditor
                    Divider().opacity(0.35)
                    formalReportFieldsSection
                    analysisReferenceDisclosure
                    reportAnalysisActionArea
                }
                detailCard(title: "整改与验收", systemImage: "checkmark.seal") {
                    rectificationClosureTimeline
                    Divider().opacity(0.35)
                    rectificationEntryCard
                }
            }
        }
    }

    private var rectificationClosureTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("整改闭环时间线", systemImage: "timeline.selection")
                .font(.subheadline.weight(.semibold))
            ForEach(rectificationTimelineNodes) { node in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: node.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(node.isDone ? node.tint : Color(.tertiaryLabel))
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(node.title)
                                .font(.caption.weight(.semibold))
                            Spacer(minLength: 8)
                            Text(node.timeText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(node.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var rectificationTimelineNodes: [RectificationTimelineNode] {
        let latest = finding.latestRectificationRound
        let foundAt = finding.discoveredAt ?? finding.createdAt
        let generatedNoticeAt = ReportExportEventStore.generatedAt(for: finding)
        let noticeDone = generatedNoticeAt != nil || finding.isExternalSource || finding.hasConfirmedDetailFields
        let noticeTime = generatedNoticeAt ?? finding.externalNoticeDate ?? finding.createdAt
        let rectifiedDone = latest.map { round in
            normalizedOptional(round.actionTaken) != nil || round.evidencePhotoData != nil
        } ?? false
        let rectifiedTime = latest?.createdAt
        let passedDone = latest?.statusEnum == .passed
        let passedTime = latest?.verifiedAt
        return [
            RectificationTimelineNode(
                title: "发现隐患",
                isDone: true,
                time: foundAt,
                detail: finding.reportLocationPart
            ),
            RectificationTimelineNode(
                title: "生成通知",
                isDone: noticeDone,
                time: noticeDone ? noticeTime : nil,
                detail: generatedNoticeAt != nil ? "已导出或分享正式通知资料" : (noticeDone ? "已形成可导出的通知资料" : "导出通知单后会进入此节点")
            ),
            RectificationTimelineNode(
                title: "完成整改",
                isDone: rectifiedDone,
                time: rectifiedDone ? rectifiedTime : nil,
                detail: rectifiedDone ? "已填写整改情况或上传整改后照片" : "待填写实际整改说明或上传整改后照片"
            ),
            RectificationTimelineNode(
                title: "复查通过",
                isDone: passedDone,
                time: passedTime,
                detail: passedDone ? (latest?.verifierNote ?? "复查通过") : "待提交验收并复查"
            ),
            RectificationTimelineNode(
                title: "闭环归档",
                isDone: finding.isRectificationClosed,
                time: finding.isRectificationClosed ? passedTime : nil,
                detail: finding.isRectificationClosed ? "已闭环，可用于整改回复资料" : "复查通过后自动进入闭环归档"
            )
        ]
    }

    private var readonlyReferenceDisclosure: some View {
        DisclosureGroup(
            isExpanded: $showReadonlyReference
        ) {
            VStack(alignment: .leading, spacing: 12) {
                recordSitePhotoGallery
                siteFactsReadonly
                riskLevelReadonly
                siteDescriptionReadonly
                formalReportReadonlySection
                analysisReferenceDisclosure
            }
            .padding(.top, 8)
        } label: {
            Label("展开排查依据", systemImage: "chevron.right.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
        }
    }

    private var rectificationEntryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(finding.rectificationClosureSummary.badgeText, systemImage: "checkmark.seal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if let latest = finding.latestRectificationRound {
                latestRectificationOutcomeSummary(latest)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("当前轮次")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("第 \(latest.roundIndex) 轮")
                            .font(.caption.weight(.semibold))
                    }
                    HStack(spacing: 8) {
                        Text("状态")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(rectificationStatusText(latest.statusEnum))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(rectificationStatusTint(latest.statusEnum))
                    }
                    if latest.modeEnum == .scheduled {
                        HStack(spacing: 8) {
                            Text("计划完成日")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(latest.plannedDueAt.map(Self.dayFormatter.string(from:)) ?? "待确认")
                                .font(.caption)
                        }
                        let dueStatus = RectificationDueStatus.status(for: finding)
                        Text(dueStatus.text)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(dueStatus.tint)
                    }
                }
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text("尚未开始整改。可进入整改页发起首轮整改并记录整改过程。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                RectificationWorkflowView(finding: finding, disabled: anyAnalyzing)
            } label: {
                Label("进入整改闭环", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Self.productivityAccent)
            .disabled(anyAnalyzing || !canEnterRectificationWorkflow)

            if !canEnterRectificationWorkflow {
                Label(
                    readOnly
                        ? "当前记录未满足整改前置条件（项目名称、检查人、存在问题、整改要求）。"
                        : "请先在上方点击「确定隐患详情」，再进入整改闭环。",
                    systemImage: "lock.fill"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func latestRectificationOutcomeSummary(_ round: RectificationRound) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本次整改变化")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let action = normalizedOptional(round.actionTaken) {
                rectificationSummaryRow("实际整改说明", action)
            } else {
                rectificationSummaryRow("实际整改说明", "暂未填写")
            }

            if let note = normalizedOptional(round.verifierNote) {
                rectificationSummaryRow("验收意见", note)
            } else {
                rectificationSummaryRow("验收意见", round.statusEnum == .passed ? "验收通过" : "暂无")
            }

            if let verifiedAt = round.verifiedAt {
                rectificationSummaryRow("验收时间", Self.dateTimeFormatter.string(from: verifiedAt))
            }

            if let photo = rectificationEvidenceImage(round) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("整改后照片")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    photo
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            } else {
                rectificationSummaryRow("整改后照片", "未上传")
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func rectificationSummaryRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func hasRectificationPhoto(_ round: RectificationRound) -> Bool {
        guard let data = round.evidencePhotoData else { return false }
        return !data.isEmpty
    }

    private func rectificationEvidenceImage(_ round: RectificationRound) -> Image? {
        guard hasRectificationPhoto(round), let data = round.evidencePhotoData else { return nil }
        return Image.fromStoredData(data)
    }

    @ViewBuilder
    private var recordSitePhotoGallery: some View {
        let photos = finding.sitePhotoDatasOrdered
        if !photos.isEmpty {
            TabView {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
                    if let img = Image.fromStoredData(data) {
                        ZStack(alignment: .bottomLeading) {
                            img
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 220)
                                .clipped()

                            Text(photos.count > 1 ? (index == 0 ? "主图" : "副图 \(index)") : "现场照片")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.35), in: Capsule())
                                .padding(12)
                        }
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 6)
            .padding(.vertical, 8)
        }
    }

    private func riskBadge(_ level: String) -> some View {
        Text(level)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(riskTint(level), in: Capsule())
            .shadow(color: riskTint(level).opacity(0.2), radius: 8, x: 0, y: 4)
    }

    private var siteFactsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("现场事实")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
            sourceMetaLine
            hazardTypeTagsView

            HStack(alignment: .top, spacing: 10) {
                editableMetaField(
                    title: "项目名称",
                    placeholder: "例如：润城第二大道",
                    text: $projectNameDraft,
                    focus: .projectName(finding.objectID),
                    recentKind: .projectName
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)

                editableMetaField(
                    title: "检查人",
                    placeholder: "例如：张三",
                    text: $inspectorNameDraft,
                    focus: .inspectorName(finding.objectID),
                    recentKind: .inspectorName
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            HStack(alignment: .top, spacing: 10) {
                editableMetaField(
                    title: "部位/地点",
                    placeholder: "例如：1号宿舍内、办公区走廊、施工现场东侧",
                    text: $locationDraft,
                    focus: .location(finding.objectID),
                    recentKind: .location
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)

                discoveredAtTile
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var siteFactsReadonly: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("现场事实")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
            sourceMetaLine
            hazardTypeTagsView

            HStack(alignment: .top, spacing: 10) {
                labeledTile("项目名称", projectNameDraft)
                labeledTile("检查人", inspectorNameDraft)
            }

            HStack(alignment: .top, spacing: 10) {
                if !locationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    labeledTile("部位/地点", locationDraft)
                }
                discoveredAtTile
            }
        }
    }

    private var discoveredAtTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("发现时间")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))

            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundStyle(Self.productivityAccent)
                    .font(.subheadline.weight(.semibold))
                Text(Self.discoveredAtDisplayFormatter.string(from: discoveredAtDraft))
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var sourceMetaLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("来源")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
            Text(finding.sourceDisplayLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(finding.isExternalSource ? .blue : .secondary)
            if let external = finding.externalNoticeSummary {
                Text(external)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var hazardTypeTagsView: some View {
        let tags = parsedHazardTypeTags
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("隐患类型")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Self.productivityAccent.opacity(0.14), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private var riskLevelEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("风险等级")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
            Picker("风险等级", selection: $riskLevelDraft) {
                ForEach(Self.riskLevelOptions, id: \.self) { level in
                    Text(level).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: riskLevelDraft) { _, newLevel in
                persistRiskLevelDraft(newLevel)
            }
        }
    }

    private var riskLevelReadonly: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("风险等级")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
            riskBadge(riskLevelDraft)
        }
    }

    private var siteDescriptionEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("现场说明")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
            HStack(alignment: .top, spacing: 8) {
                TextField("补充现场看到的情况，保存后可重新智能优化", text: $supplementaryDraft, axis: .vertical)
                    .lineLimit(2...20)
                    .focused(editorFocus, equals: .supplementary(finding.objectID))
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
#if os(iOS) || os(visionOS) || os(macOS)
                recordVoiceMicButton(
                    fieldID: RecordEditorFocus.supplementary(finding.objectID),
                    text: $supplementaryDraft,
                    label: "语音输入文字说明"
                )
#endif
            }
#if os(iOS) || os(visionOS) || os(macOS)
            if voiceTranscriber.isActive(fieldID: RecordEditorFocus.supplementary(finding.objectID)) {
                RecordingWaveformView(tint: Self.productivityAccent)
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .scale))
            }
#endif
        }
    }

    private var siteDescriptionReadonly: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("现场说明")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
            Text(supplementaryDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : supplementaryDraft)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var optimizeActionButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                guard hasAnyOptimizationTarget else {
                    showOptimizationTargetAlert = true
                    return
                }
                saveEdits(silent: true)
                Task {
                    await optimizeSelectedFields()
                }
            } label: {
                if thisAnalyzing {
                    HStack {
                        Spacer()
                        ProgressView("正在生成正式报告语言...")
                            .tint(.white)
                        Spacer()
                    }
                } else {
                    Label(optimizationButtonTitle, systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Self.productivityAccent)
            .disabled(!hasMinimumInputForOptimization || !hasAnyOptimizationTarget || anyAnalyzing)

            if !hasAnyOptimizationTarget {
                Label("请选择要优化的字段", systemImage: "checkmark.square")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                Button {
                    saveEdits()
                } label: {
                    Label("保存当前编辑", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(anyAnalyzing)

                if !finding.isExternalSource {
                    Button {
                        saveEdits(silent: true)
                        isDetailConfirmed = true
                        DetailConfirmationStore.setConfirmed(true, for: finding)
                        editSaveHint = "已确认隐患详情，可进入整改闭环。"
                    } label: {
                        Label("确定隐患详情", systemImage: "checkmark.seal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(!isDetailReadyForConfirmation || anyAnalyzing)
                }
            }

            if let editSaveHint {
                Text(editSaveHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hasAnyOptimizationTarget: Bool {
        optimizeIssueEnabled || optimizeRequirementEnabled || optimizeLegalBasisEnabled
    }

    private var selectedOptimizationTargetCount: Int {
        [optimizeIssueEnabled, optimizeRequirementEnabled, optimizeLegalBasisEnabled].filter { $0 }.count
    }

    private var optimizationButtonTitle: String {
        let count = selectedOptimizationTargetCount
        guard count > 0 else { return "请选择优化项" }
        return "智能优化 \(count) 项"
    }

    private var isDetailReadyForConfirmation: Bool {
        !projectNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !inspectorNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !issueDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !requirementDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canEnterRectificationWorkflow: Bool {
        if readOnly {
            if finding.isExternalSource {
                return true
            }
            return finding.isRectificationClosed || isDetailReadyForConfirmation
        }
        if finding.isExternalSource {
            return true
        }
        return isDetailConfirmed && isDetailReadyForConfirmation
    }

    private var initialDetailConfirmedState: Bool {
        if finding.isExternalSource {
            DetailConfirmationStore.setConfirmed(true, for: finding)
            return true
        }
        return DetailConfirmationStore.isConfirmed(for: finding)
    }

    private var analysisReferenceDisclosure: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("正式报告字段中的“存在问题/整改要求/整改依据”为当前优化结果，请在导出前核对。", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reportAnalysisActionArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            if (finding.hazardDescription ?? "").contains(HazardOfflineMarkers.recordPrefix) {
                Label("这条记录是快速保存内容，联网后可重新分析补全建议和依据。", systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !deepSeekConfigured {
                Label("未完成 API 地址与 Apple 同步时，将使用本地演示结论。", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if finding.needsPendingAnalysis {
                Label("当前为待补分析记录，请先点击上方“智能优化”。", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var formalReportFieldsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            labeled(
                "事故类别",
                accidentCategoryDetail(major: finding.accidentCategoryMajor, minor: finding.accidentCategoryMinor)
            )
            if !associatedRiskTags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("关联风险（自动识别）")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(.secondaryLabel))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(associatedRiskTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Self.productivityAccent.opacity(0.14), in: Capsule())
                            }
                        }
                    }
                }
            }
            editableMultilineField(
                title: "存在问题",
                placeholder: "正式报告中的存在问题",
                text: $issueDraft,
                wasOptimized: issueWasOptimized,
                onRestore: issueBeforeOptimization == nil ? nil : restoreIssueOriginal
            )
            .opacity(issueFieldOpacity)
            .animation(.linear(duration: 0.08), value: issueFieldOpacity)
            editableMultilineField(
                title: "整改要求",
                placeholder: "正式报告中的整改要求",
                text: $requirementDraft,
                wasOptimized: requirementWasOptimized,
                onRestore: requirementBeforeOptimization == nil ? nil : restoreRequirementOriginal
            )
            .opacity(requirementFieldOpacity)
            .animation(.linear(duration: 0.08), value: requirementFieldOpacity)
            editableLargeMultilineField(
                title: "整改依据",
                placeholder: "正式报告中的整改依据",
                text: $legalBasisDraft,
                wasOptimized: legalBasisWasOptimized,
                onRestore: legalBasisBeforeOptimization == nil ? nil : restoreLegalBasisOriginal
            )
            .opacity(legalBasisFieldOpacity)
            .animation(.linear(duration: 0.08), value: legalBasisFieldOpacity)
            Label("当前为演示依据，正式使用请复核。", systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var formalReportFieldsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("正式报告字段（导出前确认）", systemImage: hasFormalFieldGaps ? "exclamationmark.triangle" : "doc.text")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(hasFormalFieldGaps ? .orange : Color(.secondaryLabel))
            if hasFormalFieldGaps {
                Label("导出前需补齐存在问题、整改要求和整改依据。", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Label("正式字段已填写，导出前仍建议人工核对。", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let optimizeInteractionHint {
                Label(optimizeInteractionHint, systemImage: "slider.horizontal.3")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            optimizationTargetPicker
            formalReportFieldsEditor
            optimizeActionButton
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var formalReportReadonlySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("正式报告字段", systemImage: "doc.text")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))

            if !issueDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                labeled("存在问题", issueDraft)
            }
            if !requirementDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                labeled("整改要求", requirementDraft)
            }
            if !legalBasisDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                labeled("整改依据", legalBasisDraft)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var optimizationTargetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择需要智能优化的字段")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
            HStack(spacing: 8) {
                optimizationTargetButton("存在问题", isOn: $optimizeIssueEnabled)
                optimizationTargetButton("整改要求", isOn: $optimizeRequirementEnabled)
                optimizationTargetButton("整改依据", isOn: $optimizeLegalBasisEnabled)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func optimizationTargetButton(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            optimizeInteractionHint = isOn.wrappedValue
                ? "已选择「\(title)」智能优化。"
                : "已取消「\(title)」智能优化。"
        } label: {
            Label(title, systemImage: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(isOn.wrappedValue ? Self.productivityAccent : .secondary)
    }

    private func editableMultilineField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        optimizeToggle: Binding<Bool>? = nil,
        wasOptimized: Bool = false,
        onRestore: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                Spacer(minLength: 6)
                if let optimizeToggle {
                    optimizationCornerToggle(title: title, isOn: optimizeToggle)
                }
            }
            formalFieldStatusRow(wasOptimized: wasOptimized, onRestore: onRestore)
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(3...8)
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                .autocorrectionDisabled(true)
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func editableLargeMultilineField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        optimizeToggle: Binding<Bool>? = nil,
        wasOptimized: Bool = false,
        onRestore: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                Spacer(minLength: 6)
                if let optimizeToggle {
                    optimizationCornerToggle(title: title, isOn: optimizeToggle)
                }
            }
            formalFieldStatusRow(wasOptimized: wasOptimized, onRestore: onRestore)

            ZStack(alignment: .topLeading) {
                if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .foregroundStyle(Color(.placeholderText))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                }

                TextEditor(text: text)
#if os(iOS)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled(true)
                    .frame(minHeight: 180)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func formalFieldStatusRow(wasOptimized: Bool, onRestore: (() -> Void)?) -> some View {
        HStack(spacing: 8) {
            Label(wasOptimized ? "已优化" : "待优化", systemImage: wasOptimized ? "checkmark.circle.fill" : "pencil")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(wasOptimized ? .green : .secondary)
            Text("可编辑")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let onRestore {
                Button("恢复原文", action: onRestore)
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(anyAnalyzing)
            }
        }
    }

    private func optimizationCornerToggle(title: String, isOn: Binding<Bool>) -> some View {
        let hintBinding = Binding<Bool>(
            get: { isOn.wrappedValue },
            set: { newValue in
                isOn.wrappedValue = newValue
                optimizeInteractionHint = newValue
                    ? "已开启「\(title)」智能优化。"
                    : "已关闭「\(title)」智能优化。"
            }
        )
        return Toggle("", isOn: hintBinding)
            .labelsHidden()
            .scaleEffect(0.75)
            .frame(height: 18)
    }

    private func editableMetaField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        focus: RecordEditorFocus,
        recentKind: RecentFieldKind? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
            TextField(placeholder, text: text)
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                .autocorrectionDisabled(true)
                .focused(editorFocus, equals: focus)
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if let recentKind {
                RecentValueChipsView(kind: recentKind, text: text, showTitle: false)
            }
        }
    }

    private func labeledTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func riskTint(_ level: String) -> Color {
        switch HazardRiskLevel.normalizedForStorage(level) {
        case "重大风险":
            return .red
        case "较大风险":
            return Self.productivityAccent
        case "一般风险":
            return .orange
        case "低风险":
            return Color(.systemGray)
        default:
            return Self.productivityAccent
        }
    }

    private func rectificationStatusText(_ status: RectificationStatus) -> String {
        switch status {
        case .inProgress: return "整改中"
        case .pendingVerification: return "待验收"
        case .passed: return "已通过"
        case .failed: return "未通过"
        }
    }

    private func rectificationStatusTint(_ status: RectificationStatus) -> Color {
        switch status {
        case .inProgress: return .blue
        case .pendingVerification: return Self.productivityAccent
        case .passed: return .green
        case .failed: return .red
        }
    }

    private func rectificationDeadlineHint(for round: RectificationRound) -> (text: String, tint: Color)? {
        guard round.modeEnum == .scheduled, let due = round.plannedDueAt else { return nil }
        let cal = Calendar.current
        let dueDay = cal.startOfDay(for: due)
        let today = cal.startOfDay(for: Date())
        guard let days = cal.dateComponents([.day], from: today, to: dueDay).day else { return nil }
        if days < 0 {
            return ("已逾期 \(abs(days)) 天", .red)
        }
        if days == 0 {
            return ("今天到期", .orange)
        }
        if days <= 2 {
            return ("剩余 \(days) 天（临近到期）", .orange)
        }
        return ("剩余 \(days) 天", Color(.secondaryLabel))
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年MM月dd日 HH:mm"
        return f
    }()

    private func detailCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            content()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
        .padding(.vertical, 8)
    }

#if os(iOS) || os(visionOS) || os(macOS)
    private func recordVoiceMicButton<FieldID: Hashable>(
        fieldID: FieldID,
        text: Binding<String>,
        label: String
    ) -> some View {
        VoiceInputIconButton(
            isRecordingForThisField: voiceTranscriber.isActive(fieldID: fieldID),
            isDisabled: anyAnalyzing,
            accessibilityLabel: label
        ) {
            Task {
                await voiceTranscriber.toggle(fieldID: fieldID, onto: text)
            }
        }
    }
#endif

    private func syncDraftsFromFinding() {
        locationDraft = finding.location ?? ""
        projectNameDraft = finding.recordProjectNameSnapshot ?? ""
        inspectorNameDraft = finding.recordInspectorNameSnapshot ?? ""
        supplementaryDraft = finding.supplementaryText ?? ""
        issueDraft = normalizedIssueDraft(
            hazardDescription: finding.hazardDescription,
            supplementaryText: finding.supplementaryText
        )
        requirementDraft = normalizedRequirementDraft(finding.rectificationMeasures)
        legalBasisDraft = normalizedLegalBasisDraft(finding.legalBasis)
        riskLevelDraft = Self.normalizedRiskLevel(finding.riskLevel)
        discoveredAtDraft = finding.discoveredAt ?? finding.createdAt ?? Date()
        editSaveHint = nil
    }

    private func normalizedIssueDraft(hazardDescription: String?, supplementaryText: String?) -> String {
        let issue = hazardDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !issue.isEmpty, !issue.contains(HazardOfflineMarkers.recordPrefix) {
            return issue
        }
        let supplementary = Self.removingHazardTypeLine(from: supplementaryText ?? "")
        return supplementary
    }

    private var parsedHazardTypeTags: [String] {
        Self.hazardTypeTags(from: supplementaryDraft)
    }

    private static func hazardTypeTags(from text: String) -> [String] {
        guard let line = text
            .split(whereSeparator: \.isNewline)
            .map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { $0.hasPrefix("隐患类型：") })
        else { return [] }
        return line
            .replacingOccurrences(of: "隐患类型：", with: "")
            .split(separator: "、")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func removingHazardTypeLine(from text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("隐患类型：") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedRequirementDraft(_ raw: String?) -> String {
        let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty || text.contains("待联网后") { return "" }
        return text
    }

    private func normalizedLegalBasisDraft(_ raw: String?) -> String {
        let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty || text.contains("离线记录：") { return "" }
        return text
    }

    private var associatedRiskTags: [String] {
        let text = issueDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let keywordMap: [(String, String)] = [
            ("触电", "触电"),
            ("电击", "触电"),
            ("火灾", "火灾"),
            ("起火", "火灾"),
            ("爆炸", "爆炸"),
            ("坠落", "高处坠落"),
            ("高处", "高处坠落"),
            ("中毒", "中毒窒息"),
            ("窒息", "中毒窒息"),
            ("机械伤害", "机械伤害"),
            ("物体打击", "物体打击"),
            ("灼伤", "灼烫伤"),
            ("烫伤", "灼烫伤")
        ]
        var tags: [String] = []
        for (keyword, label) in keywordMap where text.contains(keyword) {
            if !tags.contains(label) {
                tags.append(label)
            }
        }
        return tags
    }

    @MainActor
    private func optimizeSelectedFields() async {
        guard hasAnyOptimizationTarget else { return }
        let objectID = finding.objectID
        let previousIssue = finding.hazardDescription
        let previousRequirement = finding.rectificationMeasures
        let previousLegalBasis = finding.legalBasis
        if optimizeIssueEnabled {
            issueBeforeOptimization = issueDraft
        }
        if optimizeRequirementEnabled {
            requirementBeforeOptimization = requirementDraft
        }
        if optimizeLegalBasisEnabled {
            legalBasisBeforeOptimization = legalBasisDraft
        }
        reanalyzingObjectID = objectID
        defer { reanalyzingObjectID = nil }
        do {
            guard let persisted = try? viewContext.existingObject(with: objectID) as? InspectionFinding else {
                onReanalyzeError("无法写回：该条记录可能已被删除。")
                return
            }
            try await persisted.performReanalysis(context: viewContext, overwriteFormalFields: true)

            if !optimizeIssueEnabled {
                persisted.hazardDescription = previousIssue
            }
            if !optimizeRequirementEnabled {
                persisted.rectificationMeasures = previousRequirement
            }
            if !optimizeLegalBasisEnabled {
                persisted.legalBasis = previousLegalBasis
            }
            try viewContext.save()
            syncDraftsFromFinding()
            if optimizeIssueEnabled {
                issueWasOptimized = true
            }
            if optimizeRequirementEnabled {
                requirementWasOptimized = true
            }
            if optimizeLegalBasisEnabled {
                legalBasisWasOptimized = true
            }
            optimizeInteractionHint = "已生成正式报告语言，可继续编辑或恢复原文。"
            playOptimizedFieldsReveal()
        } catch {
            viewContext.rollback()
            onReanalyzeError(error.localizedDescription)
        }
    }

    private func restoreIssueOriginal() {
        guard let original = issueBeforeOptimization else { return }
        issueDraft = original
        issueWasOptimized = false
        saveEdits(silent: true)
        optimizeInteractionHint = "已恢复「存在问题」原文。"
    }

    private func restoreRequirementOriginal() {
        guard let original = requirementBeforeOptimization else { return }
        requirementDraft = original
        requirementWasOptimized = false
        saveEdits(silent: true)
        optimizeInteractionHint = "已恢复「整改要求」原文。"
    }

    private func restoreLegalBasisOriginal() {
        guard let original = legalBasisBeforeOptimization else { return }
        legalBasisDraft = original
        legalBasisWasOptimized = false
        saveEdits(silent: true)
        optimizeInteractionHint = "已恢复「整改依据」原文。"
    }

    private func playOptimizedFieldsReveal() {
        if optimizeIssueEnabled {
            issueFieldOpacity = 0.82
        }
        if optimizeRequirementEnabled {
            requirementFieldOpacity = 0.82
        }
        if optimizeLegalBasisEnabled {
            legalBasisFieldOpacity = 0.82
        }
        withAnimation(.linear(duration: 0.08)) {
            issueFieldOpacity = 1
            requirementFieldOpacity = 1
            legalBasisFieldOpacity = 1
        }
    }

    private static func normalizedRiskLevel(_ raw: String?) -> String {
        HazardRiskLevel.normalizedForStorage(raw) ?? defaultRiskLevel
    }

    private func persistRiskLevelDraft(_ level: String) {
        guard HazardRiskLevel.normalizedForStorage(level) != nil else { return }
        finding.riskLevel = level
        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
        }
    }

    private func refreshCloudAnalysisConfiguredFlag() {
        let base = SafeMasterAPIConfiguration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = KeychainStore.safemasterAccessToken()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        deepSeekConfigured = !base.isEmpty && !token.isEmpty
    }

    private func saveEdits(silent: Bool = false) {
        let project = projectNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        finding.reportProjectName = project.isEmpty ? nil : project
        let inspector = inspectorNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        finding.reportInspectorName = inspector.isEmpty ? nil : inspector
        let loc = locationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        finding.location = loc.isEmpty ? nil : loc
        let sup = supplementaryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        finding.supplementaryText = sup.isEmpty ? nil : sup
        let issue = issueDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        finding.hazardDescription = issue.isEmpty ? nil : issue
        let requirement = requirementDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        finding.rectificationMeasures = requirement.isEmpty ? nil : requirement
        let legalBasis = legalBasisDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        finding.legalBasis = legalBasis.isEmpty ? nil : legalBasis
        finding.riskLevel = riskLevelDraft
        do {
            try viewContext.save()
            RecentFieldValuesStore.record(project, for: .projectName)
            RecentFieldValuesStore.record(inspector, for: .inspectorName)
            RecentFieldValuesStore.record(loc, for: .location)
            if !finding.isExternalSource && !isDetailReadyForConfirmation {
                isDetailConfirmed = false
                DetailConfirmationStore.setConfirmed(false, for: finding)
            }
            editSaveHint = silent ? nil : "已保存。可点击「智能优化」用当前文字说明更新建议。"
        } catch {
            viewContext.rollback()
            onReanalyzeError("保存编辑失败：\(error.localizedDescription)")
        }
    }

    private func labeled(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func accidentCategoryDetail(major: String?, minor: String?) -> String {
        let maj = major?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let mino = minor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if maj.isEmpty, mino.isEmpty { return "—" }
        if mino.isEmpty { return "大类：\(maj)" }
        if maj.isEmpty { return "细类：\(mino)" }
        return "大类：\(maj)\n细类：\(mino)"
    }
}

private struct RectificationTimelineNode: Identifiable {
    let id = UUID()
    var title: String
    var isDone: Bool
    var time: Date?
    var detail: String

    var tint: Color {
        isDone ? .green : .secondary
    }

    var timeText: String {
        guard let time else { return "待完成" }
        return Self.formatter.string(from: time)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}

private struct HazardDetailPreviewSheet: View {
    let findings: [InspectionFinding]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if findings.isEmpty {
                        ContentUnavailableView("暂无可预览内容", systemImage: "doc.text.magnifyingglass")
                    } else {
                        ForEach(Array(findings.enumerated()), id: \.element.objectID) { index, finding in
                            previewCard(for: finding, index: index + 1)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("隐患详情预览")
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func previewCard(for finding: InspectionFinding, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("隐患 \(index)")
                .font(.headline)
            if let imageData = finding.sitePhotoDatasOrdered.first,
               let image = Image.fromStoredData(imageData) {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            previewRow("项目名称", finding.recordProjectNameSnapshot ?? "—")
            previewRow("检查人", finding.recordInspectorNameSnapshot ?? "—")
            previewRow("部位/地点", finding.location ?? "—")
            previewRow("发现时间", Self.timeFormatter.string(from: finding.discoveredAt ?? finding.createdAt ?? Date()))
            previewRow("存在问题", finding.hazardDescription ?? "—")
            previewRow("整改要求", finding.rectificationMeasures ?? "—")
            previewRow("整改依据", finding.legalBasis ?? "—")
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func previewRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : value)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年MM月dd日 HH:mm"
        return f
    }()
}

private struct RectificationWorkflowView: View {
    @ObservedObject var finding: InspectionFinding
    var disabled: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                remediationTaskBrief
                RectificationTimelineSection(finding: finding, disabled: disabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("整改闭环")
#if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private var remediationTaskBrief: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("整改任务（只读）", systemImage: "doc.text")
                .font(.subheadline.weight(.semibold))
            infoLine("部位/地点", normalized(finding.location))
            infoLine("存在问题", normalized(finding.hazardDescription))
            infoLine("整改要求", normalized(finding.rectificationMeasures))
            if let legal = optionalNormalized(finding.legalBasis) {
                infoLine("整改依据", legal)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func normalized(_ value: String?) -> String {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "—" : text
    }

    private func optionalNormalized(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private func infoLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        RecordDetailView(day: Calendar.current.startOfDay(for: Date()))
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
