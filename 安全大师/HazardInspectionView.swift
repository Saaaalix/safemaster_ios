//
//  HazardInspectionView.swift
//  安全大师
//

import SwiftUI
import PhotosUI

#if os(iOS)
import UIKit
#endif

struct HazardInspectionView: View {
    @Binding var path: [SafetyNavigationRoute]

    @Environment(\.managedObjectContext) private var viewContext

    /// 现场照片（顺序即主图、副图；至多 `HazardForm.maxSitePhotos` 张）。
    @State private var hazardSitePhotos: [Data] = []
#if os(iOS)
    @State private var cameraCaptureBuffer: Data?
#endif
    @State private var photoLimitNotice = false
    @State private var supplementaryText: String = ""
    @State private var location: String = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var cameraUnavailableNotice = false
    @State private var isAnalyzing = false
    @State private var analysisError: String?
    @State private var analysisTask: Task<Void, Never>?
    /// 任一字段聚焦时隐藏底部「排查记录」，避免键盘上方误触。
    @FocusState private var focusedField: InspectionFormField?
    @State private var deepSeekConfigured = false
    @State private var rectificationIntent: HazardRectificationIntent = .immediate
    @State private var rectificationScheduledDue: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var scheduleAddToCalendar = false
    @State private var showImmediateRectificationSheet = false
    @State private var showScheduledRectificationSheet = false
    @State private var immediateRectNote: String = ""
    @State private var immediateRectPhotoData: Data?
    @State private var immediateRectPickerItem: PhotosPickerItem?
#if os(iOS)
    @State private var showImmediateRectificationCamera = false
#endif

#if os(iOS) || os(visionOS) || os(macOS)
    @StateObject private var voiceTranscriber = HazardVoiceTranscriber()
#endif

    private enum InspectionFormField: Hashable {
        case supplementary
        case location
    }

    private enum HazardForm {
        static let maxSitePhotos = 2
    }

    var body: some View {
        mainPanel
            .navigationTitle("隐患识别")
            .inlineNavigationTitleMode()
            .toolbar {
                if isAnalyzing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            analysisTask?.cancel()
                        }
                    }
                }
            }
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

    /// 可解码预览的 `(hazardSitePhotos 下标, Image)`，用于并列缩略图与删除（下标与 `hazardSitePhotos` 一致）。
    private var hazardSitePhotoPairs: [(offset: Int, image: Image)] {
        hazardSitePhotos.enumerated().compactMap { index, data in
            guard let img = Image.fromStoredData(data) else { return nil }
            return (offset: index, image: img)
        }
    }

    private var rectificationIntentFooter: String {
        guard hasHazardDescription else {
            return "请先填写上方的「隐患描述」，再编辑地点并选择立即或限期整改。"
        }
        switch rectificationIntent {
        case .immediate:
            return "保存后自动建立第 1 轮整改。可点「填写立即整改现场…」补充整改侧照片与说明（与上方隐患照片可不同），也可稍后在记录详情补全。"
        case .scheduled:
            return "请点「选择完成日期与日程…」在日历中选计划完成日，并可选择是否写入系统日历。保存后建立第 1 轮限期整改。"
        }
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            Form {
                if !deepSeekConfigured {
                    Section {
                        Text("当前为本地演示分析：未在「我的」填写 API 地址并完成 Apple 登录同步时，不会请求你的服务端做云端分析。有照片时会先用本机 Vision 提取摘要；同步后将由服务器代调模型并扣次。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack(spacing: 12) {
#if os(iOS)
                        Button {
                            presentCameraIfPossible()
                        } label: {
                            photoSourceColumn(
                                title: "拍照",
                                systemImage: "camera.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(sitePhotosAtCapacity || isAnalyzing)
#else
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.title2)
                            Text("拍照")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.secondary)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
#endif

                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            photoSourceColumn(
                                title: "从相册选择照片",
                                systemImage: "photo.on.rectangle.angled"
                            )
                        }
                        .buttonStyle(.bordered)
                        .disabled(sitePhotosAtCapacity || isAnalyzing)
                    }
                    .listRowInsets(EdgeInsets(
                        top: 10,
                        leading: 16,
                        bottom: hasHazardPhotoForPreview ? 4 : 10,
                        trailing: 16
                    ))
                    .listRowSeparator(.hidden, edges: .bottom)

                    if !hazardSitePhotoPairs.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(hazardSitePhotoPairs, id: \.offset) { pair in
                                hazardSitePhotoCell(image: pair.image, index: pair.offset)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 8, trailing: 12))
                        .listRowSeparator(.hidden, edges: .top)
                    }
                } footer: {
                    Text("同一隐患最多添加 \(HazardForm.maxSitePhotos) 张现场照片（可选）。有照片时会先经本机 Vision 提取摘要再参与分析。")
                        .font(.caption)
                }

                Section {
                    HStack(alignment: .top, spacing: 10) {
                        TextField("文字输入（必填）", text: $supplementaryText, axis: .vertical)
                            .lineLimit(3...6)
                            .focused($focusedField, equals: .supplementary)

#if os(iOS) || os(visionOS) || os(macOS)
                        Button {
                            Task { await voiceTranscriber.toggle(onto: $supplementaryText) }
                        } label: {
                            Image(systemName: voiceTranscriber.isRecording ? "stop.circle.fill" : "mic.fill")
                                .font(.title2)
                                .foregroundStyle(voiceTranscriber.isRecording ? Color.red : Color.accentColor)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(voiceTranscriber.isRecording ? "停止语音输入" : "语音输入")
                        .disabled(isAnalyzing)
#endif
                    }
                } header: {
                    Text("隐患描述")
                } footer: {
#if os(iOS) || os(visionOS) || os(macOS)
                    if let err = voiceTranscriber.lastError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
#endif
                }

                Section {
                    TextField("输入地点…", text: $location)
                        .focused($focusedField, equals: .location)
                        .disabled(!hasHazardDescription)
                } header: {
                    Text("输入地点")
                } footer: {
                    Text("填写隐患描述后即可编辑地点。")
                        .font(.caption)
                }

                Section {
                    Picker("整改安排", selection: $rectificationIntent) {
                        Text(HazardRectificationIntent.immediate.shortLabel).tag(HazardRectificationIntent.immediate)
                        Text(HazardRectificationIntent.scheduled.shortLabel).tag(HazardRectificationIntent.scheduled)
                    }
                    .pickerStyle(.segmented)

                    if rectificationIntent == .immediate {
                        Button("填写立即整改现场…") {
                            showImmediateRectificationSheet = true
                        }
                    } else {
                        Button("选择完成日期与日程…") {
                            showScheduledRectificationSheet = true
                        }
                    }
                } header: {
                    Text("整改安排")
                } footer: {
                    Text(rectificationIntentFooter)
                        .font(.footnote)
                }
                .disabled(!hasHazardDescription)

                Section {
                    Button {
                        analysisTask = Task { await runAnalysis() }
                    } label: {
                        if isAnalyzing {
                            HStack {
                                Spacer()
                                ProgressView("分析中…")
                                Spacer()
                            }
                        } else {
                            Text("开始排查")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isAnalyzing || !hasMinimumInput)

                    Button {
                        openOfflineManualRecord()
                    } label: {
                        Label("无网先记录", systemImage: "wifi.slash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isAnalyzing || !hasMinimumInput)
                } footer: {
                    Text("须先填写「隐患描述」（可无照片）。隧道、基坑等弱网环境若无法完成云端分析，可用「无网先记录」保存本条，有网络后再用「开始排查」补全措施与法规依据。分析卡住时可点左上角「取消」。")
                        .font(.footnote)
                }

                if let analysisError {
                    Section {
                        Text(analysisError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
#if os(iOS)
            .scrollDismissesKeyboard(.interactively)
#endif

            if focusedField == nil {
                Divider()

                Button {
                    path.append(.hazardRecords)
                } label: {
                    Text("排查记录")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .background(.ultraThinMaterial)
            }
        }
        .onChange(of: rectificationIntent) { _, new in
            guard hasHazardDescription else { return }
            if new == .immediate {
                scheduleAddToCalendar = false
                showImmediateRectificationSheet = true
            } else {
                showScheduledRectificationSheet = true
            }
        }
        .onChange(of: immediateRectPickerItem) { _, new in
            guard let new else { return }
            Task {
                if let data = try? await new.loadTransferable(type: Data.self) {
                    immediateRectPhotoData = data
                }
            }
        }
        .sheet(isPresented: $showImmediateRectificationSheet) {
            Group {
#if os(iOS)
                HazardImmediateRectificationSheet(
                    note: $immediateRectNote,
                    photoData: $immediateRectPhotoData,
                    pickerItem: $immediateRectPickerItem,
                    requestCamera: { presentImmediateRectificationCameraIfPossible() }
                )
#else
                HazardImmediateRectificationSheet(
                    note: $immediateRectNote,
                    photoData: $immediateRectPhotoData,
                    pickerItem: $immediateRectPickerItem,
                    requestCamera: {}
                )
#endif
            }
        }
        .sheet(isPresented: $showScheduledRectificationSheet) {
            HazardScheduledRectificationSheet(
                dueDate: $rectificationScheduledDue,
                addToCalendar: $scheduleAddToCalendar
            )
        }
#if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
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
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker(imageData: $cameraCaptureBuffer)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showImmediateRectificationCamera) {
            CameraImagePicker(imageData: $immediateRectPhotoData)
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
#endif
        .alert("已达照片上限", isPresented: $photoLimitNotice) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("同一隐患最多保存 \(HazardForm.maxSitePhotos) 张现场照片，请先删除一张后再添加。")
        }
        .onChange(of: pickerItem) { _, new in
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
        .onDisappear {
#if os(iOS) || os(visionOS) || os(macOS)
            voiceTranscriber.stopSessionIfNeeded()
#endif
        }
        .onAppear {
            refreshDeepSeekConfiguredFlag()
        }
        .onReceive(NotificationCenter.default.publisher(for: .safemasterAccessTokenDidChange)) { _ in
            refreshDeepSeekConfiguredFlag()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appleUserSessionDidChange)) { _ in
            refreshDeepSeekConfiguredFlag()
        }
    }

    private func appendSitePhotoIfAllowed(_ data: Data) {
        guard !data.isEmpty else { return }
        guard hazardSitePhotos.count < HazardForm.maxSitePhotos else {
            photoLimitNotice = true
            return
        }
        hazardSitePhotos.append(data)
    }

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
    private func presentImmediateRectificationCameraIfPossible() {
#if targetEnvironment(simulator)
        cameraUnavailableNotice = true
#else
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraUnavailableNotice = true
            return
        }
        showImmediateRectificationCamera = true
#endif
    }
#endif

#if os(iOS)
    private func presentCameraIfPossible() {
#if targetEnvironment(simulator)
        cameraUnavailableNotice = true
#else
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraUnavailableNotice = true
            return
        }
        showCamera = true
#endif
    }
#endif

    @MainActor
    private func runAnalysis() async {
#if os(iOS) || os(visionOS) || os(macOS)
        voiceTranscriber.stopSessionIfNeeded()
#endif
        analysisError = nil
        isAnalyzing = true
        defer {
            isAnalyzing = false
            analysisTask = nil
        }
        do {
            try Task.checkCancellation()
            let service = HazardAnalysisServiceFactory.makeDefault()
            let result = try await service.analyze(
                photoData: hazardSitePhotos.first,
                secondaryPhotoData: hazardSitePhotos.count > 1 ? hazardSitePhotos[1] : nil,
                supplementaryText: supplementaryText,
                location: location
            )
            try Task.checkCancellation()
            let payload = makeResultPayload(analysis: result)
            path.append(.hazardResult(id: UUID(), payload: payload))
        } catch is CancellationError {
            // 用户点「取消」
        } catch {
            analysisError = error.localizedDescription
        }
    }

    /// 不请求网络：用当前表单生成占位分析并导航到排查结果，便于连续记录多处隐患。
    @MainActor
    private func openOfflineManualRecord() {
#if os(iOS) || os(visionOS) || os(macOS)
        voiceTranscriber.stopSessionIfNeeded()
#endif
        analysisError = nil
        let hasPhoto = !hazardSitePhotos.filter { !$0.isEmpty }.isEmpty
        let analysis = HazardAnalysisResult.offlineManualRecord(
            supplementaryText: supplementaryText,
            location: location,
            hasPhoto: hasPhoto
        )
        let payload = makeResultPayload(analysis: analysis)
        path.append(.hazardResult(id: UUID(), payload: payload))
    }

    private func makeResultPayload(analysis: HazardAnalysisResult) -> HazardResultPayload {
        let dueDay = Calendar.current.startOfDay(for: rectificationScheduledDue)
        return HazardResultPayload(
            photoData: hazardSitePhotos.first,
            secondaryPhotoData: hazardSitePhotos.count > 1 ? hazardSitePhotos[1] : nil,
            location: location,
            supplementaryText: supplementaryText,
            analysis: analysis,
            rectificationIntent: rectificationIntent,
            rectificationPlannedDueAt: rectificationIntent == .scheduled ? dueDay : nil,
            prefillRectificationActionNote: immediateRectNote,
            prefillRectificationPhotoData: immediateRectPhotoData,
            addDeadlineToDeviceCalendar: rectificationIntent == .scheduled && scheduleAddToCalendar
        )
    }
}

// MARK: - 整改安排 Sheet（隐患识别）

private struct HazardImmediateRectificationSheet: View {
    @Binding var note: String
    @Binding var photoData: Data?
    @Binding var pickerItem: PhotosPickerItem?
    var requestCamera: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
#if os(iOS)
                    Button {
                        requestCamera()
                    } label: {
                        Label("拍照", systemImage: "camera.fill")
                    }
#endif
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("从相册选择", systemImage: "photo.on.rectangle.angled")
                    }
                    if let img = Image.fromStoredData(photoData) {
                        img
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } header: {
                    Text("整改侧照片")
                } footer: {
                    Text("可与上方「隐患照片」不同，用于记录已采取的现场措施。")
                        .font(.caption)
                }

                Section("整改说明") {
                    TextField("已采取的措施或现场情况（可选）", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
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
#if os(iOS) || os(visionOS)
        .presentationDetents([.medium, .large])
#endif
    }
}

private struct HazardScheduledRectificationSheet: View {
    @Binding var dueDate: Date
    @Binding var addToCalendar: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "计划完成日",
                        selection: $dueDate,
                        displayedComponents: [.date]
                    )
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                } footer: {
                    Text("保存隐患记录后，将按此日期建立限期整改轮次。")
                        .font(.caption)
                }

                Section {
                    Toggle("加入系统日历提醒", isOn: $addToCalendar)
                } footer: {
                    Text("开启后，在排查结果页点「记录」成功时会请求日历权限并写入一条「全天」事件作为截止提醒。")
                        .font(.caption)
                }
            }
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

#Preview {
    BuildingSafetyHubView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
