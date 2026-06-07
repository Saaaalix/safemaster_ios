//
//  ImportedNoticeDocumentStore.swift
//  安全大师
//

import Foundation

enum ImportedNoticeReextractResult {
    case success(ImportedNoticeDocument)
    case failure(String)
}

enum ImportedNoticeDocumentStore {
    private static let directoryName = "ImportedNoticeDocuments"
    private static let indexFileName = "index.json"
    private static let extractionIndexFileName = "extractions.json"
    private static let draftIndexFileName = "drafts.json"

    static func list() -> [ImportedNoticeDocument] {
        documents()
    }

    static func documents() -> [ImportedNoticeDocument] {
        (try? loadDocumentIndex())?.sorted(by: { $0.importedAt > $1.importedAt }) ?? []
    }

    static func document(id: UUID) -> ImportedNoticeDocument? {
        documents().first(where: { $0.id == id })
    }

    @discardableResult
    static func saveDocument(_ document: ImportedNoticeDocument) -> ImportedNoticeDocument? {
        var all = documents()
        if let idx = all.firstIndex(where: { $0.id == document.id }) {
            all[idx] = document
        } else {
            all.insert(document, at: 0)
        }
        do {
            try saveDocumentIndex(all)
            return document
        } catch {
            return nil
        }
    }

    @discardableResult
    static func updateDocument(_ document: ImportedNoticeDocument) -> ImportedNoticeDocument? {
        saveDocument(document)
    }

    @discardableResult
    static func updateProcessingStatus(
        _ status: ImportedNoticeProcessingStatus,
        forDocumentID documentID: UUID
    ) -> ImportedNoticeDocument? {
        var all = documents()
        guard let idx = all.firstIndex(where: { $0.id == documentID }) else { return nil }
        all[idx].processingStatus = status
        do {
            try saveDocumentIndex(all)
            return all[idx]
        } catch {
            return nil
        }
    }

    static func extractions() -> [ImportedNoticeExtraction] {
        (try? loadExtractionIndex())?.sorted(by: { $0.extractedAt > $1.extractedAt }) ?? []
    }

    static func extraction(id: UUID) -> ImportedNoticeExtraction? {
        extractions().first(where: { $0.id == id })
    }

    static func extraction(forDocumentID documentID: UUID) -> ImportedNoticeExtraction? {
        extractions().first(where: { $0.documentID == documentID })
    }

    @discardableResult
    static func saveExtraction(_ extraction: ImportedNoticeExtraction) -> ImportedNoticeExtraction? {
        var all = extractions()
        if let idx = all.firstIndex(where: { $0.id == extraction.id }) {
            all[idx] = extraction
        } else if let documentID = extraction.documentID,
                  let idx = all.firstIndex(where: { $0.documentID == documentID }) {
            all[idx] = extraction
        } else {
            all.insert(extraction, at: 0)
        }
        do {
            try saveExtractionIndex(all)
            return extraction
        } catch {
            return nil
        }
    }

    @discardableResult
    static func updateExtraction(_ extraction: ImportedNoticeExtraction) -> ImportedNoticeExtraction? {
        saveExtraction(extraction)
    }

    static func deleteExtraction(id: UUID) {
        var all = extractions()
        all.removeAll(where: { $0.id == id })
        try? saveExtractionIndex(all)
    }

    static func deleteExtraction(forDocumentID documentID: UUID) {
        var all = extractions()
        all.removeAll(where: { $0.documentID == documentID })
        try? saveExtractionIndex(all)
    }

    static func drafts() -> [ImportedNoticeDraft] {
        (try? loadDraftIndex())?.sorted(by: { $0.createdAt > $1.createdAt }) ?? []
    }

    static func draft(id: UUID) -> ImportedNoticeDraft? {
        drafts().first(where: { $0.id == id })
    }

    static func draft(forDocumentID documentID: UUID) -> ImportedNoticeDraft? {
        drafts().first(where: { $0.documentID == documentID })
    }

    @discardableResult
    static func saveDraft(_ draft: ImportedNoticeDraft) -> ImportedNoticeDraft? {
        var all = drafts()
        if let idx = all.firstIndex(where: { $0.id == draft.id }) {
            all[idx] = draft
        } else if let idx = all.firstIndex(where: { $0.documentID == draft.documentID }) {
            all[idx] = draft
        } else {
            all.insert(draft, at: 0)
        }
        do {
            try saveDraftIndex(all)
            return draft
        } catch {
            return nil
        }
    }

    @discardableResult
    static func updateDraft(_ draft: ImportedNoticeDraft) -> ImportedNoticeDraft? {
        saveDraft(draft)
    }

    static func deleteDraft(id: UUID) {
        var all = drafts()
        all.removeAll(where: { $0.id == id })
        try? saveDraftIndex(all)
    }

    static func deleteDraft(forDocumentID documentID: UUID) {
        var all = drafts()
        all.removeAll(where: { $0.documentID == documentID })
        try? saveDraftIndex(all)
    }

    static func importFiles(from urls: [URL]) async -> [ImportedNoticeDocument] {
        var imported: [ImportedNoticeDocument] = []
        for url in urls {
            if let item = await importFile(from: url) {
                imported.append(item)
            }
        }
        return imported
    }

    static func importFile(from sourceURL: URL) async -> ImportedNoticeDocument? {
        let id = UUID()
        let ext = sourceURL.pathExtension.lowercased()
        let incomingName = sourceURL.lastPathComponent
        let storedFileName = ext.isEmpty ? "\(id.uuidString)" : "\(id.uuidString).\(ext)"
        let textFileName = "\(id.uuidString).txt"

        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: sourceURL) else { return nil }
        let baseDir = ensureBaseDirectory()
        let storedURL = baseDir.appendingPathComponent(storedFileName)
        let textURL = baseDir.appendingPathComponent(textFileName)
        do {
            try data.write(to: storedURL, options: .atomic)
            let extractionResult = try? await ImportedNoticeTextExtractor.extractResult(from: storedURL)
            let extractedText = sanitizeExtractedText(extractionResult?.rawText ?? "")
            try extractedText.write(to: textURL, atomically: true, encoding: .utf8)

            let item = ImportedNoticeDocument(
                id: id,
                fileName: incomingName,
                fileExtension: ext,
                importedAt: Date(),
                fileSizeBytes: Int64(data.count),
                storedFileName: storedFileName,
                extractedTextFileName: textFileName,
                extractedTextLength: extractedText.count,
                extractedTextPreview: String(extractedText.prefix(140))
            )

            try saveDocumentIndex(withInsertedOrUpdated: item)
            saveExtraction(
                ImportedNoticeExtraction(
                    documentID: item.id,
                    rawText: extractedText,
                    sourceDescription: extractionResult?.sourceDescription ?? "文件",
                    warnings: extractionResult?.warnings ?? []
                )
            )
            return item
        } catch {
            try? FileManager.default.removeItem(at: storedURL)
            try? FileManager.default.removeItem(at: textURL)
            return nil
        }
    }

    /// 从分享扩展 App Group 目录接收原文件（即使暂时无法提取正文也先入库）。
    static func importInboundSharedFile(from inboundURL: URL, originalFileName: String?) async -> ImportedNoticeDocument? {
        guard let data = try? Data(contentsOf: inboundURL) else { return nil }
        let id = UUID()
        let ext = inboundURL.pathExtension.lowercased()
        let displayName = (originalFileName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? (originalFileName ?? inboundURL.lastPathComponent)
            : inboundURL.lastPathComponent
        let storedFileName = ext.isEmpty ? "\(id.uuidString)" : "\(id.uuidString).\(ext)"
        let textFileName = "\(id.uuidString).txt"
        let baseDir = ensureBaseDirectory()
        let storedURL = baseDir.appendingPathComponent(storedFileName)
        let textURL = baseDir.appendingPathComponent(textFileName)
        do {
            try data.write(to: storedURL, options: .atomic)
            let extractionResult = try? await ImportedNoticeTextExtractor.extractResult(from: storedURL)
            let extractedText = sanitizeExtractedText(extractionResult?.rawText ?? "")
            try extractedText.write(to: textURL, atomically: true, encoding: .utf8)
            let item = ImportedNoticeDocument(
                id: id,
                fileName: displayName,
                fileExtension: ext,
                importedAt: Date(),
                fileSizeBytes: Int64(data.count),
                storedFileName: storedFileName,
                extractedTextFileName: textFileName,
                extractedTextLength: extractedText.count,
                extractedTextPreview: String(extractedText.prefix(140))
            )
            try saveDocumentIndex(withInsertedOrUpdated: item)
            saveExtraction(
                ImportedNoticeExtraction(
                    documentID: item.id,
                    rawText: extractedText,
                    sourceDescription: extractionResult?.sourceDescription ?? "文件",
                    warnings: extractionResult?.warnings ?? []
                )
            )
            try? FileManager.default.removeItem(at: inboundURL)
            return item
        } catch {
            try? FileManager.default.removeItem(at: storedURL)
            try? FileManager.default.removeItem(at: textURL)
            return nil
        }
    }

    static func extractedText(for item: ImportedNoticeDocument) -> String? {
        let textURL = ensureBaseDirectory().appendingPathComponent(item.extractedTextFileName)
        guard let text = try? String(contentsOf: textURL, encoding: .utf8) else { return nil }
        let trimmed = sanitizeExtractedText(text)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func reextractText(for item: ImportedNoticeDocument) async -> ImportedNoticeReextractResult {
        let baseDir = ensureBaseDirectory()
        let fileURL = baseDir.appendingPathComponent(item.storedFileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failure("文件不存在，请重新导入后再试。")
        }
        let extracted = await ImportedNoticeTextExtractor.extractText(from: fileURL) ?? ""
        let sanitized = sanitizeExtractedText(extracted)
        if !sanitized.isEmpty {
            if let updated = updateExtractedText(for: item, text: sanitized) {
                return .success(updated)
            }
            return .failure("文本提取成功，但保存失败。")
        }
        return await cloudReextractText(for: item, fileURL: fileURL)
    }

    static func delete(_ item: ImportedNoticeDocument) {
        deleteDocument(id: item.id)
    }

    static func deleteDocument(id: UUID) {
        if let item = document(id: id) {
            let baseDir = ensureBaseDirectory()
            try? FileManager.default.removeItem(at: baseDir.appendingPathComponent(item.storedFileName))
            try? FileManager.default.removeItem(at: baseDir.appendingPathComponent(item.extractedTextFileName))
        }
        var all = documents()
        all.removeAll(where: { $0.id == id })
        try? saveDocumentIndex(all)
        deleteExtraction(forDocumentID: id)
        deleteDraft(forDocumentID: id)
    }

    private static func ensureBaseDirectory() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = root.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func indexURL() -> URL {
        ensureBaseDirectory().appendingPathComponent(indexFileName)
    }

    private static func extractionIndexURL() -> URL {
        ensureBaseDirectory().appendingPathComponent(extractionIndexFileName)
    }

    private static func draftIndexURL() -> URL {
        ensureBaseDirectory().appendingPathComponent(draftIndexFileName)
    }

    private static func loadDocumentIndex() throws -> [ImportedNoticeDocument] {
        let url = indexURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ImportedNoticeDocument].self, from: data)
    }

    private static func saveDocumentIndex(_ items: [ImportedNoticeDocument]) throws {
        let data = try JSONEncoder().encode(items)
        try data.write(to: indexURL(), options: .atomic)
    }

    private static func saveDocumentIndex(withInsertedOrUpdated item: ImportedNoticeDocument) throws {
        var all = documents()
        if let idx = all.firstIndex(where: { $0.id == item.id }) {
            all[idx] = item
        } else {
            all.insert(item, at: 0)
        }
        try saveDocumentIndex(all)
    }

    private static func loadExtractionIndex() throws -> [ImportedNoticeExtraction] {
        let url = extractionIndexURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ImportedNoticeExtraction].self, from: data)
    }

    private static func saveExtractionIndex(_ items: [ImportedNoticeExtraction]) throws {
        let data = try JSONEncoder().encode(items)
        try data.write(to: extractionIndexURL(), options: .atomic)
    }

    private static func loadDraftIndex() throws -> [ImportedNoticeDraft] {
        let url = draftIndexURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ImportedNoticeDraft].self, from: data)
    }

    private static func saveDraftIndex(_ items: [ImportedNoticeDraft]) throws {
        let data = try JSONEncoder().encode(items)
        try data.write(to: draftIndexURL(), options: .atomic)
    }

    private static func updateExtractedText(for item: ImportedNoticeDocument, text: String) -> ImportedNoticeDocument? {
        let trimmed = sanitizeExtractedText(text)
        guard !trimmed.isEmpty else { return nil }
        let baseDir = ensureBaseDirectory()
        let textURL = baseDir.appendingPathComponent(item.extractedTextFileName)
        do {
            try trimmed.write(to: textURL, atomically: true, encoding: .utf8)
            var all = list()
            guard let idx = all.firstIndex(where: { $0.id == item.id }) else { return nil }
            all[idx].extractedTextLength = trimmed.count
            all[idx].extractedTextPreview = String(trimmed.prefix(140))
            all[idx].processingStatus = .extracted
            try saveDocumentIndex(all)
            saveExtraction(
                ImportedNoticeExtraction(
                    documentID: item.id,
                    rawText: trimmed,
                    sourceDescription: "重新提取",
                    warnings: []
                )
            )
            return all[idx]
        } catch {
            return nil
        }
    }

    private static func sanitizeExtractedText(_ raw: String) -> String {
        let trimmed = raw
            .replacingOccurrences(of: "\u{0000}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return looksLikeEmbeddedFileStructure(trimmed) ? "" : trimmed
    }

    private static func looksLikeEmbeddedFileStructure(_ text: String) -> Bool {
        let head = String(text.prefix(512)).trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("%PDF-") || head.hasPrefix("PK\u{03}\u{04}") || head.hasPrefix("bplist00") {
            return true
        }
        let pdfMarkers = [" obj", "endobj", "xref", "trailer", "%%EOF"]
        let matchedPDFMarkers = pdfMarkers.filter { head.contains($0) }.count
        return matchedPDFMarkers >= 3
    }

    private static func cloudReextractText(for item: ImportedNoticeDocument, fileURL: URL) async -> ImportedNoticeReextractResult {
        let baseRaw = SafeMasterAPIConfiguration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseRaw.isEmpty else {
            return .failure("未配置云端地址，无法启用 AI 提取。")
        }
        guard let token = KeychainStore.safemasterAccessToken(),
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .failure("请先在「我的」页面登录 Apple，同步后再提取。")
        }
        do {
            let client = SafeMasterAPIClient(baseURL: baseRaw)
            let text = try await client.extractImportedText(
                accessToken: token,
                fileURL: fileURL,
                fileName: item.fileName,
                cleanWithAI: true
            )
            if let updated = updateExtractedText(for: item, text: text) {
                return .success(updated)
            }
            return .failure("云端提取成功，但写入本地失败。")
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
