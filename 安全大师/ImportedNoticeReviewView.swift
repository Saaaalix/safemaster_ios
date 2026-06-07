//
//  ImportedNoticeReviewView.swift
//  安全大师
//

import CoreData
import SwiftUI

struct ImportedNoticeReviewView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let document: ImportedNoticeDocument
    let extraction: ImportedNoticeExtraction?
    @State private var draft: ImportedNoticeDraft
    @State private var message: String?
    @State private var isReparsing = false
    @State private var isPersisting = false
    @State private var expandedHazardIDs: Set<UUID> = []
    @State private var showOriginalText = false

    init(
        document: ImportedNoticeDocument,
        extraction: ImportedNoticeExtraction? = nil,
        draft: ImportedNoticeDraft
    ) {
        self.document = document
        self.extraction = extraction
        _draft = State(initialValue: draft)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                summaryCard
                attentionSection
                hazardsSection
                advancedSection
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 96)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            bottomActionBar
        }
        .navigationTitle("导入文件处理")
        .inlineNavigationTitleMode()
        .sheet(isPresented: $showOriginalText) {
            NavigationStack {
                ImportedNoticeOriginalTextView(
                    title: "原文内容",
                    fileName: document.fileName,
                    text: extraction?.cleanedText ?? "暂无可查看的原文。"
                )
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(document.fileName)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(draft.documentType.reviewTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }

                Spacer()

                StatusBadge(status: overallStatus)
            }

            Divider()

            HStack(spacing: 18) {
                summaryMetric(title: "识别条目", value: "\(draft.hazards.count)")
                summaryMetric(title: "需要补充", value: "\(attentionFieldCount)")
                summaryMetric(title: "整体判断", value: overallStatus.title)
            }

            TextField("摘要", text: $draft.summary, axis: .vertical)
                .font(.subheadline)
                .lineLimit(2...4)
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("需要补充")
            VStack(spacing: 0) {
                if attentionFieldCount == 0 {
                    Label("关键字段已基本齐全", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    if draft.needsAttention(.projectName) {
                        compactFieldEditor("项目名称", field: $draft.projectName)
                    }
                    if draft.needsAttention(.issuer) {
                        compactFieldEditor("发文单位", field: $draft.issuer)
                    }
                    if draft.needsAttention(.inspectedUnit) {
                        compactFieldEditor("被检查单位", field: $draft.inspectedUnit)
                    }
                    if draft.needsAttention(.noticeNo) {
                        compactFieldEditor("通知编号", field: $draft.noticeNo)
                    }
                    if draft.needsAttention(.noticeDate) {
                        compactFieldEditor("通知日期", field: $draft.noticeDate)
                    }
                    if draft.needsAttention(.rectificationDeadline) {
                        compactFieldEditor("整改期限", field: $draft.rectificationDeadline)
                    }
                    if draft.needsAttention(.legalBasis) {
                        compactFieldEditor("法律依据", field: $draft.legalBasis, axis: .vertical)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var hazardsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader(draft.documentType == .rectificationReply ? "整改项清单" : "隐患清单")
                Spacer()
                Button {
                    addHazard()
                } label: {
                    Label("新增", systemImage: "plus")
                }
                .font(.subheadline.weight(.semibold))
            }

            if draft.hazards.isEmpty {
                ContentUnavailableView(
                    "暂无条目",
                    systemImage: "checklist",
                    description: Text("可以手动新增一条整改任务。")
                )
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(Array(draft.hazards.indices), id: \.self) { index in
                    hazardCard(index: index)
                }
            }
        }
    }

    private var advancedSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                if !draft.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("提示")
                            .font(.subheadline.weight(.semibold))
                        ForEach(draft.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Text("整体置信度：\(Self.percentFormatter.string(from: NSNumber(value: draft.confidence)) ?? "-")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                advancedField("项目名称", field: draft.projectName)
                advancedField("发文单位", field: draft.issuer)
                advancedField("被检查单位", field: draft.inspectedUnit)
                advancedField("通知编号", field: draft.noticeNo)
                advancedField("通知日期", field: draft.noticeDate)
                advancedField("整改期限", field: draft.rectificationDeadline)
                advancedField("法律依据", field: draft.legalBasis)
            }
            .padding(.top, 10)
        } label: {
            Label("查看识别依据 / 高级信息", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var bottomActionBar: some View {
        HStack(spacing: 10) {
            Button {
                saveDraft()
            } label: {
                Label("保存草稿", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                confirmPersistence()
            } label: {
                if isPersisting {
                    Label("入库中…", systemImage: "hourglass")
                        .frame(maxWidth: .infinity)
                } else {
                    Label("确认入库", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPersisting)

            Menu {
                Button {
                    reparseDraft()
                } label: {
                    Label(isReparsing ? "重新识别中…" : "重新识别", systemImage: "text.magnifyingglass")
                }
                .disabled(isReparsing || extraction == nil)

                Button {
                    showOriginalText = true
                } label: {
                    Label("查看原文", systemImage: "doc.plaintext")
                }

                Button {
                    archiveOnly()
                } label: {
                    Label("仅保存原文件", systemImage: "archivebox")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var attentionFieldCount: Int {
        draft.requiredFields.filter { draft.needsAttention($0) }.count
    }

    private var hazardNeedsReviewCount: Int {
        draft.hazards.filter { hazardStatus(for: $0) != .confirmed }.count
    }

    private var overallStatus: ReviewStatus {
        if attentionFieldCount > 0 {
            return .needsSupplement
        }
        if hazardNeedsReviewCount > 0 || draft.confidence < 0.75 {
            return .needsReview
        }
        return .ready
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
    }

    private func compactFieldEditor(
        _ title: String,
        field: Binding<ImportedNoticeRecognizedField>,
        axis: Axis = .horizontal
    ) -> some View {
        HStack(alignment: axis == .vertical ? .top : .center, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 86, alignment: .leading)

            if axis == .vertical {
                TextField("请补充", text: field.value, axis: .vertical)
                    .lineLimit(2...4)
            } else {
                TextField("请补充", text: field.value)
                    .lineLimit(1)
            }

            if fieldNeedsAttention(field.wrappedValue) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("需要核对")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .onChange(of: field.wrappedValue.value) { _, newValue in
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                field.wrappedValue.needsReview = false
            }
        }
    }

    @ViewBuilder
    private func hazardCard(index: Int) -> some View {
        if draft.hazards.indices.contains(index) {
            let hazard = draft.hazards[index]
            let isExpanded = expandedHazardIDs.contains(hazard.id)
            let status = hazardStatus(for: hazard)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("\(draft.documentType == .rectificationReply ? "整改项" : "隐患") \(index + 1)")
                                .font(.headline.weight(.semibold))
                            StatusBadge(status: status)
                        }

                        if let location = nonEmpty(hazard.location.value) {
                            Label(location, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Menu {
                        Button {
                            toggleHazardExpanded(hazard.id)
                        } label: {
                            Label(isExpanded ? "收起详情" : "编辑详情", systemImage: "square.and.pencil")
                        }

                        Button {
                            markHazardConfirmed(at: index)
                        } label: {
                            Label("标记确认", systemImage: "checkmark.circle")
                        }

                        Button(role: .destructive) {
                            deleteHazard(at: index)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .frame(width: 36, height: 36)
                    }
                }

                if let description = nonEmpty(hazard.description.value) {
                    labeledPreview("问题描述", text: description)
                }
                if let requirement = nonEmpty(hazard.requirement.value) {
                    labeledPreview(draft.documentType == .rectificationReply ? "整改情况" : "整改要求", text: requirement)
                }

                Button {
                    toggleHazardExpanded(hazard.id)
                } label: {
                    Label(isExpanded ? "收起详情" : "编辑详情", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.subheadline.weight(.semibold))
                }

                if isExpanded {
                    VStack(spacing: 0) {
                        compactFieldEditor("部位/地点", field: hazardFieldBinding(index: index, keyPath: \.location))
                        Divider()
                        compactFieldEditor("问题描述", field: hazardFieldBinding(index: index, keyPath: \.description), axis: .vertical)
                        Divider()
                        compactFieldEditor(draft.documentType == .rectificationReply ? "整改情况" : "整改要求", field: hazardFieldBinding(index: index, keyPath: \.requirement), axis: .vertical)
                        Divider()
                        compactFieldEditor("整改期限", field: hazardFieldBinding(index: index, keyPath: \.dueDate))
                        Divider()
                        compactFieldEditor("责任单位", field: hazardFieldBinding(index: index, keyPath: \.responsibleParty))
                    }
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))

                    DisclosureGroup("识别依据") {
                        VStack(alignment: .leading, spacing: 8) {
                            advancedField("部位/地点", field: draft.hazards[index].location)
                            advancedField("问题描述", field: draft.hazards[index].description)
                            advancedField(draft.documentType == .rectificationReply ? "整改情况" : "整改要求", field: draft.hazards[index].requirement)
                            advancedField("整改期限", field: draft.hazards[index].dueDate)
                            advancedField("责任单位", field: draft.hazards[index].responsibleParty)
                        }
                        .padding(.top, 8)
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func labeledPreview(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func advancedField(_ title: String, field: ImportedNoticeRecognizedField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(Self.percentFormatter.string(from: NSNumber(value: field.confidence)) ?? "-")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if fieldNeedsAttention(field) {
                    Text("需要核对")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            if let value = nonEmpty(field.value) {
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }
            if let snippet = nonEmpty(field.sourceSnippet) {
                Text(snippet)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(.vertical, 4)
    }

    private func fieldNeedsAttention(_ field: ImportedNoticeRecognizedField) -> Bool {
        field.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || field.needsReview
    }

    private func hazardStatus(for hazard: ImportedNoticeHazardDraft) -> ReviewStatus {
        let hasDescription = nonEmpty(hazard.description.value) != nil
        let hasRequirement = nonEmpty(hazard.requirement.value) != nil
        if !hasDescription || !hasRequirement {
            return .incomplete
        }
        let fields = [hazard.location, hazard.description, hazard.requirement, hazard.dueDate, hazard.responsibleParty]
        return fields.contains(where: fieldNeedsAttention) ? .needsReview : .confirmed
    }

    private func toggleHazardExpanded(_ id: UUID) {
        if expandedHazardIDs.contains(id) {
            expandedHazardIDs.remove(id)
        } else {
            expandedHazardIDs.insert(id)
        }
    }

    private func markHazardConfirmed(at index: Int) {
        guard draft.hazards.indices.contains(index) else { return }
        draft.hazards[index].location.needsReview = false
        draft.hazards[index].description.needsReview = false
        draft.hazards[index].requirement.needsReview = false
        draft.hazards[index].dueDate.needsReview = false
        draft.hazards[index].responsibleParty.needsReview = false
        message = "已确认第 \(index + 1) 条。"
    }

    private func nonEmpty(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    @ViewBuilder
    private func hazardEditor(index: Int) -> some View {
        if draft.hazards.indices.contains(index) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("隐患 \(index + 1)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(role: .destructive) {
                        deleteHazard(at: index)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                recognizedFieldEditor("部位/地点", field: hazardFieldBinding(index: index, keyPath: \.location))
                recognizedFieldEditor("存在问题", field: hazardFieldBinding(index: index, keyPath: \.description), axis: .vertical)
                recognizedFieldEditor("整改要求", field: hazardFieldBinding(index: index, keyPath: \.requirement), axis: .vertical)
                recognizedFieldEditor("整改期限", field: hazardFieldBinding(index: index, keyPath: \.dueDate))
                recognizedFieldEditor("责任人/责任单位", field: hazardFieldBinding(index: index, keyPath: \.responsibleParty))
            }
            .padding(.vertical, 4)
        }
    }

    private func recognizedFieldEditor(
        _ title: String,
        field: Binding<ImportedNoticeRecognizedField>,
        axis: Axis = .horizontal
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if axis == .vertical {
                TextField(title, text: field.value, axis: .vertical)
                    .lineLimit(2...6)
            } else {
                TextField(title, text: field.value)
            }

            HStack(spacing: 8) {
                Text("置信度 \(Self.percentFormatter.string(from: NSNumber(value: field.wrappedValue.confidence)) ?? "-")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if field.wrappedValue.needsReview || field.wrappedValue.confidence < 0.85 {
                    Label("需要核对", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Toggle("标记为需要核对", isOn: field.needsReview)
                .font(.caption)

            if let snippet = field.wrappedValue.sourceSnippet,
               !snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(snippet)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
    }

    private func hazardFieldBinding(
        index: Int,
        keyPath: WritableKeyPath<ImportedNoticeHazardDraft, ImportedNoticeRecognizedField>
    ) -> Binding<ImportedNoticeRecognizedField> {
        Binding(
            get: {
                guard draft.hazards.indices.contains(index) else { return .empty() }
                return draft.hazards[index][keyPath: keyPath]
            },
            set: { newValue in
                guard draft.hazards.indices.contains(index) else { return }
                draft.hazards[index][keyPath: keyPath] = newValue
            }
        )
    }

    private func addHazard() {
        draft.hazards.append(ImportedNoticeHazardDraft())
        message = "已新增一条隐患草稿。"
    }

    private func deleteHazard(at index: Int) {
        guard draft.hazards.indices.contains(index) else { return }
        draft.hazards.remove(at: index)
        message = "已删除隐患条目。"
    }

    private func saveDraft() {
        if ImportedNoticeDocumentStore.saveDraft(draft) != nil {
            _ = ImportedNoticeDocumentStore.updateProcessingStatus(.draftReady, forDocumentID: document.id)
            message = "草稿已保存。"
        } else {
            message = "草稿保存失败，请稍后重试。"
        }
    }

    private func reparseDraft() {
        guard let extraction else {
            message = "暂无可重新识别的提取文本。"
            return
        }
        isReparsing = true
        message = KeychainStore.safemasterAccessToken() == nil ? "正在用本地规则重新识别…" : "正在调用云端 AI 重新识别…"
        Task.detached(priority: .userInitiated) {
            do {
                let reparsed = try await ImportedNoticeAIParser.parse(extraction: extraction, fileName: document.fileName)
                await MainActor.run {
                    draft = reparsed
                    isReparsing = false
                    message = "已重新识别，请核对后保存草稿。"
                }
            } catch {
                await MainActor.run {
                    isReparsing = false
                    message = "重新识别失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func confirmPersistence() {
        guard !isPersisting else { return }
        guard ImportedNoticeDocumentStore.saveDraft(draft) != nil else {
            message = "草稿保存失败，暂未入库。"
            return
        }

        isPersisting = true
        message = "正在入库，请稍候…"
        let draftToSave = draft
        let documentID = document.id
        let context = viewContext
        Task {
            do {
                let result = try await context.perform {
                    try ExternalNoticePersistenceService.save(
                        importedNoticeDraft: draftToSave,
                        context: context
                    )
                }
                await MainActor.run {
                    _ = ImportedNoticeDocumentStore.updateProcessingStatus(.reviewed, forDocumentID: documentID)
                    isPersisting = false
                    switch result.status {
                    case .saved:
                        message = "已确认入库。"
                    case .updated:
                        message = "已更新入库记录。"
                    }
                }
            } catch {
                await MainActor.run {
                    isPersisting = false
                    message = "入库失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func archiveOnly() {
        if ImportedNoticeDocumentStore.updateProcessingStatus(.archivedOnly, forDocumentID: document.id) != nil {
            message = "已标记为仅保存原文件。"
        } else {
            message = "状态更新失败，请稍后重试。"
        }
    }

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

private extension ImportedNoticeDocumentType {
    var reviewTitle: String {
        switch self {
        case .hazardNotice:
            return "隐患通知"
        case .rectificationReply:
            return "整改回复"
        case .inspectionRecord:
            return "检查记录"
        case .meetingMinutes:
            return "会议纪要"
        case .unknown:
            return "未知"
        }
    }
}

private enum ReviewStatus {
    case ready
    case needsSupplement
    case needsReview
    case incomplete
    case confirmed

    var title: String {
        switch self {
        case .ready:
            return "可入库"
        case .needsSupplement:
            return "需补充"
        case .needsReview:
            return "建议核对"
        case .incomplete:
            return "信息不完整"
        case .confirmed:
            return "已确认"
        }
    }

    var systemImage: String {
        switch self {
        case .ready, .confirmed:
            return "checkmark.circle.fill"
        case .needsSupplement:
            return "square.and.pencil"
        case .needsReview:
            return "exclamationmark.triangle.fill"
        case .incomplete:
            return "questionmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ready, .confirmed:
            return .green
        case .needsSupplement:
            return .orange
        case .needsReview:
            return .yellow
        case .incomplete:
            return .red
        }
    }
}

private struct StatusBadge: View {
    let status: ReviewStatus

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(status.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(status.tint.opacity(0.14), in: Capsule())
    }
}

private struct ImportedNoticeOriginalTextView: View {
    var title: String
    var fileName: String
    var text: String

    var body: some View {
        Form {
            Section("文件") {
                Text(fileName)
                    .font(.subheadline.weight(.semibold))
            }
            Section(title) {
                Text(text)
                    .font(.footnote)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle(title)
        .inlineNavigationTitleMode()
    }
}

#Preview {
    NavigationStack {
        ImportedNoticeReviewView(
            document: ImportedNoticeDocument(
                id: UUID(),
                fileName: "监理整改通知.pdf",
                fileExtension: "pdf",
                importedAt: Date(),
                fileSizeBytes: 248_000,
                storedFileName: "demo.pdf",
                extractedTextFileName: "demo.txt",
                extractedTextLength: 180,
                extractedTextPreview: "项目名称：示例项目\n存在问题：临边防护不到位"
            ),
            extraction: ImportedNoticeExtraction(
                documentID: UUID(),
                rawText: "项目名称：示例项目\n存在问题：临边防护不到位\n整改要求：立即完善防护。",
                sourceDescription: "PDF"
            ),
            draft: ImportedNoticeDraft(
                documentID: UUID(),
                documentType: .hazardNotice,
                projectName: ImportedNoticeRecognizedField(value: "示例项目", confidence: 0.9),
                issuer: ImportedNoticeRecognizedField(value: "监理部", confidence: 0.82, sourceSnippet: "发文单位：监理部"),
                hazards: [
                    ImportedNoticeHazardDraft(
                        location: ImportedNoticeRecognizedField(value: "二层临边", confidence: 0.86),
                        description: ImportedNoticeRecognizedField(value: "临边防护不到位", confidence: 0.78, sourceSnippet: "存在问题：临边防护不到位"),
                        requirement: ImportedNoticeRecognizedField(value: "立即完善防护", confidence: 0.8),
                        dueDate: ImportedNoticeRecognizedField(value: "2026-06-10", confidence: 0.76),
                        responsibleParty: ImportedNoticeRecognizedField(value: "施工单位", confidence: 0.82)
                    )
                ],
                summary: "临边防护不到位",
                confidence: 0.82,
                warnings: ["整改期限置信度较低，请核对。"]
            )
        )
    }
}
