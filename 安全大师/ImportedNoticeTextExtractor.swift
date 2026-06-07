//
//  ImportedNoticeTextExtractor.swift
//  安全大师
//

import Foundation
import Compression
import PDFKit
import UIKit
import Vision

struct ImportedNoticeTextExtractionResult {
    var rawText: String
    var sourceDescription: String
    var warnings: [String]
}

enum ImportedNoticeTextExtractor {
    private static let maxLocalDocxArchiveBytes = 8 * 1024 * 1024
    private static let maxLocalLegacyOfficeBytes = 2 * 1024 * 1024
    private static let maxLocalPDFOCRBytes = 20 * 1024 * 1024
    private static let minUsefulPDFTextCharacters = 80
    private static let maxPDFOCRPages = 5
    private static let maxPDFOCRDimension: CGFloat = 1600
    private static let maxDocxXMLBytes = 3 * 1024 * 1024
    private static let maxExtractedTextCharacters = 60_000

    static func extractText(from url: URL) async -> String? {
        (try? await extractResult(from: url))?.rawText
    }

    static func extractResult(from url: URL) async throws -> ImportedNoticeTextExtractionResult {
        let ext = url.pathExtension.lowercased()

        if ext == "pdf" {
            return await extractTextFromPDFWithOCRFallback(url: url)
        }

        if ext == "docx", fileSize(at: url) > maxLocalDocxArchiveBytes {
            return ImportedNoticeTextExtractionResult(rawText: "", sourceDescription: "Word", warnings: ["Word 文件较大，已跳过本地提取以避免卡顿"])
        }
        if ["doc", "rtf"].contains(ext), fileSize(at: url) > maxLocalLegacyOfficeBytes {
            return ImportedNoticeTextExtractionResult(rawText: "", sourceDescription: "Word/RTF", warnings: ["Office 文件较大，已跳过本地提取以避免卡顿"])
        }

        guard let data = try? Data(contentsOf: url) else {
            return ImportedNoticeTextExtractionResult(rawText: "", sourceDescription: "文件", warnings: ["无法读取文件内容"])
        }

        if let wrappedURL = resolveWrappedFileURL(from: data),
           wrappedURL.isFileURL,
           FileManager.default.fileExists(atPath: wrappedURL.path) {
            return try await extractResult(from: wrappedURL)
        }

        if ext == "docx" {
            if let docx = extractDocxText(from: data) {
                return ImportedNoticeTextExtractionResult(rawText: docx, sourceDescription: "Word", warnings: [])
            }
            return ImportedNoticeTextExtractionResult(rawText: "", sourceDescription: "Word", warnings: ["未能从 Word 文档中提取正文"])
        }

        if let office = extractOfficeText(from: data) {
            return ImportedNoticeTextExtractionResult(rawText: limitExtractedText(office), sourceDescription: "Word/RTF", warnings: [])
        }

        if isOfficeExtension(ext) {
            return ImportedNoticeTextExtractionResult(rawText: "", sourceDescription: "Word/RTF", warnings: ["未能从 Office 文档中提取正文"])
        }

        if let plain = decodeText(data) {
            return ImportedNoticeTextExtractionResult(rawText: plain, sourceDescription: "文本", warnings: [])
        }

        if isImageExtension(ext),
           let image = UIImage(data: data),
           let ocr = await recognizeText(from: image) {
            return ImportedNoticeTextExtractionResult(rawText: ocr, sourceDescription: "图片 OCR", warnings: [])
        }

        return ImportedNoticeTextExtractionResult(rawText: "", sourceDescription: "文件", warnings: ["未提取到文本"])
    }

    static func extractText(from data: Data, suggestedFileExtension ext: String = "") async -> String? {
        (try? await extractResult(from: data, suggestedFileExtension: ext))?.rawText
    }

    static func extractResult(
        from data: Data,
        suggestedFileExtension ext: String = ""
    ) async throws -> ImportedNoticeTextExtractionResult {
        let normalizedExt = ext.lowercased()

        if normalizedExt == "pdf" {
            return await extractTextFromPDFWithOCRFallback(data: data)
        }

        if let wrappedURL = resolveWrappedFileURL(from: data),
           wrappedURL.isFileURL,
           FileManager.default.fileExists(atPath: wrappedURL.path) {
            return try await extractResult(from: wrappedURL)
        }

        if normalizedExt == "docx" || (normalizedExt.isEmpty && isZipData(data)) {
            if data.count > maxLocalDocxArchiveBytes {
                return ImportedNoticeTextExtractionResult(rawText: "", sourceDescription: "Word", warnings: ["Word 文件较大，已跳过本地提取以避免卡顿"])
            }
            if let docx = extractDocxText(from: data) {
                return ImportedNoticeTextExtractionResult(rawText: docx, sourceDescription: "Word", warnings: [])
            }
            if normalizedExt == "docx" {
                return ImportedNoticeTextExtractionResult(rawText: "", sourceDescription: "Word", warnings: ["未能从 Word 文档中提取正文"])
            }
        }

        if data.count <= maxLocalLegacyOfficeBytes, let office = extractOfficeText(from: data) {
            return ImportedNoticeTextExtractionResult(rawText: office, sourceDescription: "Word/RTF", warnings: [])
        }

        if isOfficeExtension(normalizedExt) {
            return ImportedNoticeTextExtractionResult(rawText: "", sourceDescription: "Word/RTF", warnings: ["未能从 Office 文档中提取正文"])
        }

        if let plain = decodeText(data) {
            return ImportedNoticeTextExtractionResult(rawText: plain, sourceDescription: "文本", warnings: [])
        }

        if isImageExtension(normalizedExt),
           let image = UIImage(data: data),
           let ocr = await recognizeText(from: image) {
            return ImportedNoticeTextExtractionResult(rawText: ocr, sourceDescription: "图片 OCR", warnings: [])
        }

        return ImportedNoticeTextExtractionResult(rawText: "", sourceDescription: "数据", warnings: ["未提取到文本"])
    }

    static func extractTextFromPDF(url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        let text = document.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    static func extractTextFromPDF(data: Data) -> String? {
        guard let document = PDFDocument(data: data) else { return nil }
        let text = document.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    static func extractTextFromPDFWithOCRFallback(url: URL) async -> ImportedNoticeTextExtractionResult {
        guard fileSize(at: url) <= maxLocalPDFOCRBytes else {
            let text = extractTextFromPDF(url: url) ?? ""
            if text.count >= minUsefulPDFTextCharacters {
                return ImportedNoticeTextExtractionResult(rawText: limitExtractedText(text), sourceDescription: "文字型 PDF", warnings: [])
            }
            return ImportedNoticeTextExtractionResult(rawText: "", sourceDescription: "PDF", warnings: ["PDF 文件较大，已跳过本地 OCR 以避免卡顿"])
        }
        guard let document = PDFDocument(url: url) else {
            return ImportedNoticeTextExtractionResult(rawText: "", sourceDescription: "PDF", warnings: ["无法打开 PDF"])
        }
        return await extractTextFromPDFWithOCRFallback(document: document)
    }

    static func extractTextFromPDFWithOCRFallback(data: Data) async -> ImportedNoticeTextExtractionResult {
        guard data.count <= maxLocalPDFOCRBytes else {
            let text = extractTextFromPDF(data: data) ?? ""
            if text.count >= minUsefulPDFTextCharacters {
                return ImportedNoticeTextExtractionResult(rawText: limitExtractedText(text), sourceDescription: "文字型 PDF", warnings: [])
            }
            return ImportedNoticeTextExtractionResult(rawText: "", sourceDescription: "PDF", warnings: ["PDF 文件较大，已跳过本地 OCR 以避免卡顿"])
        }
        guard let document = PDFDocument(data: data) else {
            return ImportedNoticeTextExtractionResult(rawText: "", sourceDescription: "PDF", warnings: ["无法打开 PDF"])
        }
        return await extractTextFromPDFWithOCRFallback(document: document)
    }

    private static func extractTextFromPDFWithOCRFallback(document: PDFDocument) async -> ImportedNoticeTextExtractionResult {
        let textLayer = document.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if textLayer.count >= minUsefulPDFTextCharacters,
           !looksLikePDFStructureText(textLayer) {
            return ImportedNoticeTextExtractionResult(rawText: limitExtractedText(textLayer), sourceDescription: "文字型 PDF", warnings: [])
        }

        var warnings: [String] = []
        var pageTexts: [String] = []
        let pageCount = min(document.pageCount, maxPDFOCRPages)
        if document.pageCount > maxPDFOCRPages {
            warnings.append("PDF 页数较多，仅 OCR 前 \(maxPDFOCRPages) 页，请核对完整性")
        }

        for pageIndex in 0..<pageCount {
            guard let page = document.page(at: pageIndex),
                  let image = renderPDFPage(page) else {
                warnings.append("第 \(pageIndex + 1) 页渲染失败")
                continue
            }
            if let ocrText = await recognizeText(from: image),
               !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pageTexts.append(ocrText)
            } else {
                warnings.append("第 \(pageIndex + 1) 页 OCR 未识别到文本")
            }
        }

        let ocrText = limitExtractedText(pageTexts.joined(separator: "\n"))
        if !ocrText.isEmpty {
            return ImportedNoticeTextExtractionResult(rawText: ocrText, sourceDescription: "扫描型 PDF OCR", warnings: warnings)
        }
        if !textLayer.isEmpty, !looksLikePDFStructureText(textLayer) {
            warnings.append("OCR 未提取到有效文本，已保留 PDF 文字层短文本")
            return ImportedNoticeTextExtractionResult(rawText: limitExtractedText(textLayer), sourceDescription: "PDF", warnings: warnings)
        }
        warnings.append("OCR 未提取到有效文本")
        return ImportedNoticeTextExtractionResult(rawText: "", sourceDescription: "PDF OCR", warnings: warnings)
    }

    private static func renderPDFPage(_ page: PDFPage) -> UIImage? {
        let pageRect = page.bounds(for: .mediaBox)
        guard pageRect.width > 0, pageRect.height > 0 else { return nil }
        let scale = min(maxPDFOCRDimension / pageRect.width, maxPDFOCRDimension / pageRect.height, 1)
        let renderSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: renderSize, format: format).image { rendererContext in
            UIColor.white.setFill()
            rendererContext.fill(CGRect(origin: .zero, size: renderSize))
            let context = rendererContext.cgContext
            context.saveGState()
            context.translateBy(x: 0, y: renderSize.height)
            context.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
        }
    }

    static func extractOfficeText(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return extractOfficeText(from: data)
    }

    static func extractOfficeText(from data: Data) -> String? {
        guard data.count <= maxLocalLegacyOfficeBytes else { return nil }
        let types: [NSAttributedString.DocumentType] = [
            NSAttributedString.DocumentType(rawValue: "com.microsoft.word.doc"),
            .rtf
        ]
        for type in types {
            if let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: type],
                documentAttributes: nil
            ) {
                let text = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return limitExtractedText(text) }
            }
        }
        if let attributed = try? NSAttributedString(data: data, options: [:], documentAttributes: nil) {
            let text = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return limitExtractedText(text) }
        }
        return nil
    }

    static func extractDocxText(from data: Data) -> String? {
        guard data.count <= maxLocalDocxArchiveBytes else { return nil }
        guard let xmlData = zipEntryData(named: "word/document.xml", in: data),
              xmlData.count <= maxDocxXMLBytes,
              let xml = String(data: xmlData, encoding: .utf8) else {
            return nil
        }
        let text = docxPlainText(fromDocumentXML: xml)
        return text.isEmpty ? nil : limitExtractedText(text)
    }

    static func decodeText(_ data: Data) -> String? {
        if isLikelyBinaryData(data) {
            return nil
        }
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        let encodings: [String.Encoding] = [.utf8, .unicode, .utf16, .utf16LittleEndian, .utf16BigEndian, gb18030]
        for encoding in encodings {
            if let text = String(data: data, encoding: encoding)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                return text
            }
        }
        return nil
    }

    static func readTextFile(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decodeText(data)
    }

    static func recognizeText(from image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: (text?.isEmpty == false) ? text : nil)
            }
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.recognitionLevel = .accurate
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    static func resolveWrappedFileURL(from data: Data) -> URL? {
        if let plistURL = resolveFileURLFromPropertyListData(data) {
            return plistURL
        }
        let candidates = [
            String(data: data, encoding: .utf8),
            String(data: data, encoding: .unicode),
            String(data: data, encoding: .utf16),
            String(data: data, encoding: .isoLatin1),
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }

        for raw in candidates {
            if let resolved = resolveLikelyFileURL(from: raw) {
                return resolved
            }
        }
        return nil
    }

    static func resolveLikelyFileURL(from raw: String) -> URL? {
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }

        if let fileRange = candidate.range(of: "file://") {
            let tail = String(candidate[fileRange.lowerBound...])
            if let url = URL(string: tail), url.isFileURL {
                return url
            }
        }
        if let url = URL(string: candidate), url.isFileURL {
            return url
        }
        if candidate.hasPrefix("/") {
            let decoded = candidate.removingPercentEncoding ?? candidate
            let url = URL(fileURLWithPath: decoded)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        if let tmpRange = candidate.range(of: "/tmp/") {
            let path = String(candidate[tmpRange.lowerBound...])
            let decoded = path.removingPercentEncoding ?? path
            let url = URL(fileURLWithPath: decoded)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    static func looksLikeFileLocatorString(_ text: String) -> Bool {
        text.hasPrefix("bplist00") || text.contains("file://") || text.contains("/tmp/fileCache/")
    }

    private static func resolveFileURLFromPropertyListData(_ data: Data) -> URL? {
        guard data.count >= 8 else { return nil }
        if data.starts(with: Data("bplist00".utf8)) == false,
           data.starts(with: Data("<?xml".utf8)) == false {
            return nil
        }
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let raw = firstFileLocatorString(in: object),
              let url = resolveLikelyFileURL(from: raw) else {
            return nil
        }
        return url
    }

    private static func firstFileLocatorString(in object: Any) -> String? {
        if let s = object as? String, looksLikeFileLocatorString(s) {
            return s
        }
        if let arr = object as? [Any] {
            for value in arr {
                if let found = firstFileLocatorString(in: value) { return found }
            }
            return nil
        }
        if let dict = object as? [AnyHashable: Any] {
            for value in dict.values {
                if let found = firstFileLocatorString(in: value) { return found }
            }
            return nil
        }
        return nil
    }

    private static func isLikelyBinaryPropertyList(_ data: Data) -> Bool {
        data.count >= 8 && data.starts(with: Data("bplist00".utf8))
    }

    private static func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values?.fileSize {
            return Int64(size)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.size] as? Int64 ?? 0
    }

    private static func limitExtractedText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxExtractedTextCharacters else { return trimmed }
        return String(trimmed.prefix(maxExtractedTextCharacters))
    }

    private static func isLikelyBinaryData(_ data: Data) -> Bool {
        if data.isEmpty { return false }
        if isLikelyBinaryPropertyList(data) || isZipData(data) || data.starts(with: Data("%PDF".utf8)) {
            return true
        }
        let imageHeaders: [Data] = [
            Data([0xFF, 0xD8, 0xFF]),
            Data([0x89, 0x50, 0x4E, 0x47]),
            Data([0x47, 0x49, 0x46, 0x38])
        ]
        if imageHeaders.contains(where: { data.starts(with: $0) }) {
            return true
        }
        let sample = data.prefix(min(data.count, 4096))
        let nullCount = sample.filter { $0 == 0 }.count
        return nullCount > max(8, sample.count / 20)
    }

    private static func looksLikePDFStructureText(_ text: String) -> Bool {
        let head = String(text.prefix(512)).trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("%PDF-") {
            return true
        }
        let pdfMarkers = [" obj", "endobj", "xref", "trailer", "%%EOF"]
        return pdfMarkers.filter { head.contains($0) }.count >= 3
    }

    private static func isZipData(_ data: Data) -> Bool {
        data.count >= 4 && data.starts(with: Data([0x50, 0x4B, 0x03, 0x04]))
    }

    private static func isOfficeExtension(_ ext: String) -> Bool {
        ["doc", "docx", "rtf"].contains(ext)
    }

    private static func isImageExtension(_ ext: String) -> Bool {
        ["jpg", "jpeg", "png", "heic", "heif", "webp", "bmp", "tiff"].contains(ext)
    }

    private static func zipEntryData(named targetName: String, in data: Data) -> Data? {
        guard data.count > 22 else { return nil }
        guard let eocd = findEndOfCentralDirectory(in: data) else { return nil }
        let entryCount = Int(readUInt16LE(data, at: eocd + 10) ?? 0)
        let centralDirectoryOffset = Int(readUInt32LE(data, at: eocd + 16) ?? 0)
        var cursor = centralDirectoryOffset

        for _ in 0..<entryCount {
            guard cursor + 46 <= data.count,
                  readUInt32LE(data, at: cursor) == 0x02014B50 else {
                return nil
            }
            let compressionMethod = Int(readUInt16LE(data, at: cursor + 10) ?? 0)
            let compressedSize = Int(readUInt32LE(data, at: cursor + 20) ?? 0)
            let uncompressedSize = Int(readUInt32LE(data, at: cursor + 24) ?? 0)
            let nameLength = Int(readUInt16LE(data, at: cursor + 28) ?? 0)
            let extraLength = Int(readUInt16LE(data, at: cursor + 30) ?? 0)
            let commentLength = Int(readUInt16LE(data, at: cursor + 32) ?? 0)
            let localHeaderOffset = Int(readUInt32LE(data, at: cursor + 42) ?? 0)
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLength

            guard nameEnd <= data.count else { return nil }
            let entryName = String(data: data[nameStart..<nameEnd], encoding: .utf8) ?? ""
            if entryName == targetName {
                guard compressedSize <= maxDocxXMLBytes,
                      uncompressedSize <= maxDocxXMLBytes else {
                    return nil
                }
                return zipEntryPayload(
                    in: data,
                    localHeaderOffset: localHeaderOffset,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    compressionMethod: compressionMethod
                )
            }
            cursor = nameEnd + extraLength + commentLength
        }
        return nil
    }

    private static func zipEntryPayload(
        in data: Data,
        localHeaderOffset: Int,
        compressedSize: Int,
        uncompressedSize: Int,
        compressionMethod: Int
    ) -> Data? {
        guard localHeaderOffset + 30 <= data.count,
              readUInt32LE(data, at: localHeaderOffset) == 0x04034B50 else {
            return nil
        }
        let nameLength = Int(readUInt16LE(data, at: localHeaderOffset + 26) ?? 0)
        let extraLength = Int(readUInt16LE(data, at: localHeaderOffset + 28) ?? 0)
        let payloadStart = localHeaderOffset + 30 + nameLength + extraLength
        let payloadEnd = payloadStart + compressedSize
        guard payloadStart >= 0, payloadEnd <= data.count else { return nil }
        let payload = Data(data[payloadStart..<payloadEnd])

        switch compressionMethod {
        case 0:
            return payload
        case 8:
            return inflateDeflate(payload, expectedSize: uncompressedSize)
        default:
            return nil
        }
    }

    private static func inflateDeflate(_ data: Data, expectedSize: Int) -> Data? {
        guard !data.isEmpty, expectedSize > 0 else { return nil }
        var output = Data(count: expectedSize)
        let decodedCount = output.withUnsafeMutableBytes { outputBuffer in
            data.withUnsafeBytes { inputBuffer in
                compression_decode_buffer(
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    expectedSize,
                    inputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decodedCount > 0 else { return nil }
        output.removeSubrange(decodedCount..<output.count)
        return output
    }

    private static func findEndOfCentralDirectory(in data: Data) -> Int? {
        let minimumOffset = max(0, data.count - 65_557)
        guard data.count >= 22, minimumOffset < data.count - 3 else { return nil }
        var cursor = data.count - 22
        while cursor >= minimumOffset {
            if readUInt32LE(data, at: cursor) == 0x06054B50 {
                return cursor
            }
            if cursor == 0 { break }
            cursor -= 1
        }
        return nil
    }

    private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func docxPlainText(fromDocumentXML xml: String) -> String {
        let withBreaks = xml
            .replacingOccurrences(of: "</w:p>", with: "\n")
            .replacingOccurrences(of: "<w:tab/>", with: "\t")
            .replacingOccurrences(of: "<w:br/>", with: "\n")
        let withoutTags = withBreaks.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        return decodeXMLEntities(withoutTags)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeXMLEntities(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
