//
//  ImportedNoticeInboxView.swift
//  安全大师
//

import SwiftUI
import UniformTypeIdentifiers

struct ImportedNoticeInboxView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @State private var items: [ImportedNoticeDocument] = []
    @State private var showFileImporter = false
    @State private var isImporting = false
    @State private var showIntake = false
    @State private var intakeText: String?
    @State private var intakeAutoRecognize = false
    @State private var intakeSessionID = UUID()
    @State private var message: String?
    @State private var reextractingIDs: Set<UUID> = []
    @State private var parsingDraftIDs: Set<UUID> = []
    @State private var textPreview: ImportedNoticeTextPreview?
    @State private var reviewSession: ImportedNoticeReviewSession?

    var body: some View {
        List {
            Section("操作") {
                Button {
                    showFileImporter = true
                } label: {
                    Label("导入文件", systemImage: "square.and.arrow.down")
                }

                if isImporting {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在导入与提取文本…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("导入箱") {
                if items.isEmpty {
                    ContentUnavailableView(
                        "暂无导入文件",
                        systemImage: "tray",
                        description: Text("支持 PDF、Word、图片和文本。导入后可提取正文并创建整改记录。")
                    )
                } else {
                    ForEach(items) { item in
                        documentCard(for: item)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    generateOrOpenDraft(for: item)
                                } label: {
                                    Label("草稿核对", systemImage: "doc.text.magnifyingglass")
                                }
                                .tint(.blue)

                                Button {
                                    showCleanedText(for: item)
                                } label: {
                                    Label("查看文本", systemImage: "text.viewfinder")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    delete(item)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle("导入箱")
        .inlineNavigationTitleMode()
        .onAppear {
            reloadItems()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importFiles(urls)
            case .failure(let error):
                message = "导入失败：\(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showIntake) {
            ExternalNoticeIntakeView(
                prefilledRawText: intakeText,
                autoRecognizeOnAppear: intakeAutoRecognize
            )
            .id(intakeSessionID)
            .environment(\.managedObjectContext, viewContext)
        }
        .sheet(item: $textPreview) { preview in
            NavigationStack {
                ImportedNoticeTextPreviewView(preview: preview)
            }
        }
        .sheet(item: $reviewSession, onDismiss: {
            reloadItems()
        }) { session in
            NavigationStack {
                ImportedNoticeReviewView(
                    document: session.document,
                    extraction: session.extraction,
                    draft: session.draft
                )
            }
        }
    }

    private var supportedContentTypes: [UTType] {
        let base: [UTType] = [.pdf, .plainText, .text, .rtf, .image]
        let office = [UTType(filenameExtension: "doc"), UTType(filenameExtension: "docx")]
            .compactMap { $0 }
        return base + office
    }

    private func reloadItems() {
        items = ImportedNoticeDocumentStore.list()
    }

    private func documentCard(for item: ImportedNoticeDocument) -> some View {
        let status = statusInfo(for: item)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.fileName)
                        .font(.headline.weight(.semibold))
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.primary)

                    Text(documentMetaLine(for: item, statusTitle: status.title))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                Button {
                    handleStatusTap(for: item)
                } label: {
                    ImportedNoticeStatusTag(status: status)
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("状态：\(status.title)")
            }

            if !item.extractedTextPreview.isEmpty {
                Text(item.extractedTextPreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: 10) {
                Spacer(minLength: 0)

                Button {
                    generateOrOpenDraft(for: item)
                } label: {
                    Label(primaryActionTitle(for: item), systemImage: primaryActionIcon(for: item))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(ImportedNoticePrimaryButtonStyle())
                .disabled(parsingDraftIDs.contains(item.id))

                Menu {
                    Button {
                        reextractText(for: item)
                    } label: {
                        Label(item.extractedTextLength == 0 ? "手动提取" : "重新提取文本", systemImage: "text.viewfinder")
                    }

                    Button {
                        showRawText(for: item)
                    } label: {
                        Label("查看原文", systemImage: "doc.plaintext")
                    }

                    Button {
                        showCleanedText(for: item)
                    } label: {
                        Label("查看清洗文本", systemImage: "wand.and.stars")
                    }

                    Button {
                        openIntake(from: item)
                    } label: {
                        Label("识别建档", systemImage: "text.magnifyingglass")
                    }

                    Button {
                        openReviewIfAvailable(for: item)
                    } label: {
                        Label("打开核对页面", systemImage: "checklist")
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(ImportedNoticeSecondaryButtonStyle())

                Button(role: .destructive) {
                    delete(item)
                } label: {
                    Label("删除", systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(ImportedNoticeDeleteButtonStyle())
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.28), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImporting = true
        Task {
            let imported = await ImportedNoticeDocumentStore.importFiles(from: urls)
            await MainActor.run {
                isImporting = false
                reloadItems()
                if imported.isEmpty {
                    message = "未导入成功，请重试。"
                } else {
                    message = "已导入 \(imported.count) 份文件。"
                }
            }
        }
    }

    private func openIntake(from item: ImportedNoticeDocument) {
        let extracted = normalizeForIntake(ImportedNoticeDocumentStore.extractedText(for: item))
        let fallback = normalizeForIntake(item.extractedTextPreview)
        let candidate = extracted ?? fallback
        intakeText = candidate
        intakeAutoRecognize = (candidate?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        intakeSessionID = UUID()
        if candidate == nil {
            message = "未读取到可用正文，请先点「手动提取」或手动粘贴。"
        }
        showIntake = true
    }

    private func delete(_ item: ImportedNoticeDocument) {
        let draft = ImportedNoticeDocumentStore.draft(forDocumentID: item.id)
        do {
            let deletedCount = try ExternalNoticePersistenceService.deleteImportedNoticeFindings(
                documentID: item.id,
                draft: draft,
                context: viewContext
            )
            ImportedNoticeDocumentStore.delete(item)
            reloadItems()
            if deletedCount > 0 {
                message = "已删除 \(item.fileName)，并移除 \(deletedCount) 条关联排查记录。"
            } else {
                message = "已删除 \(item.fileName)"
            }
        } catch {
            viewContext.rollback()
            message = "删除失败：\(error.localizedDescription)"
        }
    }

    private func reextractText(for item: ImportedNoticeDocument) {
        guard !reextractingIDs.contains(item.id) else { return }
        reextractingIDs.insert(item.id)
        message = "正在提取“\(item.fileName)”文本…"
        Task {
            let result = await ImportedNoticeDocumentStore.reextractText(for: item)
            await MainActor.run {
                reextractingIDs.remove(item.id)
                reloadItems()
                switch result {
                case .success(let updated):
                    if updated.extractedTextLength > 0 {
                        message = "已提取“\(updated.fileName)”文本。"
                    } else {
                        message = "未能提取“\(updated.fileName)”文本，可直接手动录入。"
                    }
                case .failure(let reason):
                    message = "提取失败：\(reason)"
                }
            }
        }
    }

    private func showRawText(for item: ImportedNoticeDocument) {
        guard let text = normalizeForIntake(ImportedNoticeDocumentStore.extractedText(for: item)) else {
            message = "未读取到原始文本，请先手动提取。"
            return
        }
        textPreview = ImportedNoticeTextPreview(
            title: "原始文本",
            fileName: item.fileName,
            text: text
        )
    }

    private func showCleanedText(for item: ImportedNoticeDocument) {
        guard let extraction = extractionForReview(item) else {
            message = "未读取到清洗文本，请先手动提取。"
            return
        }
        let cleaned = normalizeForIntake(extraction.cleanedText)
        guard let cleaned else {
            message = "清洗后文本为空，请重新提取或手动录入。"
            return
        }
        textPreview = ImportedNoticeTextPreview(
            title: "清洗文本",
            fileName: item.fileName,
            text: cleaned
        )
    }

    private func handleStatusTap(for item: ImportedNoticeDocument) {
        if ImportedNoticeDocumentStore.draft(forDocumentID: item.id) != nil {
            openReviewIfAvailable(for: item)
        } else if item.extractedTextLength > 0 {
            showCleanedText(for: item)
        } else {
            reextractText(for: item)
        }
    }

    private func documentMetaLine(for item: ImportedNoticeDocument, statusTitle: String) -> String {
        let size = Self.byteFormatter.string(fromByteCount: item.fileSizeBytes)
        let textCount = item.extractedTextLength > 0 ? "\(item.extractedTextLength) 字" : "未提取"
        return "\(Self.dateTimeFormatter.string(from: item.importedAt)) · \(size) · \(statusTitle) · \(textCount)"
    }

    private func primaryActionTitle(for item: ImportedNoticeDocument) -> String {
        if parsingDraftIDs.contains(item.id) {
            return "生成中"
        }
        return ImportedNoticeDocumentStore.draft(forDocumentID: item.id) == nil ? "生成草稿" : "草稿核对"
    }

    private func primaryActionIcon(for item: ImportedNoticeDocument) -> String {
        parsingDraftIDs.contains(item.id) ? "hourglass" : "doc.text.magnifyingglass"
    }

    private func statusInfo(for item: ImportedNoticeDocument) -> ImportedNoticeCardStatus {
        if reextractingIDs.contains(item.id) {
            return ImportedNoticeCardStatus(title: "提取中", systemImage: "hourglass", tint: .blue)
        }
        if parsingDraftIDs.contains(item.id) {
            return ImportedNoticeCardStatus(title: "草稿生成中", systemImage: "sparkles", tint: .purple)
        }
        if item.processingStatus == .reviewed {
            return ImportedNoticeCardStatus(title: "已确认入库", systemImage: "checkmark.seal.fill", tint: .green)
        }
        if item.processingStatus == .archivedOnly {
            return ImportedNoticeCardStatus(title: "仅保存原文件", systemImage: "archivebox.fill", tint: .secondary)
        }
        if ImportedNoticeDocumentStore.draft(forDocumentID: item.id) != nil || item.processingStatus == .draftReady {
            return ImportedNoticeCardStatus(title: "草稿生成", systemImage: "doc.text.fill", tint: .purple)
        }
        if item.processingStatus == .extractionFailed || item.processingStatus == .parsingFailed {
            return ImportedNoticeCardStatus(title: "处理失败", systemImage: "exclamationmark.triangle.fill", tint: .red)
        }
        if item.extractedTextLength > 0 || item.processingStatus == .extracted {
            return ImportedNoticeCardStatus(title: "已提取", systemImage: "text.badge.checkmark", tint: .green)
        }
        return ImportedNoticeCardStatus(title: "未提取", systemImage: "tray.fill", tint: .orange)
    }

    private func generateOrOpenDraft(for item: ImportedNoticeDocument) {
        if let draft = ImportedNoticeDocumentStore.draft(forDocumentID: item.id) {
            openReview(for: item, draft: draft)
            return
        }

        guard !parsingDraftIDs.contains(item.id) else { return }
        guard let extraction = extractionForReview(item) else {
            message = "未读取到可识别文本，请先手动提取。"
            return
        }

        parsingDraftIDs.insert(item.id)
        message = KeychainStore.safemasterAccessToken() == nil
            ? "正在生成“\(item.fileName)”的本地规则草稿…"
            : "正在调用云端 AI 识别“\(item.fileName)”…"
        Task.detached(priority: .userInitiated) {
            do {
                let draft = try await ImportedNoticeAIParser.parse(extraction: extraction, fileName: item.fileName)
                await MainActor.run {
                    _ = ImportedNoticeDocumentStore.saveDraft(draft)
                    _ = ImportedNoticeDocumentStore.updateProcessingStatus(.draftReady, forDocumentID: item.id)
                    parsingDraftIDs.remove(item.id)
                    reloadItems()
                    message = "草稿已生成，请核对后再入库。"
                    openReview(for: item, extraction: extraction, draft: draft)
                }
            } catch {
                await MainActor.run {
                    _ = ImportedNoticeDocumentStore.updateProcessingStatus(.parsingFailed, forDocumentID: item.id)
                    parsingDraftIDs.remove(item.id)
                    reloadItems()
                    message = "生成草稿失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func openReviewIfAvailable(for item: ImportedNoticeDocument) {
        guard let draft = ImportedNoticeDocumentStore.draft(forDocumentID: item.id) else {
            message = "还没有 AI 草稿，请先生成草稿。"
            return
        }
        openReview(for: item, draft: draft)
    }

    private func openReview(
        for item: ImportedNoticeDocument,
        extraction: ImportedNoticeExtraction? = nil,
        draft: ImportedNoticeDraft
    ) {
        reviewSession = ImportedNoticeReviewSession(
            document: item,
            extraction: extraction ?? extractionForReview(item),
            draft: draft
        )
    }

    private func extractionForReview(_ item: ImportedNoticeDocument) -> ImportedNoticeExtraction? {
        if let extraction = ImportedNoticeDocumentStore.extraction(forDocumentID: item.id) {
            if let rawText = normalizeForIntake(extraction.rawText) {
                return ImportedNoticeExtraction(
                    id: extraction.id,
                    documentID: extraction.documentID,
                    rawText: rawText,
                    sourceDescription: extraction.sourceDescription,
                    warnings: extraction.warnings,
                    quality: extraction.quality,
                    extractedAt: extraction.extractedAt
                )
            }
            ImportedNoticeDocumentStore.deleteExtraction(id: extraction.id)
        }
        guard let rawText = normalizeForIntake(ImportedNoticeDocumentStore.extractedText(for: item)) else {
            return nil
        }
        let extraction = ImportedNoticeExtraction(
            documentID: item.id,
            rawText: rawText,
            sourceDescription: item.fileType.reviewTitle
        )
        _ = ImportedNoticeDocumentStore.saveExtraction(extraction)
        return extraction
    }

    private func normalizeForIntake(_ raw: String?) -> String? {
        guard var text = raw else { return nil }
        text = text
            .replacingOccurrences(of: "\u{0000}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if looksLikeEmbeddedFileStructure(trimmed) {
            return nil
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    private func looksLikeEmbeddedFileStructure(_ text: String) -> Bool {
        let head = String(text.prefix(512)).trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("%PDF-") || head.hasPrefix("PK\u{03}\u{04}") || head.hasPrefix("bplist00") {
            return true
        }
        let pdfMarkers = [" obj", "endobj", "xref", "trailer", "%%EOF"]
        return pdfMarkers.filter { head.contains($0) }.count >= 3
    }

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB]
        f.countStyle = .file
        return f
    }()
}

private struct ImportedNoticeTextPreview: Identifiable {
    let id = UUID()
    var title: String
    var fileName: String
    var text: String
}

private struct ImportedNoticeReviewSession: Identifiable {
    let id = UUID()
    var document: ImportedNoticeDocument
    var extraction: ImportedNoticeExtraction?
    var draft: ImportedNoticeDraft
}

private struct ImportedNoticeCardStatus {
    var title: String
    var systemImage: String
    var tint: Color
}

private struct ImportedNoticeStatusTag: View {
    let status: ImportedNoticeCardStatus

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(status.tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(status.tint.opacity(0.16), in: Capsule())
    }
}

private struct ImportedNoticePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.72 : 0.95), in: Capsule())
    }
}

private struct ImportedNoticeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 11)
            .frame(minHeight: 34)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.18 : 0.11), in: Capsule())
    }
}

private struct ImportedNoticeDeleteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(.red)
            .padding(.horizontal, 11)
            .frame(minHeight: 34)
            .background(Color.red.opacity(configuration.isPressed ? 0.18 : 0.1), in: Capsule())
    }
}

private struct ImportedNoticeTextPreviewView: View {
    let preview: ImportedNoticeTextPreview

    var body: some View {
        Form {
            Section("文件") {
                Text(preview.fileName)
                    .font(.subheadline.weight(.semibold))
            }
            Section(preview.title) {
                Text(preview.text)
                    .font(.footnote)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle(preview.title)
        .inlineNavigationTitleMode()
    }
}

private extension ImportedNoticeFileType {
    var reviewTitle: String {
        switch self {
        case .pdf:
            return "PDF"
        case .word:
            return "Word/RTF"
        case .image:
            return "图片 OCR"
        case .text:
            return "文本"
        case .unknown:
            return "文件"
        }
    }
}

#Preview {
    NavigationStack {
        ImportedNoticeInboxView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
