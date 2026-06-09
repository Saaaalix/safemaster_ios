//
//  RectificationTimelineSection.swift
//  安全大师
//

import CoreData
import PhotosUI
import SwiftUI

struct RectificationTimelineSection: View {
    @ObservedObject var finding: InspectionFinding
    @Environment(\.managedObjectContext) private var viewContext

    var disabled: Bool = false

    private static let productivityAccent = Color(red: 0.95, green: 0.65, blue: 0.3)

    @State private var showScheduledPicker = false
    @State private var scheduledDueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var actionError: String?
    @State private var rejectingRound: RectificationRound?
    @State private var rejectNoteDraft = ""
    @State private var pendingSubmitRound: RectificationRound?
    @State private var pendingPassRound: RectificationRound?
    @State private var showNextRoundConfirmation = false

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("整改闭环")
                        .font(.headline)
                    Spacer(minLength: 8)
                    Text(finding.rectificationClosureSummary.badgeText)
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                        .multilineTextAlignment(.trailing)
                }
                Text("此处记录「实际整改」与「验收」。若在「隐患识别」已选立即/稍后安排并保存，下方可能已有第 1 轮。上方「整改措施」仍为排查时的 AI 建议，二者可对照使用。")
                    .font(.caption2)
                    .foregroundStyle(Color(.secondaryLabel))
            }

            if finding.rectificationRoundsArray.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("尚未建立整改记录")
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                    HStack(spacing: 10) {
                        Button("立即整改") {
                            _ = finding.startFirstRectificationRound(
                                mode: .immediate,
                                plannedDueAt: nil,
                                context: viewContext
                            )
                            persistOrRollback()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Self.productivityAccent)
                        .disabled(disabled)

                        Button("稍后安排") {
                            scheduledDueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
                            showScheduledPicker = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(disabled)
                    }
                }
                .padding(14)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            let rounds = finding.rectificationRoundsArray
            let latestRoundID = rounds.last?.objectID
            ForEach(rounds, id: \.objectID) { round in
                if round.objectID == latestRoundID {
                    rectificationRoundCard(round)
                } else {
                    DisclosureGroup {
                        rectificationRoundCard(round)
                            .padding(.top, 8)
                    } label: {
                        HStack {
                            Label(
                                "第 \(round.roundIndex) 轮历史记录",
                                systemImage: round.statusEnum == .passed ? "checkmark.circle" : "clock.arrow.circlepath"
                            )
                            Spacer()
                            Text(statusLabel(round.statusEnum))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(statusTint(round.statusEnum))
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            if case .failedPendingNewRound = finding.rectificationClosureSummary {
                Button("开始下一轮整改") {
                    showNextRoundConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(Self.productivityAccent)
                .disabled(disabled)
            }
        }
        .sheet(isPresented: $showScheduledPicker) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        sheetCard(title: "计划完成日（可选）", systemImage: "calendar.badge.clock") {
                            DatePicker(
                                "计划完成日期",
                                selection: $scheduledDueDate,
                                displayedComponents: [.date]
                            )
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                            RectificationDueDateShortcutButtons { date in
                                scheduledDueDate = date
                            }
                        }
                    }
                    .padding(16)
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("稍后安排")
#if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showScheduledPicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("创建") {
                            _ = finding.startFirstRectificationRound(
                                mode: .scheduled,
                                plannedDueAt: scheduledDueDate,
                                context: viewContext
                            )
                            persistOrRollback()
                            showScheduledPicker = false
                        }
                    }
                }
            }
#if os(iOS) || os(visionOS)
            .presentationDetents([.medium])
#endif
        }
        .sheet(item: $rejectingRound) { round in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        sheetCard(title: "不通过说明", systemImage: "xmark.seal") {
                            VStack(alignment: .leading, spacing: 10) {
                        TextField("不符合项与需再次整改的要点", text: $rejectNoteDraft, axis: .vertical)
                            .lineLimit(4...12)
                                    .padding(12)
                                    .background(Color(.tertiarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Text("提交后将标记本轮为「不通过」，可再开下一轮整改。")
                            .font(.caption)
                                    .foregroundStyle(Color(.secondaryLabel))
                            }
                        }
                    }
                    .padding(16)
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("验收不通过")
#if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { rejectingRound = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("提交") {
                            do {
                                try round.markVerificationFailed(note: rejectNoteDraft)
                                persistOrRollback()
                                rejectingRound = nil
                            } catch {
                                actionError = error.localizedDescription
                            }
                        }
                    }
                }
            }
#if os(iOS) || os(visionOS)
            .presentationDetents([.medium, .large])
#endif
        }
        .confirmationDialog(
            "确认提交待验收",
            isPresented: Binding(
                get: { pendingSubmitRound != nil },
                set: { if !$0 { pendingSubmitRound = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("确认提交") {
                if let round = pendingSubmitRound {
                    submitVerify(round)
                }
                pendingSubmitRound = nil
            }
            Button("取消", role: .cancel) {
                pendingSubmitRound = nil
            }
        } message: {
            Text("提交后将进入待验收状态，整改内容与整改后照片将作为当前轮次的验收依据。")
        }
        .confirmationDialog(
            "确认验收通过",
            isPresented: Binding(
                get: { pendingPassRound != nil },
                set: { if !$0 { pendingPassRound = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("确认通过") {
                if let round = pendingPassRound {
                    pass(round)
                }
                pendingPassRound = nil
            }
            Button("取消", role: .cancel) {
                pendingPassRound = nil
            }
        } message: {
            Text("通过后该轮将闭环完成。")
        }
        .confirmationDialog(
            "确认开始下一轮整改",
            isPresented: $showNextRoundConfirmation,
            titleVisibility: .visible
        ) {
            Button("确认开始") {
                _ = finding.startNextRectificationRoundAfterFailure(context: viewContext)
                persistOrRollback()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将基于上一轮信息创建新轮次，并进入整改中状态。")
        }
        .alert("提示", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("好的", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private func sheetCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
        .padding(.vertical, 8)
    }

    private func rectificationRoundCard(_ round: RectificationRound) -> some View {
        RectificationRoundCard(
            finding: finding,
            round: round,
            disabled: disabled,
            onSubmitVerify: { pendingSubmitRound = round },
            onPass: { pendingPassRound = round },
            onReject: {
                rejectingRound = round
                rejectNoteDraft = ""
            }
        )
    }

    private func statusLabel(_ s: RectificationStatus) -> String {
        switch s {
        case .inProgress: return "整改中"
        case .pendingVerification: return "待验收"
        case .passed: return "已通过"
        case .failed: return "未通过"
        }
    }

    private func statusTint(_ s: RectificationStatus) -> Color {
        switch s {
        case .inProgress: return .blue
        case .pendingVerification: return Self.productivityAccent
        case .passed: return .green
        case .failed: return .red
        }
    }

    private func submitVerify(_ round: RectificationRound) {
        do {
            try round.submitForVerification()
            persistOrRollback()
            if let party = round.responsibleParty?.trimmingCharacters(in: .whitespacesAndNewlines), !party.isEmpty {
                RecentFieldValuesStore.record(party, for: .rectificationResponsible)
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func pass(_ round: RectificationRound) {
        do {
            try round.markVerificationPassed(note: nil)
            persistOrRollback()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func persistOrRollback() {
        do {
            try viewContext.save()
            actionError = nil
        } catch {
            viewContext.rollback()
            actionError = "保存失败：\(error.localizedDescription)"
        }
    }
}

private struct RectificationDueDateShortcutButtons: View {
    let onPick: (Date) -> Void

    var body: some View {
        let calendar = Calendar.current
        HStack(spacing: 8) {
            Button("今天") {
                onPick(calendar.startOfDay(for: Date()))
            }
            Button("3天") {
                onPick(calendar.date(byAdding: .day, value: 3, to: Date()) ?? Date())
            }
            Button("7天") {
                onPick(calendar.date(byAdding: .day, value: 7, to: Date()) ?? Date())
            }
            Text("自定义请点日期")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
    }
}

// MARK: - 单轮卡片

private struct RectificationRoundCard: View {
    @ObservedObject var finding: InspectionFinding
    @ObservedObject var round: RectificationRound
    @Environment(\.managedObjectContext) private var viewContext

    private static let productivityAccent = Color(red: 0.95, green: 0.65, blue: 0.3)

    var disabled: Bool
    let onSubmitVerify: () -> Void
    let onPass: () -> Void
    let onReject: () -> Void

    @StateObject private var voiceTranscriber = HazardVoiceTranscriber()
    @State private var evidencePickerItem: PhotosPickerItem?
    @State private var optimizedActionCandidate: String?
    @FocusState private var responsibleFieldFocused: Bool

    private var actionTakenTrimmed: String {
        (round.actionTaken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var replyDraftText: String {
        finding.effectiveRectificationReplyDraft()
    }

    private var hasEvidencePhoto: Bool {
        guard let d = round.evidencePhotoData, !d.isEmpty else { return false }
        return true
    }

    private var hasActionDescription: Bool {
        !actionTakenTrimmed.isEmpty
    }

    private var actionTakenBinding: Binding<String> {
        Binding(
            get: { round.actionTaken ?? "" },
            set: {
                round.actionTaken = $0.isEmpty ? nil : $0
                optimizedActionCandidate = nil
                saveQuietly()
            }
        )
    }

    private var responsiblePartyBinding: Binding<String> {
        Binding(
            get: { round.responsibleParty ?? "" },
            set: { round.responsibleParty = $0.isEmpty ? nil : $0; saveQuietly() }
        )
    }

    private var fieldsEditable: Bool {
        !disabled && round.statusEnum == .inProgress
    }

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("第 \(round.roundIndex) 轮")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(statusLabel(round.statusEnum))
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusTint(round.statusEnum).opacity(0.15))
                        .foregroundStyle(statusTint(round.statusEnum))
                        .clipShape(Capsule())
                }

                roundReadinessSummary

                LabeledContent("方式") {
                    Text(round.modeEnum == .immediate ? "立即整改" : "稍后安排")
                }
                .font(.caption)

                if round.modeEnum == .scheduled {
                    if fieldsEditable {
                        DatePicker(
                            "计划完成日",
                            selection: Binding(
                                get: { round.plannedDueAt ?? Date() },
                                set: { round.plannedDueAt = $0; saveQuietly() }
                            ),
                            displayedComponents: [.date]
                        )
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                        .font(.caption)
                        RectificationDueDateShortcutButtons { date in
                            round.plannedDueAt = date
                            saveQuietly()
                        }
                        if let deadline = deadlineHint {
                            Text(deadline.text)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(deadline.tint)
                        }
                    } else {
                        LabeledContent("计划完成日") {
                            Text(round.plannedDueAt.map(shortDate) ?? "待确认")
                        }
                        .font(.caption)
                        if let deadline = deadlineHint {
                            Text(deadline.text)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(deadline.tint)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("整改责任人 / 班组")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if fieldsEditable {
                        TextField("填写整改责任人或班组（选填）", text: responsiblePartyBinding)
                            .focused($responsibleFieldFocused)
#if os(iOS)
                            .textInputAutocapitalization(.never)
#endif
                            .padding(10)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .onChange(of: responsibleFieldFocused) { _, focused in
                                if !focused {
                                    RecentFieldValuesStore.record(
                                        round.responsibleParty ?? "",
                                        for: .rectificationResponsible
                                    )
                                }
                            }
                        RecentValueChipsView(
                            kind: .rectificationResponsible,
                            text: responsiblePartyBinding
                        )
                    } else {
                        Text((round.responsibleParty ?? "").isEmpty ? "—" : (round.responsibleParty ?? ""))
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("整改后照片")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if fieldsEditable {
                        PhotosPicker(selection: $evidencePickerItem, matching: .images) {
                            Label("选择照片", systemImage: "photo.on.rectangle.angled")
                        }
                        .disabled(disabled)
                        .onChange(of: evidencePickerItem) { _, new in
                            guard let new else { return }
                            Task {
                                if let data = try? await new.loadTransferable(type: Data.self) {
                                    await MainActor.run {
                                        let stamp = EvidencePhotoStampContext(
                                            projectName: finding.location,
                                            shooterName: EvidenceWatermarkIdentity.resolvedShooterName(
                                                preferred: round.responsibleParty ?? finding.recordInspectorNameSnapshot
                                            ),
                                            sceneName: "整改后照片",
                                            sourceName: "安全大师",
                                            capturedAt: Date(),
                                            coordinate: EvidenceLocationProvider.shared.snapshotCoordinate()
                                        )
                                        let stamped = Data.watermarkedPhotoStorageData(from: data, context: stamp) ?? (Data.optimizedPhotoStorageData(from: data) ?? data)
                                        round.evidencePhotoData = stamped
                                        SitePhotoLibrarySaver.saveToPhotoLibraryIfPermitted(stamped, source: "整改证据照片")
                                        saveQuietly()
                                    }
                                }
                            }
                        }
                    }
                    if let img = Image.fromStoredData(round.evidencePhotoData) {
                        img
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else if fieldsEditable {
                        Text("上传整改后照片后可生成整改说明。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if !fieldsEditable && !replyDraftText.isEmpty && actionTakenTrimmed.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AI 预生成回复草稿（参考）")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(replyDraftText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("实际整改说明")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if fieldsEditable {
                        HStack(alignment: .top, spacing: 4) {
                            TextField("填写已采取的措施", text: actionTakenBinding, axis: .vertical)
                                .lineLimit(3...8)
#if os(iOS) || os(visionOS) || os(macOS)
                            actionTakenVoiceButton
#endif
                        }
                        if let requirementReference = rectificationRequirementReference {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("整改措施参考")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(requirementReference)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Button {
                            polishCurrentActionTaken()
                        } label: {
                            Label("智能优化", systemImage: "wand.and.stars")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .disabled(disabled || actionTakenTrimmed.isEmpty)
                        if actionTakenTrimmed.isEmpty {
                            Text("请先填写实际整改说明，再点击「智能优化」。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("标准：润色你的输入，并按整改措施补充 1 条关键动作。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let optimizedActionCandidate,
                           !optimizedActionCandidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("智能优化结果（待确认）")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Self.productivityAccent)
                                Text(optimizedActionCandidate)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 10) {
                                    Button("采用优化内容") {
                                        round.actionTaken = optimizedActionCandidate
                                        self.optimizedActionCandidate = nil
                                        saveQuietly()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Self.productivityAccent)
                                    .disabled(disabled)

                                    Button("保留原输入") {
                                        self.optimizedActionCandidate = nil
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(disabled)
                                }
                            }
                        }
#if os(iOS) || os(visionOS) || os(macOS)
                        if voiceTranscriber.isActive(fieldID: round.objectID) {
                            RecordingWaveformView(tint: Self.productivityAccent)
                                .padding(.top, 2)
                                .transition(.opacity.combined(with: .scale))
                        }
#endif
                    } else {
                        Text((round.actionTaken ?? "").isEmpty ? "—" : (round.actionTaken ?? ""))
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }

                if let vAt = round.verifiedAt {
                    LabeledContent("验收时间") {
                        Text(dateTimeText(vAt))
                    }
                    .font(.caption)
                }
                if let note = round.verifierNote, !note.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("验收说明")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(note)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }

                if round.statusEnum == .inProgress {
                    Button("提交待验收") {
                        onSubmitVerify()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Self.productivityAccent)
                    .disabled(disabled || !hasActionDescription || !hasEvidencePhoto)
                } else if round.statusEnum == .pendingVerification {
                    HStack(spacing: 10) {
                        Button("验收通过") {
                            onPass()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Self.productivityAccent)
                        .disabled(disabled)

                        Button("验收不通过", role: .destructive) {
                            onReject()
                        }
                        .buttonStyle(.bordered)
                        .disabled(disabled)
                    }
                }
            }
            .padding(16)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
        }
        .onDisappear {
            voiceTranscriber.stopSessionIfNeeded()
        }
        .onAppear {
            EvidenceLocationProvider.shared.start()
        }
    }

    private var roundReadinessSummary: some View {
        let state = roundReadinessState
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: state.icon)
                .foregroundStyle(state.tint)
                .frame(width: 24, height: 24)
                .background(state.tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(state.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state.tint)
                Text(state.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(state.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var roundReadinessState: (title: String, message: String, icon: String, tint: Color) {
        switch round.statusEnum {
        case .inProgress:
            if hasActionDescription && hasEvidencePhoto {
                return (
                    "已记录整改内容",
                    "整改说明和整改后照片已带入，可核对后提交待验收。",
                    "checkmark.seal.fill",
                    .green
                )
            }
            if hasActionDescription {
                return (
                    "已填写整改说明",
                    "建议补充整改后照片，作为整改回复单和闭环验收的佐证。",
                    "text.badge.checkmark",
                    Self.productivityAccent
                )
            }
            if hasEvidencePhoto {
                return (
                    "已添加整改后照片",
                    "还需要补充实际整改说明，之后即可提交待验收。",
                    "photo.badge.checkmark",
                    Self.productivityAccent
                )
            }
            return (
                "待补整改内容",
                "请填写实际整改说明，并尽量上传整改后照片。",
                "square.and.pencil",
                .orange
            )
        case .pendingVerification:
            return (
                "等待验收",
                "请根据复查结果选择验收通过或不通过。",
                "person.crop.circle.badge.clock",
                .blue
            )
        case .passed:
            return (
                "本轮已通过",
                "整改闭环已完成，可用于生成整改回复单。",
                "checkmark.circle.fill",
                .green
            )
        case .failed:
            return (
                "本轮未通过",
                "请查看验收说明并开始下一轮整改。",
                "xmark.seal.fill",
                .red
            )
        }
    }

    private var rectificationRequirementReference: String? {
        let text = (finding.rectificationMeasures ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("待联网后") || text.contains("（待联网后") { return nil }
        return text
    }

    private var deadlineHint: (text: String, tint: Color)? {
        guard round.modeEnum == .scheduled, let due = round.plannedDueAt else { return nil }
        let cal = Calendar.current
        let dueDay = cal.startOfDay(for: due)
        let today = cal.startOfDay(for: Date())
        guard let days = cal.dateComponents([.day], from: today, to: dueDay).day else { return nil }

        if days < 0 {
            if round.statusEnum == .passed {
                return ("已完成（较计划晚 \(abs(days)) 天）", Color(.secondaryLabel))
            }
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

#if os(iOS) || os(visionOS) || os(macOS)
    private var actionTakenVoiceButton: some View {
        VoiceInputIconButton(
            isRecordingForThisField: voiceTranscriber.isActive(fieldID: round.objectID),
            isDisabled: disabled,
            accessibilityLabel: "语音输入整改说明"
        ) {
            Task {
                await voiceTranscriber.toggle(fieldID: round.objectID, onto: actionTakenBinding)
            }
        }
    }
#endif

    private func polishCurrentActionTaken() {
        guard !actionTakenTrimmed.isEmpty else { return }
        let polished = InspectionFinding.polishedActionTaken(
            from: actionTakenTrimmed,
            fallbackDraft: replyDraftText,
            location: finding.location,
            riskLevel: finding.riskLevel,
            rectificationRequirement: finding.rectificationMeasures,
            includeContextPrefix: false,
            requirementMaxItems: 1
        )
        optimizedActionCandidate = polished
    }

    private func saveQuietly() {
        guard !round.isDeleted, !round.isFault else { return }
        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
        }
    }

    private func statusLabel(_ s: RectificationStatus) -> String {
        switch s {
        case .inProgress: return "整改中"
        case .pendingVerification: return "待验收"
        case .passed: return "已通过"
        case .failed: return "未通过"
        }
    }

    private func statusTint(_ s: RectificationStatus) -> Color {
        switch s {
        case .inProgress: return .blue
        case .pendingVerification: return .orange
        case .passed: return .green
        case .failed: return .red
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private func shortDate(_ d: Date) -> String {
        Self.dayFormatter.string(from: d)
    }

    private func dateTimeText(_ d: Date) -> String {
        Self.dateTimeFormatter.string(from: d)
    }
}
