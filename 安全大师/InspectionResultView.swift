//
//  InspectionResultView.swift
//  安全大师
//

import SwiftUI

struct InspectionResultView: View {
    @Environment(\.managedObjectContext) private var viewContext

    let payload: HazardResultPayload
    var onDone: () -> Void

    /// 防止连点「记录」写入多条相同 Core Data（导航未及时返回时用户会多次点击）。
    @State private var didSaveToCoreData = false
    @State private var isSavingToCoreData = false
    @State private var saveToCoreDataError: String?
    @State private var didInitializeDrafts = false
    @State private var projectNameDraft = ""
    @State private var inspectorNameDraft = ""
    @State private var locationDraft = ""
    @State private var inspectionSituationDraft = ""
    @State private var issueDraft = ""
    @State private var requirementDraft = ""
    @State private var legalBasisDraft = ""
    @State private var replyDraft = ""
    @State private var riskLevelDraft = HazardRiskLevel.canonicalOptions.first ?? "一般风险"

    private static let productivityAccent = Color(red: 0.95, green: 0.65, blue: 0.3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                resultPhotoGallery

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("正式内容确认")
                            .font(.title3.weight(.bold))
                        Text("请先核对并修订下方字段；保存后导出报告只使用这些正式内容。")
                            .font(.caption)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    Spacer()
                    riskBadge(riskLevelDraft)
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
                .padding(.vertical, 8)

                dashboardCard(title: "现场事实", systemImage: "doc.text.magnifyingglass") {
                    VStack(alignment: .leading, spacing: 12) {
                        editableField("项目名称", text: $projectNameDraft, placeholder: "项目名称")
                        editableField("检查人", text: $inspectorNameDraft, placeholder: "检查人")
                        editableField("部位/地点", text: $locationDraft, placeholder: "例如：1号宿舍内")
                        LabeledContent("地点分类") {
                            Text(payload.sceneType.rawValue)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }

                dashboardCard(title: "一句话核心风险", systemImage: "bolt.trianglebadge.exclamationmark.fill") {
                    Text(coreRiskSummary)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                dashboardCard(title: "正式报告字段", systemImage: "checklist.checked") {
                    VStack(alignment: .leading, spacing: 12) {
                        editableField("检查情况", text: $inspectionSituationDraft, placeholder: "现场检查情况", lineLimit: 2...5)
                        editableField("存在问题", text: $issueDraft, placeholder: "存在问题", lineLimit: 3...8)
                        editableField("整改要求", text: $requirementDraft, placeholder: "整改要求", lineLimit: 3...8)
                        editableField("整改依据", text: $legalBasisDraft, placeholder: "整改依据", lineLimit: 3...10)
                        Picker("风险等级", selection: $riskLevelDraft) {
                            ForEach(HazardRiskLevel.canonicalOptions, id: \.self) { level in
                                Text(level).tag(level)
                            }
                        }
                    }
                }

                dashboardCard(title: "AI 建议参考", systemImage: "sparkles") {
                    DisclosureGroup {
                        labeledSuggestion("隐患描述", payload.analysis.hazardDescription)
                        labeledSuggestion("整改措施", payload.analysis.rectificationMeasures)
                        labeledSuggestion("整改依据", payload.analysis.legalBasis)
                        if !payload.analysis.rectificationReplyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            labeledSuggestion("整改回复建议", payload.analysis.rectificationReplyDraft)
                        }
                    } label: {
                        Text("展开查看 AI 原始建议（不会直接导出）")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    if !payload.analysis.rectificationReplyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Divider().opacity(0.35)
                        editableField("整改回复建议", text: $replyDraft, placeholder: "后续整改闭环可采用", lineLimit: 2...6)
                    }
                }

                dashboardCard(title: "事故类别", systemImage: "square.stack.3d.up") {
                    Text(accidentCategoryBody(payload.analysis))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                dashboardCard(title: "整改安排", systemImage: "calendar.badge.clock") {
                    Text(rectificationIntentSummary)
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .onAppear { initializeDraftsIfNeeded() }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("确认正式内容")
        .inlineNavigationTitleMode()
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button("放弃") {
                    onDone()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("保存正式记录") {
                    commitSaveIfNeeded()
                }
                .buttonStyle(.borderedProminent)
                .tint(Self.productivityAccent)
                .frame(maxWidth: .infinity)
                .disabled(isSavingToCoreData || !hasRequiredFormalFields)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .alert("无法保存", isPresented: Binding(
            get: { saveToCoreDataError != nil },
            set: { if !$0 { saveToCoreDataError = nil } }
        )) {
            Button("好的", role: .cancel) { saveToCoreDataError = nil }
        } message: {
            Text(saveToCoreDataError ?? "")
        }
    }

    /*
     Legacy view body kept below removed in favor of formal confirmation flow.
     */
    private func initializeDraftsIfNeeded() {
        guard !didInitializeDrafts else { return }
        didInitializeDrafts = true
        projectNameDraft = payload.reportProjectName ?? ""
        inspectorNameDraft = payload.reportInspectorName ?? ""
        locationDraft = payload.location
        inspectionSituationDraft = payload.supplementaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        issueDraft = payload.analysis.hazardDescription
        requirementDraft = payload.analysis.rectificationMeasures
        legalBasisDraft = payload.analysis.legalBasis
        replyDraft = payload.analysis.rectificationReplyDraft
        riskLevelDraft = HazardRiskLevel.effectiveLevel(
            userOverride: payload.userRiskLevelOverride,
            aiLevel: payload.analysis.riskLevel
        )
    }

    private var hasRequiredFormalFields: Bool {
        !projectNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !inspectorNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !locationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !inspectionSituationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !issueDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !requirementDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !legalBasisDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func editableField(
        _ title: String,
        text: Binding<String>,
        placeholder: String,
        lineLimit: ClosedRange<Int> = 1...3
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(lineLimit)
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func labeledSuggestion(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : value)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }

    private func confirmedPayload() -> HazardResultPayload {
        var confirmed = payload
        confirmed.location = locationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        confirmed.supplementaryText = inspectionSituationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        confirmed.userRiskLevelOverride = HazardRiskLevel.normalizedForStorage(riskLevelDraft)
        confirmed.reportProjectName = projectNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        confirmed.reportInspectorName = inspectorNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        confirmed.analysis = HazardAnalysisResult(
            hazardDescription: issueDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            rectificationMeasures: requirementDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            rectificationReplyDraft: replyDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            riskLevel: riskLevelDraft,
            accidentCategoryMajor: payload.analysis.accidentCategoryMajor,
            accidentCategoryMinor: payload.analysis.accidentCategoryMinor,
            legalBasis: legalBasisDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return confirmed
    }

    private func commitSaveIfNeeded() {
        if didSaveToCoreData {
            onDone()
            return
        }
        guard !isSavingToCoreData else { return }
        isSavingToCoreData = true
        let confirmed = confirmedPayload()
        let ok = InspectionFinding.savePayload(confirmed, context: viewContext)
        isSavingToCoreData = false
        if ok {
            didSaveToCoreData = true
            if confirmed.rectificationIntent == .scheduled, confirmed.addDeadlineToDeviceCalendar {
                let loc = confirmed.location.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = loc.isEmpty ? "安全大师·隐患整改截止" : "安全大师·整改截止（\(loc)）"
                let snippet = String(confirmed.analysis.hazardDescription.prefix(200))
                let notes = "地点：\(loc.isEmpty ? "（未填）" : loc)\n\n\(snippet)"
                let due = confirmed.rectificationPlannedDueAt ?? Date()
                Task {
                    _ = await RectificationCalendarExporter.tryAddDeadlineReminder(
                        title: title,
                        notes: notes,
                        deadlineDay: due,
                        location: loc.isEmpty ? nil : loc
                    )
                }
            }
            onDone()
        } else {
            saveToCoreDataError = "无法写入本地记录，请检查存储空间或稍后重试。"
        }
    }

    private var effectiveRiskLevel: String {
        HazardRiskLevel.effectiveLevel(
            userOverride: payload.userRiskLevelOverride,
            aiLevel: payload.analysis.riskLevel
        )
    }

    private var coreRiskSummary: String {
        let source = payload.analysis.hazardDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return "请尽快排查现场，避免风险扩散。" }
        let separators = CharacterSet(charactersIn: "。！？\n")
        let first = source.components(separatedBy: separators).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? source
        let text = first.isEmpty ? source : first
        if text.count <= 42 { return text }
        let end = text.index(text.startIndex, offsetBy: 42)
        return String(text[..<end]) + "…"
    }

    private var resultPhotoGallery: some View {
        Group {
            if !payload.sitePhotoDatasOrdered.isEmpty {
                TabView {
                    ForEach(Array(payload.sitePhotoDatasOrdered.enumerated()), id: \.offset) { index, data in
                        if let img = Image.fromStoredData(data) {
                            ZStack(alignment: .bottomLeading) {
                                img
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 220)
                                    .clipped()

                                Text(payload.sitePhotoDatasOrdered.count > 1 ? "照片 \(index + 1)" : "现场照片")
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
                .tabViewStyle(.page(indexDisplayMode: payload.sitePhotoDatasOrdered.count > 1 ? .automatic : .never))
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 6)
                .padding(.vertical, 8)
            }
        }
    }

    private func dashboardCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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

    private func riskBadge(_ level: String) -> some View {
        Text(level)
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(riskTint(level), in: Capsule())
            .shadow(color: riskTint(level).opacity(0.25), radius: 8, x: 0, y: 4)
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

    private var rectificationIntentSummary: String {
        switch payload.rectificationIntent {
        case .immediate:
            let hasNote = !payload.prefillRectificationActionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasPhoto = payload.prefillRectificationPhotoData != nil && !(payload.prefillRectificationPhotoData?.isEmpty ?? true)
            let extra: String
            if hasNote || hasPhoto {
                extra = "（识别页已填写现场说明\(hasPhoto ? "与照片" : "")，将写入第 1 轮。）"
            } else {
                extra = "（可在记录详情补充现场说明与照片后再提交验收。）"
            }
            return "立即整改：保存后自动建立第 1 轮整改。\(extra)"
        case .scheduled:
            if let d = payload.rectificationPlannedDueAt {
                let cal = payload.addDeadlineToDeviceCalendar ? "保存后将尝试写入系统日历。" : "未选择写入系统日历。"
                return "稍后安排：计划完成日 \(Self.dueOnlyFormatter.string(from: d))。\(cal)"
            }
            return "稍后安排：先保存现场记录，后续在隐患详情中确认责任人、整改期限和措施。"
        }
    }

    private static let dueOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func accidentCategoryBody(_ r: HazardAnalysisResult) -> String {
        let maj = r.accidentCategoryMajor.trimmingCharacters(in: .whitespacesAndNewlines)
        let mino = r.accidentCategoryMinor.trimmingCharacters(in: .whitespacesAndNewlines)
        if maj.isEmpty, mino.isEmpty {
            return "（未判定）"
        }
        if mino.isEmpty {
            return "大类：\(maj)"
        }
        if maj.isEmpty {
            return "细类：\(mino)"
        }
        return "大类：\(maj)\n细类：\(mino)"
    }
}

#Preview {
    NavigationStack {
        InspectionResultView(
            payload: HazardResultPayload(
                photoData: nil,
                location: "示例工地",
                supplementaryText: "",
                analysis: HazardAnalysisResult(
                    hazardDescription: "示例",
                    rectificationMeasures: "示例",
                    rectificationReplyDraft: "已落实示例整改并完成复查。",
                    riskLevel: "一般",
                    accidentCategoryMajor: "高处与建筑施工类",
                    accidentCategoryMinor: "高处坠落",
                    legalBasis: "示例法规摘录"
                )
            ),
            onDone: {}
        )
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
