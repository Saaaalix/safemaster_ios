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

    @State private var showScheduledPicker = false
    @State private var scheduledDueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var actionError: String?
    @State private var rejectingRound: RectificationRound?
    @State private var rejectNoteDraft = ""

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("整改闭环")
                        .font(.headline)
                    Spacer(minLength: 8)
                    Text(finding.rectificationClosureSummary.badgeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                Text("此处记录「实际整改」与「验收」。若在「隐患识别」已选立即/限期并保存，下方可能已有第 1 轮。上方「整改措施」仍为排查时的 AI 建议，二者可对照使用。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

            if finding.rectificationRoundsArray.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("尚未建立整改记录")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
                        .disabled(disabled)

                        Button("限期整改") {
                            scheduledDueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
                            showScheduledPicker = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(disabled)
                    }
                }
            }

            ForEach(finding.rectificationRoundsArray, id: \.objectID) { round in
                RectificationRoundCard(
                    round: round,
                    disabled: disabled,
                    onSubmitVerify: { submitVerify(round) },
                    onPass: { pass(round) },
                    onReject: {
                        rejectingRound = round
                        rejectNoteDraft = ""
                    }
                )
            }

            if case .failedPendingNewRound = finding.rectificationClosureSummary {
                Button("开始下一轮整改") {
                    _ = finding.startNextRectificationRoundAfterFailure(context: viewContext)
                    persistOrRollback()
                }
                .buttonStyle(.borderedProminent)
                .disabled(disabled)
            }
        }
        .sheet(isPresented: $showScheduledPicker) {
            NavigationStack {
                Form {
                    DatePicker(
                        "计划完成日期",
                        selection: $scheduledDueDate,
                        displayedComponents: [.date]
                    )
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                }
                .navigationTitle("限期整改")
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
                Form {
                    Section {
                        TextField("不符合项与需再次整改的要点", text: $rejectNoteDraft, axis: .vertical)
                            .lineLimit(4...12)
                    } footer: {
                        Text("提交后将标记本轮为「不通过」，可再开下一轮整改。")
                            .font(.caption)
                    }
                }
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
        .alert("提示", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("好的", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private func submitVerify(_ round: RectificationRound) {
        do {
            try round.submitForVerification()
            persistOrRollback()
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

// MARK: - 单轮卡片

private struct RectificationRoundCard: View {
    @ObservedObject var round: RectificationRound
    @Environment(\.managedObjectContext) private var viewContext

    var disabled: Bool
    let onSubmitVerify: () -> Void
    let onPass: () -> Void
    let onReject: () -> Void

    @State private var evidencePickerItem: PhotosPickerItem?

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

                LabeledContent("方式") {
                    Text(round.modeEnum == .immediate ? "立即整改" : "限期整改")
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
                    } else if let due = round.plannedDueAt {
                        LabeledContent("计划完成日") {
                            Text(shortDate(due))
                        }
                        .font(.caption)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("责任人 / 班组")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if fieldsEditable {
                        TextField("选填", text: Binding(
                            get: { round.responsibleParty ?? "" },
                            set: { round.responsibleParty = $0.isEmpty ? nil : $0; saveQuietly() }
                        ))
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                    } else {
                        Text((round.responsibleParty ?? "").isEmpty ? "—" : (round.responsibleParty ?? ""))
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("实际整改说明")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if fieldsEditable {
                        TextField("填写已采取的措施", text: Binding(
                            get: { round.actionTaken ?? "" },
                            set: { round.actionTaken = $0.isEmpty ? nil : $0; saveQuietly() }
                        ), axis: .vertical)
                        .lineLimit(3...8)
                    } else {
                        Text((round.actionTaken ?? "").isEmpty ? "—" : (round.actionTaken ?? ""))
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
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
                                        round.evidencePhotoData = data
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
                    .disabled(disabled)
                } else if round.statusEnum == .pendingVerification {
                    HStack(spacing: 10) {
                        Button("验收通过") {
                            onPass()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(disabled)

                        Button("验收不通过", role: .destructive) {
                            onReject()
                        }
                        .buttonStyle(.bordered)
                        .disabled(disabled)
                    }
                }
            }
            .padding(.vertical, 4)
        }
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
        f.dateStyle = .medium
        f.timeStyle = .none
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
