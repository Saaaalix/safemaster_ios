//
//  InspectionRecordsListView.swift
//  安全大师
//

import CoreData
import SwiftUI

/// 隐患排查列表分类（与 `rectificationClosureSummary` 对应）。
enum InspectionRecordListCategory: Hashable {
    case pendingRectification
    case completedRectification

    var navigationTitle: String {
        switch self {
        case .pendingRectification:
            return "待整改隐患"
        case .completedRectification:
            return "整改完成隐患"
        }
    }

    var hubIcon: String {
        switch self {
        case .pendingRectification:
            return "exclamationmark.triangle.fill"
        case .completedRectification:
            return "checkmark.seal.fill"
        }
    }

    func includes(_ finding: InspectionFinding) -> Bool {
        switch self {
        case .pendingRectification:
            return finding.shouldAppearInRectificationWorkflow
        case .completedRectification:
            return finding.isRectificationClosed
        }
    }
}

struct InspectionRecordsListView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InspectionFinding.createdAt, ascending: false)],
        animation: .default
    )
    private var findings: FetchedResults<InspectionFinding>

    /// 子实体（整改轮次）保存后递增，驱动根页条数与分类列表重新计算。
    @State private var rectificationRefreshToken = 0
    @State private var showNoticeLedger = false
    @State private var showImportedNoticeInbox = false
    @State private var showManualNoticeIntake = false
    @State private var showFlatList = false

    private var allFindings: [InspectionFinding] {
        let _ = rectificationRefreshToken
        return Array(findings)
    }

    private func count(for category: InspectionRecordListCategory) -> Int {
        allFindings.filter { category.includes($0) }.count
    }

    var body: some View {
        Group {
            if allFindings.isEmpty {
                VStack(spacing: 14) {
                    ContentUnavailableView(
                        "暂无整改记录",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("可先导入外部通知单文件，或在隐患识别页保存记录。")
                    )
                    Button {
                        showImportedNoticeInbox = true
                    } label: {
                        Label("导入外部通知单", systemImage: "tray.full")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 16)
                }
            } else {
                List {
                    Section("闭环主流程") {
                        Button {
                            showImportedNoticeInbox = true
                        } label: {
                            processRow(
                                step: "1",
                                title: "导入外部通知单",
                                subtitle: "PDF、Word、图片先进入导入箱，再识别建档",
                                systemImage: "tray.full",
                                tint: .blue
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            InspectionRecordsCategoryListView(category: .pendingRectification)
                        } label: {
                            processRow(
                                step: "2",
                                title: "跟进待整改",
                                subtitle: count(for: .pendingRectification) == 0
                                    ? "当前暂无待整改项"
                                    : "当前 \(count(for: .pendingRectification)) 条待整改",
                                systemImage: "exclamationmark.triangle.fill",
                                tint: .orange
                            )
                        }

                        NavigationLink {
                            InspectionRecordsCategoryListView(category: .completedRectification)
                        } label: {
                            processRow(
                                step: "3",
                                title: "查看验收完成",
                                subtitle: count(for: .completedRectification) == 0
                                    ? "暂无已闭环记录"
                                    : "当前 \(count(for: .completedRectification)) 条已闭环",
                                systemImage: "checkmark.seal.fill",
                                tint: .green
                            )
                        }

                        Button {
                            showNoticeLedger = true
                        } label: {
                            processRow(
                                step: "4",
                                title: "导出整改回复单",
                                subtitle: "按批次发起回复报告预览与导出",
                                systemImage: "arrow.up.doc",
                                tint: .purple
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Section("更多") {
                        Button {
                            showFlatList = true
                        } label: {
                            Label("查看全部排查记录", systemImage: "list.bullet.rectangle")
                        }
                        .buttonStyle(.plain)

                        Button {
                            showNoticeLedger = true
                        } label: {
                            Label("通知单台账", systemImage: "book.closed")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("隐患整改")
        .inlineNavigationTitleMode()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("更多") {
                    Button("导入外部通知单", systemImage: "tray.full") {
                        showImportedNoticeInbox = true
                    }
                    Button("手动补录通知单", systemImage: "square.and.pencil") {
                        showManualNoticeIntake = true
                    }
                    if !allFindings.isEmpty {
                        Button("通知单台账", systemImage: "book.closed") {
                            showNoticeLedger = true
                        }
                        Button("全部排查记录", systemImage: "list.bullet.rectangle") {
                            showFlatList = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showNoticeLedger) {
            NoticeReportLedgerView(findings: allFindings)
        }
        .sheet(isPresented: $showImportedNoticeInbox) {
            NavigationStack {
                ImportedNoticeInboxView()
                    .environment(\.managedObjectContext, viewContext)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") {
                                showImportedNoticeInbox = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showManualNoticeIntake) {
            ExternalNoticeIntakeView()
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $showFlatList) {
            NavigationStack {
                InspectionRecordFlatListView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") {
                                showFlatList = false
                            }
                        }
                    }
            }
        }
        .onRectificationStoreRefresh(in: viewContext, token: $rectificationRefreshToken)
    }

    private func processRow(
        step: String,
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Text(step)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(tint, in: Circle())
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func hubRow(category: InspectionRecordListCategory, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.hubIcon)
                .font(.title3)
                .foregroundStyle(category == .pendingRectification ? .orange : .green)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(category.navigationTitle)
                    .font(.body.weight(.semibold))
                Text(count == 0 ? "暂无条目" : "共 \(count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct NoticeReportLedgerView: View {
    let findings: [InspectionFinding]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBatchFindings: [InspectionFinding] = []
    @State private var showReplyPreview = false
    @State private var batchErrorMessage: String?

    private var rows: [NoticeReportBatchStore.LedgerRow] {
        NoticeReportBatchStore.ledgerRows(from: findings)
    }

    var body: some View {
        NavigationStack {
            List {
                if rows.isEmpty {
                    ContentUnavailableView("暂无通知单台账", systemImage: "doc.text.magnifyingglass")
                } else {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(row.projectName)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(row.statusText)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(row.pendingCount == 0 ? .green : .orange)
                            }
                            Text("生成时间：\(Self.dateTimeFormatter.string(from: row.createdAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("回复进度：\(row.respondedCount)/\(row.totalCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if row.pendingCount > 0 {
                                Text("未完成 \(row.pendingCount) 条")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                            if !row.itemLabels.isEmpty {
                                Text(row.itemLabels.prefix(2).joined(separator: "\n"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Button {
                                openBatchReplyPreview(row)
                            } label: {
                                Label("发起回复报告", systemImage: "arrow.up.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("通知单台账")
            .inlineNavigationTitleMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showReplyPreview) {
            GeneratedReportPreviewSheet(
                findings: selectedBatchFindings,
                kind: .rectification
            )
        }
        .alert("无法发起回复", isPresented: Binding(
            get: { batchErrorMessage != nil },
            set: { if !$0 { batchErrorMessage = nil } }
        )) {
            Button("好的", role: .cancel) {
                batchErrorMessage = nil
            }
        } message: {
            Text(batchErrorMessage ?? "")
        }
    }

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private func openBatchReplyPreview(_ row: NoticeReportBatchStore.LedgerRow) {
        let findingMap = Dictionary(
            uniqueKeysWithValues: findings.compactMap { finding -> (String, InspectionFinding)? in
                guard let key = finding.reportTrackingID else { return nil }
                return (key, finding)
            }
        )
        let batchFindings = row.trackingIDs.compactMap { findingMap[$0] }
        guard !batchFindings.isEmpty else {
            batchErrorMessage = "该批次对应记录未找到，可能已被删除。"
            return
        }
        if batchFindings.count < row.totalCount {
            batchErrorMessage = "该批次有部分记录缺失（找到 \(batchFindings.count)/\(row.totalCount) 条），请先核对记录。"
            return
        }
        selectedBatchFindings = batchFindings
        showReplyPreview = true
    }
}

// MARK: - 隐患识别页：按条扁平列表

struct InspectionRecordFlatListView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \InspectionFinding.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var findings: FetchedResults<InspectionFinding>

    @AppStorage(InspectionRecordSortMode.storageKey) private var sortModeRaw = InspectionRecordSortMode.time.rawValue
    @State private var searchText = ""
    @State private var rectificationRefreshToken = 0
    @State private var isManaging = false
    @State private var selectedObjectIDs = Set<NSManagedObjectID>()
#if os(iOS)
    @State private var showReportPreview = false
#endif
    @State private var showDeleteConfirmation = false
    @State private var deleteError: String?

    private var sortMode: InspectionRecordSortMode {
        InspectionRecordSortMode(rawValue: sortModeRaw) ?? .time
    }

    private var allFindings: [InspectionFinding] {
        let _ = rectificationRefreshToken
        return Array(findings)
    }

    private var displayedFindings: [InspectionFinding] {
        let filtered = InspectionRecordListSorting.filtered(allFindings, searchText: searchText)
        return InspectionRecordListSorting.sorted(filtered, mode: sortMode)
    }

    private var groupedSections: [InspectionRecordListSection] {
        InspectionRecordListSorting.grouped(displayedFindings, mode: sortMode)
    }

    private var selectedFindings: [InspectionFinding] {
        displayedFindings.filter { selectedObjectIDs.contains($0.objectID) }
    }

    private var canGenerateBatchReport: Bool {
        isManaging && !selectedObjectIDs.isEmpty
    }

    private var canDeleteSelection: Bool {
        isManaging && !selectedObjectIDs.isEmpty
    }

    var body: some View {
        flatListContent
        .navigationTitle("排查记录")
        .inlineNavigationTitleMode()
        .searchable(text: $searchText, prompt: "地点、隐患、项目、检查人、责任人")
        .toolbar {
            if !allFindings.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    inspectionRecordSortMenu(sortModeRaw: $sortModeRaw)
                }
                ToolbarItem(placement: .cancellationAction) {
                    if isManaging {
                        Button("取消") {
                            exitManagementMode()
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isManaging {
                        Button("完成") {
                            exitManagementMode()
                        }
                    } else {
                        Button("管理") {
                            isManaging = true
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !allFindings.isEmpty {
                flatListBottomActions
            }
        }
        .confirmationDialog(
            InspectionFindingDeletionCopy.batchTitle(count: selectedFindings.count),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("永久删除", role: .destructive) {
                deleteSelectedFindings()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(InspectionFindingDeletionCopy.batchMessage(count: selectedFindings.count))
        }
        .alert("删除失败", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("好的", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
#if os(iOS)
        .sheet(isPresented: $showReportPreview) {
            GeneratedReportPreviewSheet(
                findings: selectedFindings,
                kind: .inspection
            )
        }
#endif
        .onRectificationStoreRefresh(in: viewContext, token: $rectificationRefreshToken)
    }

    @ViewBuilder
    private var flatListContent: some View {
        if allFindings.isEmpty {
            ContentUnavailableView(
                "暂无排查记录",
                systemImage: "doc.text.magnifyingglass",
                description: Text("在排查结果页点击「记录」即可保存。")
            )
        } else if displayedFindings.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            flatListSections
        }
    }

    private var flatListSections: some View {
        List {
            ForEach(groupedSections) { section in
                Section {
                    ForEach(section.findings, id: \.objectID) { finding in
                        flatListRow(for: finding)
                    }
                } header: {
                    sectionHeader(section.title)
                }
            }
        }
    }

    @ViewBuilder
    private func flatListRow(for finding: InspectionFinding) -> some View {
        if isManaging {
            Button {
                toggleSelection(for: finding)
            } label: {
                flatListSelectableRow(finding)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                makeSingleRecordDetailView(for: finding)
            } label: {
                InspectionRecordSummaryRow(
                    finding: finding,
                    status: .workflow(for: finding)
                )
            }
        }
    }

    private var flatListBottomActions: some View {
        InspectionRecordListBottomActionBar(
            isManaging: isManaging,
            canDelete: canDeleteSelection,
            canGenerateReport: canGenerateBatchReport,
            reportFullTitle: "生成隐患排查通知书",
            reportManagingTitle: "生成通知书",
            onDelete: { showDeleteConfirmation = true },
            onGenerateReport: {
#if os(iOS)
                showReportPreview = true
#endif
            }
        )
    }

    private func deleteSelectedFindings() {
        let targets = selectedFindings
        guard !targets.isEmpty else { return }
        do {
            try viewContext.deleteInspectionFindings(targets)
            exitManagementMode()
        } catch {
            viewContext.rollback()
            deleteError = error.localizedDescription
        }
    }

    private func toggleSelection(for finding: InspectionFinding) {
        let id = finding.objectID
        if selectedObjectIDs.contains(id) {
            selectedObjectIDs.remove(id)
        } else {
            selectedObjectIDs.insert(id)
        }
    }

    private func exitManagementMode() {
        isManaging = false
        selectedObjectIDs.removeAll()
    }

    private func flatListSelectableRow(_ finding: InspectionFinding) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: selectedObjectIDs.contains(finding.objectID) ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selectedObjectIDs.contains(finding.objectID) ? Color.accentColor : Color.secondary)
            InspectionRecordSummaryRow(
                finding: finding,
                status: .workflow(for: finding)
            )
        }
    }
}

// MARK: - 分类下的按条列表

struct InspectionRecordsCategoryListView: View {
    let category: InspectionRecordListCategory

    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InspectionFinding.createdAt, ascending: false)],
        animation: .default
    )
    private var findings: FetchedResults<InspectionFinding>

    @AppStorage(InspectionRecordSortMode.storageKey) private var sortModeRaw = InspectionRecordSortMode.time.rawValue
    @State private var searchText = ""
    @State private var rectificationRefreshToken = 0
    @State private var batchReanalyzing = false
    @State private var batchError: String?
    @State private var batchProgress: String?
    @State private var batchReanalysisTask: Task<Void, Never>?
    @State private var isManaging = false
    @State private var selectedObjectIDs = Set<NSManagedObjectID>()
#if os(iOS)
    @State private var showRectificationPreview = false
#endif
    @State private var showDeleteConfirmation = false
    @State private var deleteError: String?

    private var sortMode: InspectionRecordSortMode {
        InspectionRecordSortMode(rawValue: sortModeRaw) ?? .time
    }

    private var allFindings: [InspectionFinding] {
        let _ = rectificationRefreshToken
        return Array(findings)
    }

    private var filteredFindings: [InspectionFinding] {
        allFindings.filter { category.includes($0) }
    }

    private var displayedFindings: [InspectionFinding] {
        let searched = InspectionRecordListSorting.filtered(filteredFindings, searchText: searchText)
        return InspectionRecordListSorting.sorted(searched, mode: sortMode)
    }

    private var groupedSections: [InspectionRecordListSection] {
        InspectionRecordListSorting.grouped(displayedFindings, mode: sortMode)
    }

    private var pendingFindings: [InspectionFinding] {
        displayedFindings.filter(\.needsPendingAnalysis)
    }

    private var pendingCount: Int {
        pendingFindings.count
    }

    private var selectedFindings: [InspectionFinding] {
        displayedFindings.filter { selectedObjectIDs.contains($0.objectID) }
    }

    private var canGenerateRectificationReply: Bool {
        category == .completedRectification && isManaging && !selectedObjectIDs.isEmpty
    }

    private var canDeleteSelection: Bool {
        category == .completedRectification && isManaging && !selectedObjectIDs.isEmpty
    }

    var body: some View {
        Group {
            if category == .completedRectification {
                completedRectificationBody
            } else if filteredFindings.isEmpty {
                categoryEmptyState
            } else if displayedFindings.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                pendingRectificationBody
            }
        }
        .navigationTitle(category.navigationTitle)
        .inlineNavigationTitleMode()
        .searchable(text: $searchText, prompt: "地点、隐患、项目、检查人、责任人")
        .toolbar {
            if !filteredFindings.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    inspectionRecordSortMenu(sortModeRaw: $sortModeRaw)
                }
            }
            if category == .completedRectification, !filteredFindings.isEmpty {
                ToolbarItem(placement: .cancellationAction) {
                    if isManaging {
                        Button("取消") { exitManagementMode() }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isManaging {
                        Button("完成") { exitManagementMode() }
                    } else {
                        Button("管理") { isManaging = true }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if category == .completedRectification, !filteredFindings.isEmpty {
                completedCategoryBottomActions
            }
        }
        .confirmationDialog(
            InspectionFindingDeletionCopy.batchTitle(count: selectedFindings.count),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("永久删除", role: .destructive) {
                deleteSelectedFindings()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(InspectionFindingDeletionCopy.batchMessage(count: selectedFindings.count))
        }
        .alert("删除失败", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("好的", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
#if os(iOS)
        .sheet(isPresented: $showRectificationPreview) {
            GeneratedReportPreviewSheet(
                findings: selectedFindings,
                kind: .rectification
            )
        }
#endif
        .onRectificationStoreRefresh(in: viewContext, token: $rectificationRefreshToken)
        .alert("批量分析", isPresented: Binding(
            get: { batchError != nil },
            set: { if !$0 { batchError = nil } }
        )) {
            Button("好的", role: .cancel) { batchError = nil }
        } message: {
            Text(batchError ?? "")
        }
    }

    private var completedCategoryBottomActions: some View {
        InspectionRecordListBottomActionBar(
            isManaging: isManaging,
            canDelete: canDeleteSelection,
            canGenerateReport: canGenerateRectificationReply,
            reportFullTitle: "生成隐患整改回复单",
            reportManagingTitle: "生成回复单",
            onDelete: { showDeleteConfirmation = true },
            onGenerateReport: {
#if os(iOS)
                showRectificationPreview = true
#endif
            }
        )
    }

    private func deleteSelectedFindings() {
        let targets = selectedFindings
        guard !targets.isEmpty else { return }
        do {
            try viewContext.deleteInspectionFindings(targets)
            exitManagementMode()
        } catch {
            viewContext.rollback()
            deleteError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var completedRectificationBody: some View {
        if filteredFindings.isEmpty {
            categoryEmptyState
        } else if displayedFindings.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            groupedFindingsList(
                status: .completed,
                managing: isManaging,
                onToggle: toggleSelection(for:)
            )
        }
    }

    @ViewBuilder
    private var pendingRectificationBody: some View {
        if filteredFindings.isEmpty {
            categoryEmptyState
        } else if displayedFindings.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            pendingRectificationList
        }
    }

    private var pendingRectificationList: some View {
        List {
            if pendingCount > 0 {
                pendingAnalysisSection
            }
            ForEach(groupedSections) { section in
                Section {
                    ForEach(section.findings, id: \.objectID) { finding in
                        pendingFindingRow(finding)
                    }
                } header: {
                    sectionHeader(section.title)
                }
            }
        }
    }

    private func pendingFindingRow(_ finding: InspectionFinding) -> some View {
        NavigationLink {
            makePendingRectificationRecordDetailView(for: finding)
        } label: {
            InspectionRecordSummaryRow(
                finding: finding,
                status: .workflow(for: finding)
            )
        }
    }

    @ViewBuilder
    private func groupedFindingsList(
        status: InspectionRecordSummaryStatus,
        managing: Bool,
        onToggle: @escaping (InspectionFinding) -> Void
    ) -> some View {
        List {
            ForEach(groupedSections) { section in
                Section {
                    ForEach(section.findings, id: \.objectID) { finding in
                        categoryFindingRow(
                            finding,
                            status: status,
                            managing: managing,
                            onToggle: onToggle
                        )
                    }
                } header: {
                    sectionHeader(section.title)
                }
            }
        }
    }

    @ViewBuilder
    private func categoryFindingRow(
        _ finding: InspectionFinding,
        status: InspectionRecordSummaryStatus,
        managing: Bool,
        onToggle: @escaping (InspectionFinding) -> Void
    ) -> some View {
        if managing {
            Button {
                onToggle(finding)
            } label: {
                categorySelectableRow(finding, status: status)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                switch category {
                case .pendingRectification:
                    makePendingRectificationRecordDetailView(for: finding)
                case .completedRectification:
                    makeCompletedRectificationRecordDetailView(for: finding)
                }
            } label: {
                InspectionRecordSummaryRow(finding: finding, status: .workflow(for: finding))
            }
        }
    }

    private func toggleSelection(for finding: InspectionFinding) {
        let id = finding.objectID
        if selectedObjectIDs.contains(id) {
            selectedObjectIDs.remove(id)
        } else {
            selectedObjectIDs.insert(id)
        }
    }

    private func exitManagementMode() {
        isManaging = false
        selectedObjectIDs.removeAll()
    }

    private func categorySelectableRow(
        _ finding: InspectionFinding,
        status: InspectionRecordSummaryStatus
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: selectedObjectIDs.contains(finding.objectID) ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selectedObjectIDs.contains(finding.objectID) ? Color.accentColor : Color.secondary)
            InspectionRecordSummaryRow(finding: finding, status: .workflow(for: finding))
        }
    }

    @ViewBuilder
    private var categoryEmptyState: some View {
        switch category {
        case .pendingRectification:
            ContentUnavailableView(
                "暂无待整改隐患",
                systemImage: "checkmark.circle",
                description: Text("已保存的隐患若均已验收闭环，会出现在「整改完成隐患」中。")
            )
        case .completedRectification:
            ContentUnavailableView(
                "暂无整改完成记录",
                systemImage: "tray",
                description: Text("验收通过并闭环的隐患会显示在这里，每条可单独查看。")
            )
        }
    }

    @ViewBuilder
    private var pendingAnalysisSection: some View {
        Section {
            HStack {
                Label("待补分析 \(pendingCount) 条", systemImage: "clock.badge.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
            }
            if batchReanalyzing, let batchProgress {
                HStack {
                    ProgressView()
                    Text(batchProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if batchReanalyzing {
                Button(role: .cancel) {
                    batchReanalysisTask?.cancel()
                } label: {
                    Label("取消批量分析", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
            } else {
                Button {
                    startBatchReanalysis()
                } label: {
                    Label("全部重新分析", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @MainActor
    private func startBatchReanalysis() {
        guard !batchReanalyzing else { return }
        batchReanalysisTask = Task { await reanalyzeAllPending() }
    }

    @MainActor
    private func reanalyzeAllPending() async {
        let targets = pendingFindings
        guard !targets.isEmpty else { return }
        guard let coordinator = viewContext.persistentStoreCoordinator else {
            batchError = "无法访问本地数据存储，请重启应用后重试。"
            return
        }
        batchError = nil
        batchReanalyzing = true
        defer {
            batchReanalyzing = false
            batchProgress = nil
            batchReanalysisTask = nil
        }
        let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        backgroundContext.persistentStoreCoordinator = coordinator
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        backgroundContext.undoManager = nil

        var failures: [String] = []
        var finishedCount = 0
        do {
            for (index, finding) in targets.enumerated() {
                try Task.checkCancellation()
                batchProgress = "正在分析 \(index + 1)/\(targets.count)…"
                let objectID = finding.objectID
                do {
                    let persisted: InspectionFinding? = try await backgroundContext.performThrowingInBatch { () throws -> InspectionFinding? in
                        guard let entity = try backgroundContext.existingObject(with: objectID) as? InspectionFinding,
                              !entity.isDeleted
                        else { return nil }
                        return entity
                    }
                    guard let persisted else { continue }
                    try await persisted.performReanalysis(context: backgroundContext)
                    finishedCount += 1
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    let loc = finding.location ?? "未填地点"
                    failures.append("\(loc)：\(AnalysisErrorMessages.localizedUserMessage(for: error))")
                }
            }
        } catch is CancellationError {
            let suffix = finishedCount > 0 ? "（已完成 \(finishedCount)/\(targets.count) 条）" : ""
            batchError = "已取消批量分析\(suffix)。"
            return
        } catch {
            batchError = AnalysisErrorMessages.localizedUserMessage(for: error)
            return
        }

        if !failures.isEmpty {
            let head = failures.prefix(3).joined(separator: "\n")
            let more = failures.count > 3 ? "\n…另有 \(failures.count - 3) 条失败" : ""
            batchError = head + more
        }
    }
}

private extension NSManagedObjectContext {
    func performThrowingInBatch<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            perform {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - 列表底栏（管理态：删除左、生成报告右）

private struct InspectionRecordListBottomActionBar: View {
    let isManaging: Bool
    let canDelete: Bool
    let canGenerateReport: Bool
    let reportFullTitle: String
    let reportManagingTitle: String
    let onDelete: () -> Void
    let onGenerateReport: () -> Void

    var body: some View {
        Group {
            if isManaging {
                HStack(spacing: 10) {
                    Button("删除所选", role: .destructive, action: onDelete)
                        .buttonStyle(.bordered)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .containerRelativeFrame(.horizontal, count: 20, span: 7, spacing: 10)
                        .disabled(!canDelete)

                    Button(reportManagingTitle, action: onGenerateReport)
                        .buttonStyle(.borderedProminent)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .disabled(!canGenerateReport)
                }
            } else {
                Button(reportFullTitle, action: onGenerateReport)
                    .buttonStyle(.borderedProminent)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .disabled(!canGenerateReport)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

// MARK: - 排序菜单

private func inspectionRecordSortMenu(sortModeRaw: Binding<String>) -> some View {
    Menu {
        Picker("排序", selection: sortModeRaw) {
            ForEach(InspectionRecordSortMode.allCases) { mode in
                Text(mode.label).tag(mode.rawValue)
            }
        }
    } label: {
        Label(
            InspectionRecordSortMode(rawValue: sortModeRaw.wrappedValue)?.label ?? "排序",
            systemImage: "arrow.up.arrow.down"
        )
    }
}

private func makeSingleRecordDetailView(for finding: InspectionFinding) -> RecordDetailView {
    RecordDetailView(findingObjectID: finding.objectID)
}

private func makePendingRectificationRecordDetailView(for finding: InspectionFinding) -> RecordDetailView {
    RecordDetailView(findingObjectID: finding.objectID, displayMode: .editable)
}

private func makeCompletedRectificationRecordDetailView(for finding: InspectionFinding) -> RecordDetailView {
    RecordDetailView(findingObjectID: finding.objectID, displayMode: .rectificationReadonly)
}

private func sectionHeader(_ title: String) -> some View {
    Text(title)
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
}

// MARK: - Core Data 保存后刷新整改分类

private extension View {
    /// 整改轮次写入同一 `viewContext` 后，根页/分类页的条数与分组依赖此 token 重算。
    func onRectificationStoreRefresh(
        in context: NSManagedObjectContext,
        token: Binding<Int>
    ) -> some View {
        onReceive(
            NotificationCenter.default.publisher(
                for: .NSManagedObjectContextDidSave,
                object: context
            )
        ) { note in
            guard shouldRefreshRectificationLists(from: note) else { return }
            context.processPendingChanges()
            token.wrappedValue &+= 1
        }
        .onAppear {
            context.processPendingChanges()
            token.wrappedValue &+= 1
        }
    }
}

private func shouldRefreshRectificationLists(from note: Notification) -> Bool {
    let keys = [
        NSInsertedObjectsKey,
        NSUpdatedObjectsKey,
        NSDeletedObjectsKey
    ]
    for key in keys {
        guard let objects = note.userInfo?[key] as? Set<NSManagedObject> else { continue }
        if objects.contains(where: { $0 is RectificationRound || $0 is InspectionFinding }) {
            return true
        }
    }
    return false
}

#Preview {
    NavigationStack {
        InspectionRecordsListView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
