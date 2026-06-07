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

    /// 现场照片（顺序即主图、副图；至多 `HazardForm.maxSitePhotos` 张）。
    @State private var hazardSitePhotos: [Data] = []
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

    private static let productivityAccent = Color(red: 0.95, green: 0.65, blue: 0.3)

    private static let dueDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy年M月d日"
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
                            userRiskLevelOverride = HazardRiskLevel.normalizedForStorage(new.isEmpty ? nil : new)
                        }

                        Text("可先不选，在隐患详情中结合 AI 建议与实际情况再确认。")
                            .font(.caption)
                            .foregroundStyle(Color(.secondaryLabel))

                        Divider().opacity(0.35)

                        Picker("整改安排", selection: $rectificationIntent) {
                            Text(HazardRectificationIntent.immediate.shortLabel).tag(HazardRectificationIntent.immediate)
                            Text(HazardRectificationIntent.scheduled.shortLabel).tag(HazardRectificationIntent.scheduled)
                        }
                        .pickerStyle(.segmented)
                        .disabled(!hasHazardDescription)

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

                inspectionCard(title: "保存记录", systemImage: "tray.and.arrow.down") {
                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: saveQuickRecordTapped) {
                            if isAnalyzing {
                                HStack {
                                    Spacer()
                                    ProgressView("保存中…")
                                        .tint(.white)
                                    Spacer()
                                }
                            } else {
                                Label("保存记录", systemImage: "tray.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Self.productivityAccent)
                        .disabled(isAnalyzing || !hasMinimumInput)

                        Label {
                            Text("保存后进入「排查记录」，在隐患详情中可继续补充正式字段、使用 AI 辅助分析图片和生成整改建议。")
                                .font(.caption)
                                .foregroundStyle(Color(.secondaryLabel))
                        } icon: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(Color(.secondaryLabel))
                        }
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

                Button {
                    path.append(.inspectionRecordFlatList)
                } label: {
                    Label("排查记录", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .foregroundStyle(.primary)
                .background(.ultraThinMaterial)
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
                                pair.image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 220)
                                    .background(Color.black.opacity(0.06))

                                Button {
                                    guard hazardSitePhotos.indices.contains(pair.offset) else { return }
                                    hazardSitePhotos.remove(at: pair.offset)
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
        }
        .padding(.vertical, 8)
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
                    RecentValueChipsView(kind: .projectName, text: $formProjectName)
                }

                Divider().opacity(0.35)

                fieldBlock(
                    title: "项目简称",
                    footer: "用于生成文书编号。建议 2-8 位（字母/数字/短横线）。不填则自动截取项目名称。"
                ) {
                    TextField("例如：RCDD 或 润城二期", text: $formProjectAbbreviation)
                        .focused($focusedField, equals: .reportProjectAbbreviation)
                        .textInputAutocapitalization(.characters)
                }

                Divider().opacity(0.35)

                fieldBlock(
                    title: "检查人",
                    footer: "非必填。现场节奏快时可以先不写。"
                ) {
                    TextField("检查人姓名", text: $formInspectorName)
                        .focused($focusedField, equals: .reportInspectorName)
                    RecentValueChipsView(kind: .inspectorName, text: $formInspectorName)
                }

                Divider().opacity(0.35)

                fieldBlock(
                    title: "隐患地点",
                    footer: "非必填。可只选大类，也可补充楼栋、房间、设备旁等细节。"
                ) {
                    HStack(spacing: 10) {
                        TextField("补充具体地点", text: $hazardLocationDetail)
                            .focused($focusedField, equals: .location)

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
                            appendSitePhotoIfAllowed(data)
                            pickerItem = nil
                        }
                    }
                }
            }
    }

    @ViewBuilder
    private func attachLifecycleModifiers<Content: View>(_ content: Content) -> some View {
        content
            .onAppear {
                formProjectName = ""
                formInspectorName = ""
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

    private func stopVoiceBeforePhotoSource() {
#if os(iOS) || os(visionOS) || os(macOS)
        voiceTranscriber.stopSessionIfNeeded()
#endif
    }

    private func appendSitePhotoIfAllowed(_ data: Data) {
        guard !data.isEmpty else { return }
        guard hazardSitePhotos.count < HazardForm.maxSitePhotos else {
            photoLimitNotice = true
            return
        }
        let stamped = stampedPhotoDataForHazard(from: data)
        hazardSitePhotos.append(stamped)
        SitePhotoLibrarySaver.saveToPhotoLibraryIfPermitted(stamped, source: "隐患排查现场照片")
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
        let analysis = HazardAnalysisResult.offlineManualRecord(
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
            path.append(.inspectionRecordFlatList)
        } catch {
            analysisError = "无法保存记录，请检查存储空间或稍后重试。"
        }
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
            reportProjectName: trimmedFormProjectName(),
            reportInspectorName: trimmedFormInspectorName()
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
                                img
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 200)
                                    .background(Color.black.opacity(0.06))
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
