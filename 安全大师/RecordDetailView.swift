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

/// 记录详情内多行/多条的输入焦点，用于隐藏底部「生成图文报告」避免误触。
private enum RecordEditorFocus: Hashable {
    case location(NSManagedObjectID)
    case supplementary(NSManagedObjectID)
}

struct RecordDetailView: View {
    let day: Date

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest private var findings: FetchedResults<InspectionFinding>
    @State private var showShare = false
    @State private var reanalyzingObjectID: NSManagedObjectID?
    @State private var reanalyzeError: String?
    @State private var deleteTarget: InspectionFinding?
    @FocusState private var editorFocus: RecordEditorFocus?

    init(day: Date) {
        self.day = day
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        // 与「排查记录」按日汇总一致：优先按发现时间归档；无发现时间的老数据按创建时间。
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

    var body: some View {
        List {
            if findings.isEmpty {
                ContentUnavailableView("当天无记录", systemImage: "tray")
            } else {
                ForEach(Array(findings.enumerated()), id: \.element.objectID) { i, f in
                    InspectionRecordSectionView(
                        finding: f,
                        recordIndex: i + 1,
                        editorFocus: $editorFocus,
                        reanalyzingObjectID: $reanalyzingObjectID,
                        onReanalyzeError: { reanalyzeError = $0 },
                        onDeleteTap: { deleteTarget = f },
                        reanalyze: { await reanalyze(finding: f) }
                    )
                }
            }
        }
        .navigationTitle("记录详情")
        .inlineNavigationTitleMode()
#if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        .onScrollPhaseChange { oldPhase, newPhase in
            if oldPhase == .idle, newPhase != .idle {
                editorFocus = nil
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
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
#endif
        .onChange(of: findings.count) { _, count in
            if count == 0 {
                dismiss()
            }
        }
        .alert("提示", isPresented: Binding(
            get: { reanalyzeError != nil },
            set: { if !$0 { reanalyzeError = nil } }
        )) {
            Button("好的", role: .cancel) { reanalyzeError = nil }
        } message: {
            Text(reanalyzeError ?? "")
        }
        .alert("删除这条记录？", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("取消", role: .cancel) { deleteTarget = nil }
            Button("删除", role: .destructive) {
                if let f = deleteTarget {
                    deleteFinding(f)
                }
                deleteTarget = nil
            }
        } message: {
            Text("删除后无法恢复。")
        }
        .safeAreaInset(edge: .bottom) {
            if editorFocus == nil {
                Button("生成图文报告") {
                    showShare = true
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.ultraThinMaterial)
            }
        }
#if os(iOS)
        .sheet(isPresented: $showShare) {
            ActivityShareView(items: buildIOSActivityItems())
        }
#else
        .alert("生成报告", isPresented: $showShare) {
            Button("复制全文") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(reportPlainText, forType: .string)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("macOS 上可先将报告复制到剪贴板；iOS 上支持系统分享面板（含图片）。")
        }
#endif
    }

    private func deleteFinding(_ f: InspectionFinding) {
        viewContext.delete(f)
        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
            reanalyzeError = "删除失败：\(error.localizedDescription)"
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
        let photos = finding.sitePhotoDatasOrdered
        let photoData = photos.first
        let secondaryPhotoData = photos.count > 1 ? photos[1] : nil
        let supplementaryText = finding.supplementaryText ?? ""
        let location = finding.location ?? ""

        reanalyzingObjectID = objectID
        defer { reanalyzingObjectID = nil }
        do {
            let service = HazardAnalysisServiceFactory.makeDefault()
            let result = try await service.analyze(
                photoData: photoData,
                secondaryPhotoData: secondaryPhotoData,
                supplementaryText: supplementaryText,
                location: location
            )
            guard let persisted = try? viewContext.existingObject(with: objectID) as? InspectionFinding,
                  !persisted.isDeleted
            else {
                reanalyzeError = "无法写回：该条记录可能已被删除。"
                return
            }
            persisted.applyReanalysis(result)
            do {
                try viewContext.save()
            } catch {
                viewContext.rollback()
                reanalyzeError = "保存失败：\(error.localizedDescription)"
            }
        } catch {
            reanalyzeError = error.localizedDescription
        }
    }

    private var reportPlainText: String {
        DaySummaryBuilder.reportText(for: Array(findings), day: day)
    }

#if os(iOS)
    private func buildIOSActivityItems() -> [Any] {
        let list = Array(findings)
        if let url = try? ShareableReportWordDocumentBuilder.buildTemporaryFileURL(findings: list, day: day) {
            return [url]
        }
        if let url = try? ShareableReportPDFBuilder.buildTemporaryFileURL(findings: list, day: day) {
            return [url]
        }
        var items: [Any] = []
        let body = reportPlainText
        let name = "安全大师_隐患排查报告_\(Int(Date().timeIntervalSince1970)).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if (try? body.write(to: url, atomically: true, encoding: .utf8)) != nil {
            items.append(url)
        } else {
            items.append(body)
        }
        for f in findings {
            for d in f.sitePhotoDatasOrdered {
                guard !d.isEmpty, let ui = UIImage(data: d) else { continue }
                let s = ui.size
                guard s.width > 0, s.height > 0, s.width.isFinite, s.height.isFinite else { continue }
                items.append(ui)
            }
        }
        return items
    }
#endif
}

// MARK: - 单条记录（可编辑说明 / 发现时间 + 删除）

private struct InspectionRecordSectionView: View {
    @ObservedObject var finding: InspectionFinding
    @Environment(\.managedObjectContext) private var viewContext

    let recordIndex: Int
    var editorFocus: FocusState<RecordEditorFocus?>.Binding
    @Binding var reanalyzingObjectID: NSManagedObjectID?
    let onReanalyzeError: (String) -> Void
    let onDeleteTap: () -> Void
    let reanalyze: () async -> Void

    @State private var locationDraft = ""
    @State private var supplementaryDraft = ""
    @State private var discoveredAtDraft = Date()
    @State private var showDiscoveredAtPicker = false
    @State private var editSaveHint: String?
    @State private var deepSeekConfigured = false

    private static let discoveredAtDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy年MM月dd日HH时mm分"
        return f
    }()

    private var anyAnalyzing: Bool { reanalyzingObjectID != nil }
    private var thisAnalyzing: Bool { reanalyzingObjectID == finding.objectID }

    var body: some View {
        recordAndRectificationSections
            .onAppear {
                syncDraftsFromFinding()
                refreshCloudAnalysisConfiguredFlag()
            }
            .onReceive(NotificationCenter.default.publisher(for: .safemasterAccessTokenDidChange)) { _ in
                refreshCloudAnalysisConfiguredFlag()
            }
            .onReceive(NotificationCenter.default.publisher(for: .appleUserSessionDidChange)) { _ in
                refreshCloudAnalysisConfiguredFlag()
            }
            .onChange(of: finding.objectID) { _, _ in
                syncDraftsFromFinding()
            }
            .sheet(isPresented: $showDiscoveredAtPicker) {
                NavigationStack {
                    DatePicker(
                        "",
                        selection: $discoveredAtDraft,
                        displayedComponents: [.date, .hourAndMinute]
                    )
#if os(iOS) || os(visionOS)
                    .datePickerStyle(.wheel)
#endif
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                    .padding()
                    .navigationTitle("发现时间")
#if os(iOS) || os(visionOS)
                    .navigationBarTitleDisplayMode(.inline)
#endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showDiscoveredAtPicker = false }
                        }
                    }
                }
#if os(iOS) || os(visionOS)
                .presentationDetents([.medium, .large])
#endif
            }
    }

    @ViewBuilder
    private var recordAndRectificationSections: some View {
        Section("记录 \(recordIndex)") {
            ForEach(Array(finding.sitePhotoDatasOrdered.enumerated()), id: \.offset) { _, data in
                if let img = Image.fromStoredData(data) {
                    img
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .listRowInsets(EdgeInsets())
                }
            }

            TextField("地点", text: $locationDraft)
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                .focused(editorFocus, equals: .location(finding.objectID))

            Button {
                showDiscoveredAtPicker = true
            } label: {
                LabeledContent("发现时间") {
                    Text(Self.discoveredAtDisplayFormatter.string(from: discoveredAtDraft))
                        .multilineTextAlignment(.trailing)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text("文字说明")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("可补充或修改后保存，再点「重新分析」更新 AI 结论", text: $supplementaryDraft, axis: .vertical)
                    .lineLimit(3...8)
                    .focused(editorFocus, equals: .supplementary(finding.objectID))
            }

            Button("保存本条编辑") {
                saveEdits()
            }
            .disabled(anyAnalyzing)

            if let editSaveHint {
                Text(editSaveHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            labeled("隐患描述", finding.hazardDescription)
            labeled("整改措施", finding.rectificationMeasures)
            labeled("风险等级", finding.riskLevel)
            labeled(
                "事故类别",
                accidentCategoryDetail(major: finding.accidentCategoryMajor, minor: finding.accidentCategoryMinor)
            )
            labeled("整改依据", finding.legalBasis)

            if (finding.hazardDescription ?? "").contains("【离线/手工记录】") {
                Text("本条曾为离线保存，可在有网络时用下方按钮补全 AI 分析与法规依据。重新分析会覆盖本条的隐患描述、措施、风险等级、事故类别与整改依据，不会新增一条记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !deepSeekConfigured {
                Text("未完成 API 地址与 Apple 同步时，重新分析将使用与「隐患识别」相同的本地演示结论，不会请求你的服务端。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await reanalyze() }
            } label: {
                if thisAnalyzing {
                    HStack {
                        Spacer()
                        ProgressView("分析中…")
                        Spacer()
                    }
                } else {
                    Label("重新分析（需联网）", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(!finding.hasMinimumInputForAnalysis() || anyAnalyzing)

            Button("删除本条记录", role: .destructive) {
                onDeleteTap()
            }
            .disabled(anyAnalyzing)
        }

        Section {
            RectificationTimelineSection(finding: finding, disabled: anyAnalyzing)
        } header: {
            Text("整改与验收")
        }
    }

    private func syncDraftsFromFinding() {
        locationDraft = finding.location ?? ""
        supplementaryDraft = finding.supplementaryText ?? ""
        discoveredAtDraft = finding.discoveredAt ?? finding.createdAt ?? Date()
        editSaveHint = nil
    }

    private func refreshCloudAnalysisConfiguredFlag() {
        let base = SafeMasterAPIConfiguration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = KeychainStore.safemasterAccessToken()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        deepSeekConfigured = !base.isEmpty && !token.isEmpty
    }

    private func saveEdits() {
        let loc = locationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        finding.location = loc.isEmpty ? nil : loc
        let sup = supplementaryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        finding.supplementaryText = sup.isEmpty ? nil : sup
        finding.discoveredAt = discoveredAtDraft
        do {
            try viewContext.save()
            editSaveHint = "已保存。可点击「重新分析」用当前文字说明更新结论。"
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

#Preview {
    NavigationStack {
        RecordDetailView(day: Calendar.current.startOfDay(for: Date()))
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
