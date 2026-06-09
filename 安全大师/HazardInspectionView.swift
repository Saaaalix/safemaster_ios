//
//  HazardInspectionView.swift
//  安全大师
//

import SwiftUI
import PhotosUI
import Network

#if os(iOS)
import UIKit
#endif

struct HazardInspectionView: View {
    @Binding var path: [SafetyNavigationRoute]

    /// 每次进入识别页为空；填写后通过 `persistReportCoverFromForm` 写入报告项目设置 / 最近使用。
    @State private var formProjectName: String = ""
    @State private var formInspectorName: String = ""
    @State private var formProjectAbbreviation: String = ""
    @State private var formResponsiblePerson: String = ""
    @State private var formResponsibleUnit: String = ""

    /// 现场照片（顺序即主图、副图；至多 `HazardForm.maxSitePhotos` 张）。
    @State private var hazardSitePhotos: [Data] = []
    @State private var hazardSitePhotoImportedAt: [Date] = []
    @State private var selectedPhotoPreview: SitePhotoPreview?
    @State private var replacingSitePhotoIndex: Int?
    @State private var sitePhotoMessage: String?
    @State private var sitePhotoFailureNotice = false
#if os(iOS)
    @State private var cameraCaptureBuffer: Data?
#endif
    @State private var photoLimitNotice = false
    @State private var hazardLocationDetail: String = ""
    @State private var supplementaryText: String = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var showSitePhotoPicker = false
    @State private var showCamera = false
    @State private var cameraUnavailableNotice = false
    @State private var isAnalyzing = false
    @State private var analysisError: String?
    /// 任一字段聚焦时隐藏底部「排查记录」，避免键盘上方误触。
    @FocusState private var focusedField: InspectionFormField?
    @State private var deepSeekConfigured = false
    @State private var rectificationIntent: HazardRectificationIntent = .immediate
    @State private var selectedSceneType: SafetyInspectionScene = .construction
    @State private var rectificationScheduledDue: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var scheduleAddToCalendar = false
    @State private var showImmediateRectificationSheet = false
    @State private var showScheduledRectificationSheet = false
    @State private var immediateRectNote: String = ""
    @State private var immediateRectPhotoData: Data?
    @State private var immediateRectPickerItem: PhotosPickerItem?
    @State private var showOptionalContext = false
    @State private var selectedHazardTypeTags: Set<String> = []
    @State private var showSavedActions = false
    @State private var lastSavedMessage: String?
    @State private var userManuallyChangedRisk = false
    @State private var userManuallyChangedIntent = false

#if os(iOS) || os(visionOS) || os(macOS)
    @StateObject private var voiceTranscriber = HazardVoiceTranscriber()
#endif
    @StateObject private var connectivity = HazardConnectivityMonitor()
    /// 用户手选的风险等级；保存记录时优先于 AI 分析结果。
    @State private var userRiskLevelOverride: String?
    /// 识别页 Picker：空字符串表示交给 AI。
    @State private var selectedRiskLevelForForm = ""

    private enum InspectionFormField: Hashable {
        case location
        case supplementary
        case reportProjectName
        case reportInspectorName
        case reportProjectAbbreviation
    }

    private enum HazardForm {
        static let maxSitePhotos = 2
    }

    private static let hazardTypeTags = [
        "临边防护",
        "临时用电",
        "消防",
        "机械设备",
        "高处作业",
        "文明施工",
        "个人防护",
        "基坑",
        "脚手架",
        "吊装"
    ]

    private static let productivityAccent = Color(red: 0.95, green: 0.65, blue: 0.3)

    private static let dueDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    private static let photoTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    var body: some View {
        mainPanel
            .navigationTitle("隐患识别")
            .inlineNavigationTitleMode()
    }

    /// 至少填写「隐患描述」；照片可选（如仅有检查记录、无现场照片的场景）。
    private var hasHazardDescription: Bool {
        !supplementaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasMinimumInput: Bool {
        hasHazardDescription
    }

    /// 与 `Image.fromStoredData` 是否可展示一致，用于收紧「按钮行」与「预览行」间距。
    private var hasHazardPhotoForPreview: Bool {
        hazardSitePhotos.contains { Image.fromStoredData($0) != nil }
    }

    private var sitePhotosAtCapacity: Bool {
        hazardSitePhotos.count >= HazardForm.maxSitePhotos
    }

    private var trimmedImmediateRectNote: String {
        immediateRectNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasImmediateRectificationPrefill: Bool {
        !trimmedImmediateRectNote.isEmpty || immediateRectPhotoData != nil
    }

    private var currentQuickSuggestion: QuickHazardSuggestion? {
        QuickHazardSuggestion.suggest(
            text: supplementaryText,
            tags: Array(selectedHazardTypeTags)
        )
    }

    private var selectedHazardTypeTagsOrdered: [String] {
        Self.hazardTypeTags.filter { selectedHazardTypeTags.contains($0) }
    }

    private var effectiveSupplementaryText: String {
        supplementaryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var combinedResponsiblePartyForDisplay: String {
        [formResponsiblePerson, formResponsibleUnit]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    /// 可解码预览的 `(hazardSitePhotos 下标, Image)`，用于并列缩略图与删除（下标与 `hazardSitePhotos` 一致）。
    private var hazardSitePhotoPairs: [(offset: Int, image: Image)] {
        hazardSitePhotos.enumerated().compactMap { index, data in
            guard let img = Image.fromStoredData(data) else { return nil }
            return (offset: index, image: img)
        }
    }

    private var immediateRectificationSummary: some View {
        HStack(alignment: .top, spacing: 10) {
            if let data = immediateRectPhotoData, let image = Image.fromStoredData(data) {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .frame(width: 52, height: 52)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 4) {
                Label("已填写立即整改现场", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)

                Text(trimmedImmediateRectNote.isEmpty ? "已添加整改侧照片，整改说明未填写。" : trimmedImmediateRectNote)
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.green.opacity(0.18), lineWidth: 1)
        }
    }

    private var scheduledRectificationSummary: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(Self.productivityAccent)
                .frame(width: 52, height: 52)
                .background(Self.productivityAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("计划完成日：\(Self.dueDateFormatter.string(from: rectificationScheduledDue))")
                    .font(.caption.weight(.semibold))
                Text(scheduleAddToCalendar ? "保存后会尝试加入系统日历提醒。" : "保存后将建立第 1 轮限期整改，可在详情中继续修改责任人与整改内容。")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Self.productivityAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Self.productivityAccent.opacity(0.18), lineWidth: 1)
        }
    }

    private var rectificationIntentFooter: String {
        guard hasHazardDescription else {
            return "请先用一句话记下隐患，再选择立即整改或稍后安排。"
        }
        switch rectificationIntent {
        case .immediate:
            return "适合未戴安全帽、材料堆放杂乱等现场能马上处理的问题。可补充整改后照片和一句整改说明。"
        case .scheduled:
            return "适合重大或需先沟通方案的问题。可先保存现场事实，后续在隐患详情中再细化整改期限与责任人。"
        }
    }

    private var mainPanel: some View {
        attachLifecycleModifiers(
            attachSharedAlertsModifiers(
                attachIOSModifiers(
                    attachSheetModifiers(
                        attachPickerModifiers(mainPanelFormStack)
                    )
                )
            )
        )
    }

    private var mainPanelFormStack: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                if connectivity.isOffline {
                    statusBanner(
                        icon: "wifi.slash",
                        title: "当前无可用网络",
                        message: "当前仍可先保存现场记录；联网后可在「排查记录」的隐患详情中使用 AI 辅助分析。",
                        tint: .orange
                    )
                }

                if !deepSeekConfigured {
                    statusBanner(
                        icon: "cpu",
                        title: "本地演示分析",
                        message: "未在「我的」完成服务端配置与 Apple 登录同步时，详情页 AI 分析将使用本地演示结论。",
                        tint: Color(.secondaryLabel)
                    )
                }

                hazardPhotoGallery

                hazardTypeTagSection

                inspectionCard(title: "隐患简短记录", systemImage: "text.bubble") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 8) {
                            TextField("一句话记录，例如：3号楼外架作业人员未戴安全帽", text: $supplementaryText, axis: .vertical)
                                .lineLimit(3...6)
                                .focused($focusedField, equals: .supplementary)
#if os(iOS) || os(visionOS) || os(macOS)
                            voiceMicButton(
                                fieldID: InspectionFormField.supplementary,
                                text: $supplementaryText,
                                label: "语音输入隐患描述"
                            )
#endif
                        }
                        .padding(12)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

#if os(iOS) || os(visionOS) || os(macOS)
                        if voiceTranscriber.isActive(fieldID: InspectionFormField.supplementary) {
                            RecordingWaveformView(tint: Self.productivityAccent)
                                .padding(.top, 2)
                                .transition(.opacity.combined(with: .scale))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("现场先抢记事实即可。项目、检查人、地点、正式报告字段可在隐患详情里补齐。")
                                .font(.caption)
                                .foregroundStyle(Color(.secondaryLabel))
                            if let err = voiceTranscriber.lastError {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
#else
                        Text("请填写隐患描述。")
                            .font(.caption)
                            .foregroundStyle(Color(.secondaryLabel))
#endif
                    }
                }

                optionalContextDisclosure

                inspectionCard(title: "风险与整改安排", systemImage: "shield.lefthalf.filled") {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("风险等级", selection: $selectedRiskLevelForForm) {
                            Text("稍后确认").tag("")
                            ForEach(HazardRiskLevel.canonicalOptions, id: \.self) { level in
                                Text(level).tag(level)
                            }
                        }
                        .disabled(!hasHazardDescription)
                        .onChange(of: selectedRiskLevelForForm) { _, new in
                            userManuallyChangedRisk = true
                            userRiskLevelOverride = HazardRiskLevel.normalizedForStorage(new.isEmpty ? nil : new)
                        }

                        quickSuggestionView

                        Divider().opacity(0.35)

                        Picker("整改安排", selection: $rectificationIntent) {
                            Text(HazardRectificationIntent.immediate.shortLabel).tag(HazardRectificationIntent.immediate)
                            Text(HazardRectificationIntent.scheduled.shortLabel).tag(HazardRectificationIntent.scheduled)
                        }
                        .pickerStyle(.segmented)
                        .disabled(!hasHazardDescription)
                        .onChange(of: rectificationIntent) { _, _ in
                            userManuallyChangedIntent = true
                        }

                        Button(action: presentRectificationIntentSheet) {
                            Label(
                                rectificationIntent == .immediate ? "填写立即整改现场…" : "设置限期整改…",
                                systemImage: rectificationIntent == .immediate ? "bolt.fill" : "clock.badge.exclamationmark"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!hasHazardDescription)

                        if rectificationIntent == .immediate, hasImmediateRectificationPrefill {
                            immediateRectificationSummary
                        }

                        if rectificationIntent == .scheduled {
                            scheduledRectificationSummary
                        }

                        Text(rectificationIntentFooter)
                            .font(.footnote)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }

                if let analysisError {
                    inspectionCard(title: "诊断异常", systemImage: "exclamationmark.triangle") {
                        Text(analysisError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color(.systemGroupedBackground))
#if os(iOS)
            .scrollDismissesKeyboard(.interactively)
#endif

            if focusedField == nil {
                Divider()
                quickSaveBottomBar
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var hazardPhotoGallery: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("隐患现场", systemImage: "camera.metering.matrix")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(hazardSitePhotos.count)/\(HazardForm.maxSitePhotos)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5), in: Capsule())
            }

            ZStack(alignment: .bottomTrailing) {
                TabView {
                    if hazardSitePhotoPairs.isEmpty {
                        emptyPhotoHero
                    } else {
                        ForEach(hazardSitePhotoPairs, id: \.offset) { pair in
                            ZStack(alignment: .topTrailing) {
                                Button {
                                    selectedPhotoPreview = makeSitePhotoPreview(for: pair.offset)
                                } label: {
                                    pair.image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 220)
                                        .background(Color.black.opacity(0.06))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    deleteSitePhoto(at: pair.offset)
                                } label: {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.red)
                                        .frame(width: 32, height: 32)
                                        .background(.ultraThinMaterial, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .padding(10)
                                .disabled(isAnalyzing)

                                photoIndexBadge(pair.offset)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                                photoTimeBadge(pair.offset)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            }
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: hazardSitePhotoPairs.count > 1 ? .automatic : .never))
                .frame(height: 220)
                .allowsHitTesting(!hazardSitePhotoPairs.isEmpty)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 6)

                if hazardSitePhotoPairs.isEmpty {
                    primaryPhotoAddMenu
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 24)
                }

                photoAddMenu
                    .padding(14)
            }

            Text("同一隐患最多添加 \(HazardForm.maxSitePhotos) 张现场照片（可选）。有照片时会先经本机 Vision 提取摘要再参与分析。")
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))

            if let sitePhotoMessage {
                Label(sitePhotoMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.vertical, 8)
    }

    private var hazardTypeTagSection: some View {
        inspectionCard(title: "隐患类型", systemImage: "tag.fill") {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(Self.hazardTypeTags, id: \.self) { tag in
                        Button {
                            toggleHazardTypeTag(tag)
                        } label: {
                            Label(tag, systemImage: selectedHazardTypeTags.contains(tag) ? "checkmark.circle.fill" : "circle")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedHazardTypeTags.contains(tag) ? Self.productivityAccent : .secondary)
                    }
                }
                Text("可多选，标签会保存到详情页，并辅助风险类别和整改建议。")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
    }

    private var quickSuggestionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let suggestion = currentQuickSuggestion, hasHazardDescription {
                VStack(alignment: .leading, spacing: 8) {
                    Label("已根据关键词生成建议，可手动修改", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Self.productivityAccent)
                    HStack(spacing: 8) {
                        suggestionPill("风险", suggestion.riskLevel)
                        suggestionPill("类别", suggestion.accidentMinor)
                        suggestionPill("整改", suggestion.intent.shortLabel)
                    }
                    Button {
                        applyQuickSuggestion(suggestion, force: true)
                    } label: {
                        Label("采用建议", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(10)
                .background(Self.productivityAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text("可先不选，在隐患详情中结合 AI 建议与实际情况再确认。")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
    }

    private func suggestionPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var quickSaveBottomBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !hasMinimumInput {
                Label("请先填写一句现场事实", systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            if let lastSavedMessage {
                Label(lastSavedMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
            HStack(spacing: 10) {
                Button(action: saveQuickRecordTapped) {
                    if isAnalyzing {
                        ProgressView("保存中…")
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("保存记录", systemImage: "tray.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Self.productivityAccent)
                .disabled(isAnalyzing || !hasMinimumInput)

                Button {
                    path.append(.inspectionRecordFlatList)
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.title3)
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("排查记录")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .confirmationDialog(
            "已保存到排查记录，可继续补充报告字段",
            isPresented: $showSavedActions,
            titleVisibility: .visible
        ) {
            Button("继续记录下一条") {
                resetForNextQuickRecord()
            }
            Button("去补充详情") {
                path.append(.inspectionRecordFlatList)
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var optionalContextDisclosure: some View {
        DisclosureGroup(isExpanded: $showOptionalContext) {
            VStack(alignment: .leading, spacing: 16) {
                fieldBlock(
                    title: "项目名称",
                    footer: "非必填。导出正式文档前可在隐患详情中补齐。"
                ) {
                    TextField("项目名称", text: $formProjectName)
                        .focused($focusedField, equals: .reportProjectName)
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                        .autocorrectionDisabled(true)
                    RecentValueChipsView(kind: .projectName, text: $formProjectName)
                }

                Divider().opacity(0.35)

                fieldBlock(
                    title: "项目简称",
                    footer: "用于生成文书编号。建议 2-8 位（字母/数字/短横线）。不填则自动截取项目名称。"
                ) {
                    TextField("例如：RCDD 或 润城二期", text: $formProjectAbbreviation)
                        .focused($focusedField, equals: .reportProjectAbbreviation)
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                        .autocorrectionDisabled(true)
                }

                Divider().opacity(0.35)

                fieldBlock(
                    title: "检查人",
                    footer: "非必填。现场节奏快时可以先不写。"
                ) {
                    TextField("检查人姓名", text: $formInspectorName)
                        .focused($focusedField, equals: .reportInspectorName)
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                        .autocorrectionDisabled(true)
                    RecentValueChipsView(kind: .inspectorName, text: $formInspectorName)
                }

                Divider().opacity(0.35)

                fieldBlock(
                    title: "责任人",
                    footer: "选填。用于新建整改轮次的责任人/班组，可在详情中继续修改。"
                ) {
                    TextField("责任人或班组", text: $formResponsiblePerson)
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                        .autocorrectionDisabled(true)
                    RecentValueChipsView(kind: .rectificationResponsible, text: $formResponsiblePerson)
                }

                Divider().opacity(0.35)

                fieldBlock(
                    title: "责任单位",
                    footer: "选填。连续记录同一单位问题时会自动带出。"
                ) {
                    TextField("责任单位", text: $formResponsibleUnit)
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                        .autocorrectionDisabled(true)
                    RecentValueChipsView(kind: .rectificationResponsibleUnit, text: $formResponsibleUnit)
                }

                Divider().opacity(0.35)

                fieldBlock(
                    title: "隐患地点",
                    footer: "非必填。可只选大类，也可补充楼栋、房间、设备旁等细节。"
                ) {
                    HStack(spacing: 10) {
                        TextField("补充具体地点", text: $hazardLocationDetail)
                            .focused($focusedField, equals: .location)
#if os(iOS)
                            .textInputAutocapitalization(.never)
#endif
                            .autocorrectionDisabled(true)

                        Divider()
                            .frame(height: 24)

                        Menu {
                            ForEach(SafetyInspectionScene.allCases, id: \.self) { scene in
                                Button {
                                    selectedSceneType = scene
                                } label: {
                                    if selectedSceneType == scene {
                                        Label(scene.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(scene.rawValue)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(selectedSceneType.rawValue)
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.top, 12)
        } label: {
            Label("补充信息（非必填）", systemImage: "text.badge.plus")
                .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
    }

    private var emptyPhotoHero: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Self.productivityAccent.opacity(0.28),
                    Color(.systemGray5),
                    Color(.secondarySystemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
    }

    private var primaryPhotoAddMenu: some View {
        photoSourceMenu {
            VStack(spacing: 10) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Self.productivityAccent)
                Text("添加现场主图")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("照片将作为 AI 诊断的视觉上下文")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("添加现场主图")
    }

    private var photoAddMenu: some View {
        photoSourceMenu {
            Label(sitePhotosAtCapacity ? "已达上限" : "添加副图", systemImage: "plus")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .foregroundStyle(.primary)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(Color.white.opacity(0.45), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private func photoSourceMenu<LabelContent: View>(
        @ViewBuilder label: () -> LabelContent
    ) -> some View {
        Menu {
#if os(iOS)
            Button {
                presentCameraIfPossible()
            } label: {
                Label("拍照", systemImage: "camera.fill")
            }
#endif

            Button {
                stopVoiceBeforePhotoSource()
                showSitePhotoPicker = true
            } label: {
                Label("从相册选择照片", systemImage: "photo.on.rectangle.angled")
            }
        } label: {
            label()
        }
        .disabled(sitePhotosAtCapacity || isAnalyzing)
    }

    private func photoIndexBadge(_ index: Int) -> some View {
        Text(index == 0 ? "主图" : "副图 \(index)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.35), in: Capsule())
    }

    private func photoTimeBadge(_ index: Int) -> some View {
        let date = hazardSitePhotoImportedAt.indices.contains(index) ? hazardSitePhotoImportedAt[index] : Date()
        return Text("导入时间：\(Self.photoTimeFormatter.string(from: date))")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.35), in: Capsule())
    }

    private func statusBanner(icon: String, title: String, message: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
        .padding(.vertical, 8)
    }

    private func inspectionCard<Content: View>(
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

    private func fieldBlock<Content: View>(
        title: String,
        footer: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
            content()
            Text(footer)
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))
        }
    }

    @ViewBuilder
    private func attachPickerModifiers<Content: View>(_ content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $showSitePhotoPicker,
                selection: $pickerItem,
                matching: .images
            )
            .onChange(of: showSitePhotoPicker) { _, presented in
                if presented {
                    stopVoiceBeforePhotoSource()
                }
            }
#if os(iOS)
            .onChange(of: showCamera) { _, presented in
                if presented {
                    stopVoiceBeforePhotoSource()
                }
            }
#endif
            .onChange(of: rectificationIntent) { _, new in
                handleRectificationIntentChange(new)
            }
            .onChange(of: immediateRectPickerItem) { _, new in
                guard let new else { return }
                Task {
                    if let data = try? await new.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            let stamped = stampedPhotoDataForImmediateRectification(from: data)
                            immediateRectPhotoData = stamped
                            SitePhotoLibrarySaver.saveToPhotoLibraryIfPermitted(stamped, source: "立即整改相册照片")
                        }
                    }
                }
            }
    }

    @ViewBuilder
    private func attachSheetModifiers<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $showImmediateRectificationSheet) {
                HazardImmediateRectificationSheet(
                    note: $immediateRectNote,
                    photoData: $immediateRectPhotoData,
                    pickerItem: $immediateRectPickerItem,
                    locationLabel: watermarkLocationLabel(),
                    inspectorName: trimmedFormInspectorName()
                )
            }
            .sheet(isPresented: $showScheduledRectificationSheet) {
                HazardScheduledRectificationSheet(
                    dueDate: $rectificationScheduledDue,
                    addToCalendar: $scheduleAddToCalendar
                )
            }
            .sheet(item: $selectedPhotoPreview) { preview in
                SitePhotoPreviewSheet(
                    preview: preview,
                    onDelete: {
                        deleteSitePhoto(at: preview.index)
                        selectedPhotoPreview = nil
                    },
                    onReplace: {
                        replacingSitePhotoIndex = preview.index
                        selectedPhotoPreview = nil
                        showSitePhotoPicker = true
                    }
                )
            }
    }

#if os(iOS)
    @ViewBuilder
    private func attachIOSModifiers<Content: View>(_ content: Content) -> some View {
        content
            .toolbar {
                if focusedField != nil {
                    ToolbarItemGroup(placement: .keyboard) {
                        Button("完成") {
                            focusedField = nil
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
            .fullScreenCover(isPresented: $showCamera) {
                CameraImagePicker(imageData: $cameraCaptureBuffer)
                    .ignoresSafeArea()
            }
            .alert("无法打开相机", isPresented: $cameraUnavailableNotice) {
                Button("好的", role: .cancel) {}
            } message: {
                Text("模拟器通常没有可用摄像头；部分环境也会报 AVFoundation 错误。请使用「从相册选择照片」，或在真机上调试拍照。")
            }
            .onChange(of: cameraCaptureBuffer) { _, new in
                guard let new, !new.isEmpty else { return }
                appendSitePhotoIfAllowed(new)
                cameraCaptureBuffer = nil
            }
    }
#else
    @ViewBuilder
    private func attachIOSModifiers<Content: View>(_ content: Content) -> some View {
        content
    }
#endif

    @ViewBuilder
    private func attachSharedAlertsModifiers<Content: View>(_ content: Content) -> some View {
        content
            .alert("已达照片上限", isPresented: $photoLimitNotice) {
                Button("好的", role: .cancel) {}
            } message: {
                Text("同一隐患最多保存 \(HazardForm.maxSitePhotos) 张现场照片，请先删除一张后再添加。")
            }
            .onChange(of: pickerItem) { _, new in
                stopVoiceBeforePhotoSource()
                guard let new else { return }
                Task {
                    if let data = try? await new.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            appendSitePhotoIfAllowed(data, replacing: replacingSitePhotoIndex)
                            replacingSitePhotoIndex = nil
                            pickerItem = nil
                        }
                    } else {
                        await MainActor.run {
                            replacingSitePhotoIndex = nil
                            pickerItem = nil
                            sitePhotoFailureNotice = true
                        }
                    }
                }
            }
            .alert("照片添加失败", isPresented: $sitePhotoFailureNotice) {
                Button("好的", role: .cancel) {}
            } message: {
                Text("照片添加失败，请重新选择或检查相册权限。")
            }
    }

    @ViewBuilder
    private func attachLifecycleModifiers<Content: View>(_ content: Content) -> some View {
        content
            .onAppear {
                applyRecentQuickFieldsIfEmpty()
                formProjectAbbreviation = ReportProjectSettingsStore.projectAbbreviationRaw
                EvidenceLocationProvider.shared.start()
                refreshDeepSeekConfiguredFlag()
                connectivity.start()
            }
            .onDisappear {
#if os(iOS) || os(visionOS) || os(macOS)
                voiceTranscriber.stopSessionIfNeeded()
#endif
                connectivity.stop()
                persistReportCoverFromForm()
            }
            .onReceive(NotificationCenter.default.publisher(for: .safemasterAccessTokenDidChange)) { _ in
                refreshDeepSeekConfiguredFlag()
            }
            .onReceive(NotificationCenter.default.publisher(for: .appleUserSessionDidChange)) { _ in
                refreshDeepSeekConfiguredFlag()
            }
            .onChange(of: focusedField) { old, _ in
                recordReportCoverFieldIfNeeded(leaving: old)
            }
            .onChange(of: supplementaryText) { _, _ in
                if let suggestion = currentQuickSuggestion {
                    applyQuickSuggestion(suggestion, force: false)
                }
            }
    }

    private func recordReportCoverFieldIfNeeded(leaving field: InspectionFormField?) {
        switch field {
        case .reportProjectName:
            RecentFieldValuesStore.record(formProjectName, for: .projectName)
        case .reportInspectorName:
            RecentFieldValuesStore.record(formInspectorName, for: .inspectorName)
        default:
            break
        }
    }

    private func persistReportCoverFromForm() {
        RecentFieldValuesStore.recordReportCover(
            projectName: formProjectName,
            inspectorName: formInspectorName
        )
        RecentFieldValuesStore.recordQuickInspectionFields(
            projectName: formProjectName,
            inspectorName: formInspectorName,
            location: trimmedHazardLocation(),
            responsiblePerson: formResponsiblePerson,
            responsibleUnit: formResponsibleUnit
        )
        ReportProjectSettingsStore.persistIfNonEmpty(
            projectName: formProjectName,
            inspectorName: formInspectorName,
            projectAbbreviation: formProjectAbbreviation
        )
    }

    private func trimmedHazardLocation() -> String {
        let detail = hazardLocationDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else { return "" }
        return "\(selectedSceneType.rawValue) - \(detail)"
    }

    private func trimmedFormProjectName() -> String? {
        let t = formProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func trimmedFormInspectorName() -> String? {
        let t = formInspectorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func handleRectificationIntentChange(_ new: HazardRectificationIntent) {
        guard hasHazardDescription else { return }
        if new == .immediate {
            scheduleAddToCalendar = false
        }
    }

    private func applyRecentQuickFieldsIfEmpty() {
        let recent = RecentFieldValuesStore.lastQuickInspectionFields()
        if formProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            formProjectName = recent.projectName
        }
        if formInspectorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            formInspectorName = recent.inspectorName
        }
        if hazardLocationDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hazardLocationDetail = Self.locationDetail(fromStoredLocation: recent.location)
        }
        if formResponsiblePerson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            formResponsiblePerson = recent.responsiblePerson
        }
        if formResponsibleUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            formResponsibleUnit = recent.responsibleUnit
        }
    }

    private static func locationDetail(fromStoredLocation raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for scene in SafetyInspectionScene.allCases {
            let prefix = "\(scene.rawValue) - "
            if trimmed.hasPrefix(prefix) {
                return String(trimmed.dropFirst(prefix.count))
            }
        }
        return trimmed
    }

    private func presentRectificationIntentSheet() {
        switch rectificationIntent {
        case .immediate:
            showImmediateRectificationSheet = true
        case .scheduled:
            showScheduledRectificationSheet = true
        }
    }

    private func saveQuickRecordTapped() {
        Task {
            await saveQuickRecord()
        }
    }

    private func toggleHazardTypeTag(_ tag: String) {
        if selectedHazardTypeTags.contains(tag) {
            selectedHazardTypeTags.remove(tag)
        } else {
            selectedHazardTypeTags.insert(tag)
        }
        if let suggestion = currentQuickSuggestion {
            applyQuickSuggestion(suggestion, force: false)
        }
    }

    private func applyQuickSuggestion(_ suggestion: QuickHazardSuggestion, force: Bool) {
        if force || !userManuallyChangedRisk || selectedRiskLevelForForm.isEmpty {
            selectedRiskLevelForForm = suggestion.riskLevel
            userRiskLevelOverride = suggestion.riskLevel
            if force { userManuallyChangedRisk = false }
        }
        if force || !userManuallyChangedIntent {
            rectificationIntent = suggestion.intent
            if force { userManuallyChangedIntent = false }
        }
    }

    private func resetForNextQuickRecord() {
        hazardSitePhotos.removeAll()
        hazardSitePhotoImportedAt.removeAll()
        selectedPhotoPreview = nil
        replacingSitePhotoIndex = nil
        sitePhotoMessage = nil
        supplementaryText = ""
        selectedHazardTypeTags.removeAll()
        selectedRiskLevelForForm = ""
        userRiskLevelOverride = nil
        userManuallyChangedRisk = false
        userManuallyChangedIntent = false
        rectificationIntent = .immediate
        rectificationScheduledDue = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        scheduleAddToCalendar = false
        immediateRectNote = ""
        immediateRectPhotoData = nil
        lastSavedMessage = nil
        analysisError = nil
    }

    private func stopVoiceBeforePhotoSource() {
#if os(iOS) || os(visionOS) || os(macOS)
        voiceTranscriber.stopSessionIfNeeded()
#endif
    }

    private func appendSitePhotoIfAllowed(_ data: Data, replacing indexToReplace: Int? = nil) {
        guard !data.isEmpty else { return }
        if let indexToReplace {
            guard hazardSitePhotos.indices.contains(indexToReplace) else {
                sitePhotoFailureNotice = true
                return
            }
            let stamped = stampedPhotoDataForHazard(from: data)
            hazardSitePhotos[indexToReplace] = stamped
            if hazardSitePhotoImportedAt.indices.contains(indexToReplace) {
                hazardSitePhotoImportedAt[indexToReplace] = Date()
            }
            sitePhotoMessage = "已替换\(indexToReplace == 0 ? "主图" : "副图")"
            SitePhotoLibrarySaver.saveToPhotoLibraryIfPermitted(stamped, source: "隐患排查现场照片")
            return
        }
        guard hazardSitePhotos.count < HazardForm.maxSitePhotos else {
            photoLimitNotice = true
            return
        }
        let stamped = stampedPhotoDataForHazard(from: data)
        let nextIndex = hazardSitePhotos.count
        hazardSitePhotos.append(stamped)
        hazardSitePhotoImportedAt.append(Date())
        sitePhotoMessage = "已添加\(nextIndex == 0 ? "主图" : "副图")"
        SitePhotoLibrarySaver.saveToPhotoLibraryIfPermitted(stamped, source: "隐患排查现场照片")
    }

    private func deleteSitePhoto(at index: Int) {
        guard hazardSitePhotos.indices.contains(index) else { return }
        hazardSitePhotos.remove(at: index)
        if hazardSitePhotoImportedAt.indices.contains(index) {
            hazardSitePhotoImportedAt.remove(at: index)
        }
        sitePhotoMessage = "已删除现场照片"
    }

    private func makeSitePhotoPreview(for index: Int) -> SitePhotoPreview? {
        guard hazardSitePhotos.indices.contains(index),
              let image = Image.fromStoredData(hazardSitePhotos[index]) else { return nil }
        let date = hazardSitePhotoImportedAt.indices.contains(index) ? hazardSitePhotoImportedAt[index] : Date()
        return SitePhotoPreview(index: index, label: index == 0 ? "主图" : "副图", importedAt: date, image: image)
    }

    private func stampedPhotoDataForHazard(from data: Data) -> Data {
        let stamp = EvidencePhotoStampContext(
            projectName: watermarkLocationLabel(),
            shooterName: EvidenceWatermarkIdentity.resolvedShooterName(preferred: trimmedFormInspectorName()),
            sceneName: "隐患现场照片",
            sourceName: "安全大师",
            capturedAt: Date(),
            coordinate: EvidenceLocationProvider.shared.snapshotCoordinate()
        )
        return Data.watermarkedPhotoStorageData(from: data, context: stamp) ?? (Data.optimizedPhotoStorageData(from: data) ?? data)
    }

    private func stampedPhotoDataForImmediateRectification(from data: Data) -> Data {
        let stamp = EvidencePhotoStampContext(
            projectName: watermarkLocationLabel(),
            shooterName: EvidenceWatermarkIdentity.resolvedShooterName(preferred: trimmedFormInspectorName()),
            sceneName: "立即整改照片",
            sourceName: "安全大师",
            capturedAt: Date(),
            coordinate: EvidenceLocationProvider.shared.snapshotCoordinate()
        )
        return Data.watermarkedPhotoStorageData(from: data, context: stamp) ?? (Data.optimizedPhotoStorageData(from: data) ?? data)
    }

    private func watermarkLocationLabel() -> String {
        let detail = hazardLocationDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            return selectedSceneType.rawValue
        }
        return "\(selectedSceneType.rawValue)-\(detail)"
    }

#if os(iOS) || os(visionOS) || os(macOS)
    private func voiceMicButton<FieldID: Hashable>(
        fieldID: FieldID,
        text: Binding<String>,
        onFinished: ((String) -> Void)? = nil,
        label: String,
        disabled: Bool = false
    ) -> some View {
        VoiceInputIconButton(
            isRecordingForThisField: voiceTranscriber.isActive(fieldID: fieldID),
            isDisabled: disabled || isAnalyzing,
            accessibilityLabel: label
        ) {
            Task {
                await voiceTranscriber.toggle(fieldID: fieldID, onto: text, onFinished: onFinished)
            }
        }
    }
#endif

    private func refreshDeepSeekConfiguredFlag() {
        let base = SafeMasterAPIConfiguration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = KeychainStore.safemasterAccessToken()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        deepSeekConfigured = !base.isEmpty && !token.isEmpty
    }

    private func photoSourceColumn(title: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func hazardSitePhotoCell(image: Image, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            image
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 168)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))

            Button {
                guard hazardSitePhotos.indices.contains(index) else { return }
                hazardSitePhotos.remove(at: index)
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
            .buttonStyle(.plain)
            .padding(6)
            .disabled(isAnalyzing)
            .accessibilityLabel("删除照片 \(index + 1)")
        }
        .frame(maxWidth: .infinity)
    }

#if os(iOS)
    private func presentCameraIfPossible() {
#if targetEnvironment(simulator)
        cameraUnavailableNotice = true
#else
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraUnavailableNotice = true
            return
        }
        stopVoiceBeforePhotoSource()
        showCamera = true
#endif
    }
#endif

    @MainActor
    private func saveQuickRecord() async {
#if os(iOS) || os(visionOS) || os(macOS)
        voiceTranscriber.stopSessionIfNeeded()
#endif
        persistReportCoverFromForm()
        analysisError = nil
        isAnalyzing = true
        defer { isAnalyzing = false }

        let hasPhoto = hazardSitePhotos.contains { !$0.isEmpty }
        let analysis = makeQuickAnalysisResult(
            supplementaryText: supplementaryText,
            location: trimmedHazardLocation(),
            hasPhoto: hasPhoto
        )
        let payload = makeResultPayload(analysis: analysis)
        do {
            let saved = try await PersistenceController.shared.performBackgroundTask { bgContext in
                InspectionFinding.savePayload(payload, context: bgContext)
            }
            guard saved else {
                analysisError = "无法保存记录，请检查存储空间或稍后重试。"
                return
            }
            if payload.rectificationIntent == .scheduled, payload.addDeadlineToDeviceCalendar {
                addDeadlineReminder(for: payload)
            }
            lastSavedMessage = "已保存到排查记录，可继续补充报告字段"
            showSavedActions = true
        } catch {
            analysisError = "无法保存记录，请检查存储空间或稍后重试。"
        }
    }

    private func makeQuickAnalysisResult(
        supplementaryText: String,
        location: String,
        hasPhoto: Bool
    ) -> HazardAnalysisResult {
        var analysis = HazardAnalysisResult.offlineManualRecord(
            supplementaryText: supplementaryText,
            location: location,
            hasPhoto: hasPhoto
        )
        guard let suggestion = currentQuickSuggestion else { return analysis }
        analysis.riskLevel = suggestion.riskLevel
        analysis.accidentCategoryMajor = suggestion.accidentMajor
        analysis.accidentCategoryMinor = suggestion.accidentMinor
        analysis.rectificationMeasures = suggestion.rectificationRequirement
        analysis.legalBasis = "当前为本地快记建议：请在详情页点击「智能优化」后复核正式依据。"
        return analysis
    }

    private func makeResultPayload(analysis: HazardAnalysisResult) -> HazardResultPayload {
        return HazardResultPayload(
            photoData: hazardSitePhotos.first,
            secondaryPhotoData: hazardSitePhotos.count > 1 ? hazardSitePhotos[1] : nil,
            location: trimmedHazardLocation(),
            supplementaryText: supplementaryText,
            analysis: analysis,
            rectificationIntent: rectificationIntent,
            rectificationPlannedDueAt: rectificationIntent == .scheduled ? rectificationScheduledDue : nil,
            prefillRectificationActionNote: immediateRectNote,
            prefillRectificationPhotoData: immediateRectPhotoData,
            addDeadlineToDeviceCalendar: rectificationIntent == .scheduled && scheduleAddToCalendar,
            userRiskLevelOverride: resolvedUserRiskLevelOverride,
            sceneType: selectedSceneType,
            hazardTypeTags: selectedHazardTypeTagsOrdered,
            reportProjectName: trimmedFormProjectName(),
            reportInspectorName: trimmedFormInspectorName(),
            rectificationResponsiblePerson: formResponsiblePerson,
            rectificationResponsibleUnit: formResponsibleUnit
        )
    }

    private func addDeadlineReminder(for payload: HazardResultPayload) {
        let loc = payload.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = loc.isEmpty ? "安全大师·隐患整改截止" : "安全大师·整改截止（\(loc)）"
        let snippet = String(payload.analysis.hazardDescription.prefix(200))
        let notes = "地点：\(loc.isEmpty ? "（未填）" : loc)\n\n\(snippet)"
        let due = payload.rectificationPlannedDueAt ?? rectificationScheduledDue
        Task {
            _ = await RectificationCalendarExporter.tryAddDeadlineReminder(
                title: title,
                notes: notes,
                deadlineDay: due,
                location: loc.isEmpty ? nil : loc
            )
        }
    }

    private var resolvedUserRiskLevelOverride: String? {
        if let speech = userRiskLevelOverride { return speech }
        let picked = selectedRiskLevelForForm.trimmingCharacters(in: .whitespacesAndNewlines)
        return HazardRiskLevel.normalizedForStorage(picked.isEmpty ? nil : picked)
    }
}

// MARK: - 整改安排 Sheet（隐患识别）

private struct QuickHazardSuggestion {
    var riskLevel: String
    var accidentMajor: String
    var accidentMinor: String
    var rectificationRequirement: String
    var intent: HazardRectificationIntent

    static func suggest(text: String, tags: [String]) -> QuickHazardSuggestion? {
        let source = (text + " " + tags.joined(separator: " "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }

        let rules: [(keywords: [String], suggestion: QuickHazardSuggestion)] = [
            (
                ["临边", "防护栏", "栏杆", "洞口", "高处", "坠落", "基坑"],
                QuickHazardSuggestion(
                    riskLevel: "较大风险",
                    accidentMajor: "高处与建筑施工类",
                    accidentMinor: "高处坠落",
                    rectificationRequirement: "立即设置临边防护栏杆、挡脚板和警示标识，整改完成后拍照复查。",
                    intent: .scheduled
                )
            ),
            (
                ["临时用电", "配电箱", "电缆", "电线", "漏电", "触电", "私拉乱接"],
                QuickHazardSuggestion(
                    riskLevel: "较大风险",
                    accidentMajor: "用电与火灾类",
                    accidentMinor: "触电",
                    rectificationRequirement: "立即停用不符合要求的用电设施，规范配电箱、漏保和线路敷设，经电工检查合格后恢复使用。",
                    intent: .immediate
                )
            ),
            (
                ["消防", "灭火器", "易燃", "火灾", "动火"],
                QuickHazardSuggestion(
                    riskLevel: "较大风险",
                    accidentMajor: "消防与动火类",
                    accidentMinor: "火灾",
                    rectificationRequirement: "清理可燃物，补齐灭火器材和警示标识，动火作业按审批和监护要求落实后复查。",
                    intent: .immediate
                )
            ),
            (
                ["机械", "防护罩", "卷入", "设备", "传动", "吊装", "起重"],
                QuickHazardSuggestion(
                    riskLevel: "较大风险",
                    accidentMajor: "机械设备类",
                    accidentMinor: "机械伤害",
                    rectificationRequirement: "停机整改设备防护装置，设置警戒和操作规程，验收合格后方可继续作业。",
                    intent: .scheduled
                )
            ),
            (
                ["脚手架", "脚手板", "连墙件", "架体"],
                QuickHazardSuggestion(
                    riskLevel: "较大风险",
                    accidentMajor: "高处与建筑施工类",
                    accidentMinor: "坍塌/高处坠落",
                    rectificationRequirement: "按方案补齐脚手架构配件和防护措施，组织验收合格后再投入使用。",
                    intent: .scheduled
                )
            ),
            (
                ["安全帽", "安全带", "个人防护", "未佩戴"],
                QuickHazardSuggestion(
                    riskLevel: "一般风险",
                    accidentMajor: "个人防护类",
                    accidentMinor: "物体打击/高处坠落",
                    rectificationRequirement: "立即纠正个人防护用品佩戴问题，现场教育提醒并复查同类作业人员。",
                    intent: .immediate
                )
            )
        ]

        for rule in rules where rule.keywords.contains(where: { source.contains($0) }) {
            return rule.suggestion
        }

        if !tags.isEmpty {
            return QuickHazardSuggestion(
                riskLevel: "一般风险",
                accidentMajor: "建筑施工安全类",
                accidentMinor: tags.first ?? "一般隐患",
                rectificationRequirement: "按所选隐患类型落实整改措施，整改完成后拍照留存并复查确认。",
                intent: .scheduled
            )
        }

        return nil
    }
}

private struct SitePhotoPreview: Identifiable {
    let id = UUID()
    var index: Int
    var label: String
    var importedAt: Date
    var image: Image
}

private struct SitePhotoPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let preview: SitePhotoPreview
    let onDelete: () -> Void
    let onReplace: () -> Void

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                preview.image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Label(preview.label, systemImage: "photo")
                        .font(.headline.weight(.semibold))
                    Text("导入时间：\(Self.formatter.string(from: preview.importedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("删除", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onReplace()
                    } label: {
                        Label("替换", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("照片预览")
            .inlineNavigationTitleMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct HazardImmediateRectificationSheet: View {
    @Binding var note: String
    @Binding var photoData: Data?
    @Binding var pickerItem: PhotosPickerItem?
    let locationLabel: String?
    let inspectorName: String?

    @Environment(\.dismiss) private var dismiss
    private static let productivityAccent = Color(red: 0.95, green: 0.65, blue: 0.3)
#if os(iOS)
    @State private var showCamera = false
    @State private var cameraUnavailable = false
    @State private var cameraCaptureBuffer: Data?
#endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HazardSheetCard(title: "整改侧照片", systemImage: "camera.fill") {
                        VStack(alignment: .leading, spacing: 12) {
#if os(iOS)
                            Button {
                                openCameraIfPossible()
                            } label: {
                                Label("拍照", systemImage: "camera.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Self.productivityAccent)
#endif
                            PhotosPicker(selection: $pickerItem, matching: .images) {
                                Label("从相册选择", systemImage: "photo.on.rectangle.angled")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            if let img = Image.fromStoredData(photoData) {
                                ZStack(alignment: .bottomLeading) {
                                    img
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 200)
                                        .background(Color.black.opacity(0.06))
                                    Text("整改后")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.black.opacity(0.35), in: Capsule())
                                        .padding(10)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }

                            Text("可与上方「隐患照片」不同，用于记录已采取的现场措施。")
                                .font(.caption)
                                .foregroundStyle(Color(.secondaryLabel))
                        }
                    }

                    HazardSheetCard(title: "整改说明", systemImage: "text.alignleft") {
                        TextField("已采取的措施或现场情况（可选）", text: $note, axis: .vertical)
                            .lineLimit(3...8)
                            .padding(12)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("立即整改")
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
#if os(iOS)
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker(imageData: $cameraCaptureBuffer)
                .ignoresSafeArea()
        }
        .onChange(of: cameraCaptureBuffer) { _, new in
            guard let new, !new.isEmpty else { return }
            let stamped = stampedImmediateRectPhotoData(new)
            photoData = stamped
            SitePhotoLibrarySaver.saveToPhotoLibraryIfPermitted(stamped, source: "立即整改拍照照片")
            cameraCaptureBuffer = nil
        }
        .alert("无法打开相机", isPresented: $cameraUnavailable) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("当前设备无可用摄像头。请使用「从相册选择」，或在系统设置中检查相机权限。")
        }
#endif
#if os(iOS) || os(visionOS)
        .presentationDetents([.medium, .large])
#endif
    }

#if os(iOS)
    private func openCameraIfPossible() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraUnavailable = true
            return
        }
        EvidenceLocationProvider.shared.start()
        showCamera = true
    }

    private func stampedImmediateRectPhotoData(_ data: Data) -> Data {
        let stamp = EvidencePhotoStampContext(
            projectName: locationLabel,
            shooterName: EvidenceWatermarkIdentity.resolvedShooterName(preferred: inspectorName),
            sceneName: "立即整改照片",
            sourceName: "安全大师",
            capturedAt: Date(),
            coordinate: EvidenceLocationProvider.shared.snapshotCoordinate()
        )
        return Data.watermarkedPhotoStorageData(from: data, context: stamp) ?? (Data.optimizedPhotoStorageData(from: data) ?? data)
    }
#endif
}

private struct HazardScheduledRectificationSheet: View {
    @Binding var dueDate: Date
    @Binding var addToCalendar: Bool

    @Environment(\.dismiss) private var dismiss
    private static let productivityAccent = Color(red: 0.95, green: 0.65, blue: 0.3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HazardSheetCard(title: "计划完成日", systemImage: "calendar.badge.clock") {
                        DatePicker(
                            "计划完成日",
                            selection: $dueDate,
                            displayedComponents: [.date]
                        )
                        .environment(\.locale, Locale(identifier: "zh_CN"))

                        Text("保存隐患记录后，将按此日期建立限期整改轮次。")
                            .font(.caption)
                            .foregroundStyle(Color(.secondaryLabel))
                    }

                    HazardSheetCard(title: "日历提醒", systemImage: "bell.badge") {
                        Toggle("加入系统日历提醒", isOn: $addToCalendar)
                            .tint(Self.productivityAccent)

                        Text("开启后，保存记录成功时会请求日历权限并写入一条「全天」事件作为截止提醒。")
                            .font(.caption)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("限期整改")
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
#if os(iOS) || os(visionOS)
        .presentationDetents([.medium, .large])
#endif
    }
}

private struct HazardSheetCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
            content
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
        .padding(.vertical, 8)
    }
}

// MARK: - 网络可达性（隐患识别页弱网提示）

@MainActor
private final class HazardConnectivityMonitor: ObservableObject {
    @Published private(set) var isOffline = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.safemaster.hazard.connectivity")

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOffline = path.status != .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}

#Preview {
    BuildingSafetyHubView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
