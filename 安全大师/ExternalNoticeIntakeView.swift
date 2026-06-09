//
//  ExternalNoticeIntakeView.swift
//  安全大师
//

import CoreData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

private enum ExternalImportDestination: String, CaseIterable, Hashable {
    case hazardNotice
    case rectificationReply

    var title: String {
        switch self {
        case .hazardNotice: return "隐患通知"
        case .rectificationReply: return "整改回复"
        }
    }

    var helperText: String {
        switch self {
        case .hazardNotice:
            return "先保存为外部文书归档记录，后续可继续补充整改闭环。"
        case .rectificationReply:
            return "先保存为整改回复归档记录，自动归入已通过轮次。"
        }
    }
}

struct ExternalNoticeIntakeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var issuer = ""
    @State private var inspectedUnit = ""
    @State private var noticeNo = ""
    @State private var noticeDate = Date()
    @State private var projectName = ""
    @State private var inspectorName = "外部检查"
    @State private var hazardCountText = ""
    @State private var location = ""
    @State private var hazardDescription = ""
    @State private var rectificationMeasures = ""
    @State private var legalBasis = ""
    @State private var rectificationSituation = ""
    @State private var plannedDueAt = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    @State private var responsibleParty = ""
    @State private var rawNoticeText = ""
    @State private var didArchiveTextCleanup = false
    @State private var recognitionHint: String?
    @State private var recognitionWarnings: [String] = []
    @State private var recognizedConfidence: [ExternalNoticeRecognizedField: Double] = [:]
    @State private var recognizedIssueItems: [ExternalNoticeIssueItem] = []
    @State private var saveError: String?
    @State private var didAutoRecognize = false
    @State private var importDestination: ExternalImportDestination = .hazardNotice
    @State private var isIssueSectionExpanded = false
    @State private var showFileImporter = false
    @State private var isImportingFile = false
    private let autoRecognizeOnAppear: Bool

    init(prefilledRawText: String? = nil, autoRecognizeOnAppear: Bool = false) {
        _rawNoticeText = State(initialValue: prefilledRawText ?? "")
        self.autoRecognizeOnAppear = autoRecognizeOnAppear
    }

    private var canSave: Bool {
        let project = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let inspected = inspectedUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = rawNoticeText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !project.isEmpty || !inspected.isEmpty || !raw.isEmpty
    }

    private var issuerFieldTitle: String {
        let raw = rawNoticeText
        if raw.contains("检查单位"), !raw.contains("发文单位") {
            return "检查单位"
        }
        if raw.contains("发文单位"), !raw.contains("检查单位") {
            return "发文单位"
        }
        return "检查单位/发文单位"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("导入类型") {
                    Picker("导入类型", selection: $importDestination) {
                        ForEach(ExternalImportDestination.allCases, id: \.self) { destination in
                            Text(destination.title).tag(destination)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(importDestination.helperText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("原文识别（可选）") {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("选择 PDF / Word / 图片", systemImage: "tray.full")
                    }

                    if isImportingFile {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在导入并提取正文…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ZStack(alignment: .topLeading) {
                        if rawNoticeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("可先选择 PDF/Word/图片，或粘贴通知单原文")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        TextEditor(text: $rawNoticeText)
                            .frame(minHeight: 160, maxHeight: 240)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                    }
                    Button {
                        recognizeAndApplyDraft()
                    } label: {
                        Label("提取归档信息", systemImage: "text.magnifyingglass")
                    }
                    if let recognitionHint {
                        Text(recognitionHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !recognitionWarnings.isEmpty {
                        ForEach(recognitionWarnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section("来文信息") {
                    TextField("\(issuerFieldTitle)（例如：监理部）", text: $issuer)
                    confidenceLine(.issuer, fallbackText: "\(issuerFieldTitle)识别置信")
                    TextField("受检单位（例如：XX项目部）", text: $inspectedUnit, axis: .vertical)
                        .lineLimit(2...4)
                    confidenceLine(.inspectedUnit, fallbackText: "受检单位识别置信")
                    TextField("来文编号（例如：监理整改单-2026-018）", text: $noticeNo)
                    confidenceLine(.noticeNo, fallbackText: "编号识别置信")
                    DatePicker("来文日期", selection: $noticeDate, displayedComponents: [.date])
                    confidenceLine(.noticeDate, fallbackText: "来文日期识别置信")
                }

                Section("本次闭环归档信息") {
                    TextField("项目名称", text: $projectName)
                    confidenceLine(.projectName, fallbackText: "项目名称识别置信")
                    TextField("检查人（默认：外部检查）", text: $inspectorName)
                    confidenceLine(.inspectorName, fallbackText: "检查人识别置信")
                    TextField("责任人（可选）", text: $responsibleParty)
                    confidenceLine(.responsibleParty, fallbackText: "责任人识别置信")
                    DatePicker("整改期限", selection: $plannedDueAt, displayedComponents: [.date])
                    confidenceLine(.dueDate, fallbackText: "整改期限识别置信")
                    TextField("隐患条数（仅用于核对）", text: $hazardCountText)
                        .keyboardType(.numberPad)
                    confidenceLine(.hazardCount, fallbackText: "隐患条数识别置信")
                }

                Section("可选信息") {
                    DisclosureGroup("可选：识别到的隐患条目", isExpanded: $isIssueSectionExpanded) {
                        if !recognizedIssueItems.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("识别到 \(recognizedIssueItems.count) 条候选隐患，轻点可填入下方字段。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(Array(recognizedIssueItems.enumerated()), id: \.offset) { index, item in
                                    Button {
                                        applyIssueItem(item)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.location ?? item.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            Text(item.hazardDescription)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(3)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityLabel("填入候选隐患 \(index + 1)")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        TextField("部位/地点", text: $location)
                        confidenceLine(.location, fallbackText: "部位识别置信")
                        TextField("存在问题（可选，建议填写）", text: $hazardDescription, axis: .vertical)
                            .lineLimit(3...8)
                        confidenceLine(.hazardDescription, fallbackText: "存在问题识别置信")
                        TextField("整改要求（可选，建议填写）", text: $rectificationMeasures, axis: .vertical)
                            .lineLimit(3...8)
                        confidenceLine(.rectificationMeasures, fallbackText: "整改要求识别置信")
                        if importDestination == .rectificationReply {
                            TextField("整改情况（建议填写）", text: $rectificationSituation, axis: .vertical)
                                .lineLimit(3...8)
                            confidenceLine(.rectificationSituation, fallbackText: "整改情况识别置信")
                        }
                        TextField("整改依据（可选）", text: $legalBasis, axis: .vertical)
                            .lineLimit(3...8)
                        confidenceLine(.legalBasis, fallbackText: "整改依据识别置信")
                    }
                    Text("这些内容仅作为参考，不填写也可以先归档。归档后可在记录详情中继续补充。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded {
                    dismissKeyboard()
                }
            )
            .navigationTitle("外部通知归档")
            .inlineNavigationTitleMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认归档") {
                        saveFindingFromExternalNotice()
                    }
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起") {
                        dismissKeyboard()
                    }
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好的", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: supportedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                handlePickedExternalNoticeFile(result)
            }
            .onAppear {
                if !didArchiveTextCleanup {
                    rawNoticeText = cleanupArchiveRawText(rawNoticeText)
                    didArchiveTextCleanup = true
                }
                guard autoRecognizeOnAppear, !didAutoRecognize else { return }
                let trimmed = rawNoticeText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                didAutoRecognize = true
                recognizeAndApplyDraft()
            }
        }
    }

    private func dismissKeyboard() {
#if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
    }

    private var supportedContentTypes: [UTType] {
        let base: [UTType] = [.pdf, .plainText, .text, .rtf, .image]
        let office = [UTType(filenameExtension: "doc"), UTType(filenameExtension: "docx")]
            .compactMap { $0 }
        return base + office
    }

    private func handlePickedExternalNoticeFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            isImportingFile = true
            recognitionHint = "正在导入“\(url.lastPathComponent)”…"
            Task {
                let imported = await ImportedNoticeDocumentStore.importFiles(from: [url])
                await MainActor.run {
                    isImportingFile = false
                    guard let item = imported.first else {
                        recognitionHint = "文件导入失败，请确认文件可访问，或改用复制原文粘贴。"
                        return
                    }
                    let extracted = ImportedNoticeDocumentStore.extractedText(for: item)
                    let fallback = item.extractedTextPreview
                    let text = (extracted?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                        ? extracted
                        : fallback.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let text, !text.isEmpty else {
                        recognitionHint = "已导入“\(item.fileName)”，但暂未提取到正文。可在导入箱尝试手动提取，或粘贴原文。"
                        return
                    }
                    rawNoticeText = cleanupArchiveRawText(text)
                    recognitionHint = "已导入“\(item.fileName)”，正在提取归档信息…"
                    recognizeAndApplyDraft()
                }
            }
        case .failure(let error):
            recognitionHint = "选择文件失败：\(error.localizedDescription)"
        }
    }

    private func saveFindingFromExternalNotice() {
        do {
            try ExternalNoticePersistenceService.save(
                input: ExternalNoticePersistenceInput(
                    issuerLabel: issuerFieldTitle,
                    issuer: issuer,
                    inspectedUnit: inspectedUnit,
                    noticeNo: noticeNo,
                    noticeDate: noticeDate,
                    projectName: projectName,
                    inspectorName: inspectorName,
                    hazardCountText: hazardCountText,
                    location: location,
                    hazardDescription: hazardDescription,
                    rectificationMeasures: rectificationMeasures,
                    legalBasis: legalBasis,
                    rectificationSituation: rectificationSituation,
                    plannedDueAt: plannedDueAt,
                    responsibleParty: responsibleParty,
                    destination: persistenceDestination
                ),
                context: viewContext
            )
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private var persistenceDestination: ExternalNoticePersistenceDestination {
        switch importDestination {
        case .hazardNotice:
            return .hazardNotice
        case .rectificationReply:
            return .rectificationReply
        }
    }

    private func recognizeAndApplyDraft() {
        let source = rawNoticeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            recognitionHint = "请先选择 PDF/Word/图片，或粘贴通知单原文后再提取。"
            return
        }
        recognitionHint = "正在提取归档信息…"
        let draft = ExternalNoticeRecognizer.recognize(from: rawNoticeText)
        if let value = draft.issuer { issuer = value }
        if let value = draft.inspectedUnit { inspectedUnit = value }
        if let value = draft.inspectorName { inspectorName = value }
        if let value = draft.noticeNo { noticeNo = value }
        if let value = draft.noticeDate { noticeDate = value }
        if let value = draft.projectName { projectName = value }
        if let value = draft.hazardCount { hazardCountText = "\(value)" }
        if let value = draft.responsibleParty { responsibleParty = value }
        if let value = draft.dueDate { plannedDueAt = value }
        if location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let value = draft.location {
            location = value
        }
        if let value = draft.rectificationSituation { rectificationSituation = value }
        if let value = draft.legalBasis { legalBasis = value }
        if hazardDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let value = draft.hazardDescription {
            hazardDescription = value
        }
        if rectificationMeasures.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let value = draft.rectificationMeasures {
            rectificationMeasures = value
        }

        recognizedConfidence = draft.confidence
        recognitionWarnings = draft.warnings
        recognizedIssueItems = draft.issueItems

        let recognizedCount = draft.confidence.count
        importDestination = inferImportDestination(rawText: rawNoticeText, draft: draft)
        if recognizedCount == 0 {
            recognitionHint = "正文已归档为待补信息，但部分字段未识别。请补充关键归档信息后保存。"
        } else if !recognizedIssueItems.isEmpty {
            recognitionHint = "已提取 \(recognizedCount) 项归档信息，并识别到 \(recognizedIssueItems.count) 条候选隐患；候选隐患不影响归档。"
        } else {
            recognitionHint = "已提取 \(recognizedCount) 项归档信息，已预选为「\(importDestination.title)」。隐患条目未完整识别，不影响归档。"
        }
    }

    private func applyIssueItem(_ item: ExternalNoticeIssueItem) {
        if let value = item.location {
            location = value
        }
        hazardDescription = item.hazardDescription
        if let value = item.rectificationMeasures {
            rectificationMeasures = value
        }
        recognitionHint = "已填入“\(item.title)”候选内容，请核对后归档。"
    }

    private func inferImportDestination(rawText: String, draft: ExternalNoticeRecognitionDraft) -> ExternalImportDestination {
        let text = rawText.lowercased()
        let rectificationKeywords = ["整改完成", "整改情况", "复查意见", "验收通过", "闭环", "复查结论", "已整改", "整改回复"]
        let hazardKeywords = ["限期整改", "存在问题", "隐患", "整改要求", "整改期限", "责令"]
        let rectificationScore = rectificationKeywords.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
            + (draft.rectificationSituation == nil ? 0 : 2)
        let hazardScore = hazardKeywords.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
            + (draft.dueDate == nil ? 0 : 1)
        return rectificationScore > hazardScore ? .rectificationReply : .hazardNotice
    }

    @ViewBuilder
    private func confidenceLine(_ field: ExternalNoticeRecognizedField, fallbackText: String) -> some View {
        if let confidence = recognizedConfidence[field] {
            let presentation = confidencePresentation(confidence)
            Text("\(fallbackText)：\(presentation.tag)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(presentation.tint)
        }
    }

    private func confidencePresentation(_ confidence: Double) -> (tag: String, tint: Color) {
        switch confidence {
        case 0.85...:
            return ("高", .green)
        case 0.65...:
            return ("中", .orange)
        default:
            return ("低", .red)
        }
    }

    private func cleanupArchiveRawText(_ raw: String) -> String {
        let trimmed = raw
            .replacingOccurrences(of: "\u{0000}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? raw : trimmed
    }

}
