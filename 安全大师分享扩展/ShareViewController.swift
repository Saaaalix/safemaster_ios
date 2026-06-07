//
//  ShareViewController.swift
//  安全大师分享扩展
//

import Foundation
import MobileCoreServices
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private static let appGroupID = "group.com.safeMaster.aqds.share"
    private static let pendingTextKey = "safemaster.share.pendingText"
    private static let pendingFileNameKey = "safemaster.share.pendingFileName"
    private static let pendingInboundFileNameKey = "safemaster.share.pendingInboundFileName"
    private static let pendingInboundOriginalNameKey = "safemaster.share.pendingInboundOriginalName"
    private static let pendingTimestampKey = "safemaster.share.pendingAt"
    private static let pasteboardKeyPrefix = "[safemaster-share]"
    private static let sharedImportDirectoryName = "shared-import"
    private static let sharedInboundDirectoryName = "shared-inbound-files"
    private static let maxPasteboardCharacters = 180_000
    private static let maxImportCharacters = 500_000

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = .secondaryLabel
        label.text = "正在导入到安全大师…"
        return label
    }()
    private let doneButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("完成", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        button.isHidden = true
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        view.addSubview(doneButton)
        doneButton.addTarget(self, action: #selector(didTapDone), for: .touchUpInside)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -18),
            doneButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            doneButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task {
            await importSharedPayloadAndFinish()
        }
    }

    @MainActor
    private func importSharedPayloadAndFinish() async {
        let providers = extractProvidersFromExtensionItems()
        if hasInboundFileCandidate(providers: providers),
           await saveInboundFileToAppGroup(providers: providers) {
            statusLabel.text = "已将原文件保存到导入箱。\n请切回安全大师手动读取或识别。"
            finishAfterDelay()
            return
        }
        let text = await extractTextFromExtensionItems(providers: providers)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if await saveInboundFileToAppGroup(providers: providers) {
                statusLabel.text = "正文暂不可直接读取，已将原文件保存到导入箱。\n请切回安全大师继续处理。"
                finishAfterDelay()
            } else {
                statusLabel.text = "未识别到可导入内容。请改为分享文本、PDF或清晰图片。"
                showManualClose()
            }
            return
        }

        if saveToAppGroup(trimmed) {
            statusLabel.text = "已发送到安全大师，请切回 App 继续识别。"
            finishAfterDelay()
            return
        }

        if saveToPasteboard(trimmed) {
            statusLabel.text = "共享容器不可用，已走兜底导入。\n请切回安全大师继续识别。"
            finishAfterDelay()
        } else {
            statusLabel.text = "导入失败：共享容器不可用且系统拒绝剪贴板访问。\n请在主 App 与分享扩展都启用同一 App Group：\(Self.appGroupID)"
            showManualClose()
        }
    }

    private func finishAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func showManualClose() {
        doneButton.isHidden = false
    }

    @objc
    private func didTapDone() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func saveToAppGroup(_ text: String) -> Bool {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) else {
            return false
        }
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return false }
        let payload = limitedTransportText(text)
        guard !payload.isEmpty else { return false }

        if let fileName = writeSharedPayload(payload, containerURL: containerURL) {
            defaults.set(fileName, forKey: Self.pendingFileNameKey)
            defaults.removeObject(forKey: Self.pendingTextKey)
            defaults.set(Date().timeIntervalSince1970, forKey: Self.pendingTimestampKey)
            return true
        }

        // 仅在文件写入失败时才降级写小文本，避免触发 UserDefaults 4MB 限制。
        defaults.set(String(payload.prefix(40_000)), forKey: Self.pendingTextKey)
        defaults.removeObject(forKey: Self.pendingFileNameKey)
        defaults.set(Date().timeIntervalSince1970, forKey: Self.pendingTimestampKey)
        let verify = defaults.string(forKey: Self.pendingTextKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !verify.isEmpty
    }

    private func saveToPasteboard(_ text: String) -> Bool {
        let wrapped = Self.pasteboardKeyPrefix + limitedTransportText(text, maxChars: Self.maxPasteboardCharacters)
        UIPasteboard.general.string = wrapped
        let verify = UIPasteboard.general.string ?? ""
        return verify == wrapped
    }

    private func extractProvidersFromExtensionItems() -> [NSItemProvider] {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return [] }
        return items.flatMap { $0.attachments ?? [] }
    }

    private func extractTextFromExtensionItems(providers: [NSItemProvider]) async -> String {
        guard !providers.isEmpty else { return "" }

        // 优先文本，失败后再尝试文件/PDF/图片 OCR。
        for provider in providers {
            if let text = await loadPlainText(from: provider), !text.isEmpty {
                return text
            }
        }
        for provider in providers {
            if let text = await loadTextFromFile(from: provider), !text.isEmpty {
                return text
            }
        }
        for provider in providers {
            if let text = await loadTextFromPDF(from: provider), !text.isEmpty {
                return text
            }
        }
        for provider in providers {
            if let text = await loadTextFromImageOCR(from: provider), !text.isEmpty {
                return text
            }
        }
        return ""
    }

    private func loadPlainText(from provider: NSItemProvider) async -> String? {
        let candidates = [
            UTType.plainText.identifier,
            UTType.text.identifier,
            UTType.utf8PlainText.identifier,
        ]
        for type in candidates where provider.hasItemConformingToTypeIdentifier(type) {
            if let value = await loadItem(provider: provider, typeIdentifier: type) {
                if let text = value as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { continue }
                    if let fileURL = ImportedNoticeTextExtractor.resolveLikelyFileURL(from: trimmed),
                       let extracted = await extractTextFromAnyFile(url: fileURL),
                       !extracted.isEmpty {
                        return extracted
                    }
                    if ImportedNoticeTextExtractor.looksLikeFileLocatorString(trimmed) {
                        continue
                    }
                    return trimmed
                } else if let url = value as? URL,
                          let text = await extractTextFromAnyFile(url: url),
                          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                } else if let data = value as? Data,
                          let text = String(data: data, encoding: .utf8),
                          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if ImportedNoticeTextExtractor.looksLikeFileLocatorString(trimmed) {
                        continue
                    }
                    return trimmed
                }
            }
        }
        return nil
    }

    private func loadTextFromFile(from provider: NSItemProvider) async -> String? {
        let fileURLTypes = [
            UTType.fileURL.identifier,
            UTType.url.identifier,
            "public.url",
        ]
        guard let matchedType = fileURLTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) else {
            return nil
        }
        let fileURL: URL?
        if let copiedURL = await loadFileURL(provider: provider, typeIdentifier: matchedType) {
            fileURL = copiedURL
        } else if let value = await loadItem(provider: provider, typeIdentifier: matchedType) {
            if let url = value as? URL {
                fileURL = url
            } else if let data = value as? Data {
                fileURL = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                fileURL = nil
            }
        } else {
            fileURL = nil
        }
        guard let fileURL else { return nil }

        return await extractTextFromAnyFile(url: fileURL)
    }

    private func loadTextFromPDF(from provider: NSItemProvider) async -> String? {
        let pdfTypes = [UTType.pdf.identifier, "com.adobe.pdf", "public.data"]
        for type in pdfTypes where provider.hasItemConformingToTypeIdentifier(type) {
            if let url = await loadFileURL(provider: provider, typeIdentifier: type) {
                let result = await ImportedNoticeTextExtractor.extractTextFromPDFWithOCRFallback(url: url)
                if !result.rawText.isEmpty {
                    return result.rawText
                }
            }
            if let data = await loadData(provider: provider, typeIdentifier: type) {
                let result = await ImportedNoticeTextExtractor.extractTextFromPDFWithOCRFallback(data: data)
                if !result.rawText.isEmpty {
                    return result.rawText
                }
            }
        }
        return nil
    }

    private func loadTextFromImageOCR(from provider: NSItemProvider) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { return nil }
        if let data = await loadData(provider: provider, typeIdentifier: UTType.image.identifier),
           let image = UIImage(data: data),
           let text = await ImportedNoticeTextExtractor.recognizeText(from: image),
           !text.isEmpty {
            return text
        }
        if let url = await loadFileURL(provider: provider, typeIdentifier: UTType.image.identifier),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data),
           let text = await ImportedNoticeTextExtractor.recognizeText(from: image),
           !text.isEmpty {
            return text
        }
        return nil
    }

    private func loadItem(provider: NSItemProvider, typeIdentifier: String) async -> NSSecureCoding? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: item as NSSecureCoding?)
            }
        }
    }

    private func loadFileURL(provider: NSItemProvider, typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                do {
                    if FileManager.default.fileExists(atPath: tmp.path) {
                        try FileManager.default.removeItem(at: tmp)
                    }
                    try FileManager.default.copyItem(at: url, to: tmp)
                    continuation.resume(returning: tmp)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadData(provider: NSItemProvider, typeIdentifier: String) async -> Data? {
        if let url = await loadFileURL(provider: provider, typeIdentifier: typeIdentifier),
           let data = try? Data(contentsOf: url) {
            return data
        }
        if let item = await loadItem(provider: provider, typeIdentifier: typeIdentifier) {
            if let data = item as? Data {
                return data
            }
            if let url = item as? URL {
                return try? Data(contentsOf: url)
            }
        }
        return nil
    }

    private func extractTextFromAnyFile(url: URL) async -> String? {
        await ImportedNoticeTextExtractor.extractText(from: url)
    }

    private func limitedTransportText(_ text: String, maxChars: Int? = nil) -> String {
        let maxChars = maxChars ?? Self.maxImportCharacters
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        return String(trimmed[..<end])
    }

    private func writeSharedPayload(_ text: String, containerURL: URL) -> String? {
        let dir = containerURL.appendingPathComponent(Self.sharedImportDirectoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileName = "pending-\(UUID().uuidString).txt"
            let fileURL = dir.appendingPathComponent(fileName)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileName
        } catch {
            return nil
        }
    }

    private func saveInboundFileToAppGroup(providers: [NSItemProvider]) async -> Bool {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) else {
            return false
        }
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return false }
        guard let file = await extractFirstInboundFile(providers: providers) else { return false }

        let dir = containerURL.appendingPathComponent(Self.sharedInboundDirectoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let ext = file.url.pathExtension.lowercased()
            let fileName = ext.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(ext)"
            let target = dir.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: file.url, to: target)
            defaults.set(fileName, forKey: Self.pendingInboundFileNameKey)
            defaults.set(file.originalName, forKey: Self.pendingInboundOriginalNameKey)
            defaults.set(Date().timeIntervalSince1970, forKey: Self.pendingTimestampKey)
            defaults.removeObject(forKey: Self.pendingTextKey)
            defaults.removeObject(forKey: Self.pendingFileNameKey)
            return true
        } catch {
            return false
        }
    }

    private func extractFirstInboundFile(providers: [NSItemProvider]) async -> (url: URL, originalName: String)? {
        let candidateTypes = [
            UTType.fileURL.identifier,
            UTType.url.identifier,
            "public.url",
            UTType.pdf.identifier,
            "com.adobe.pdf",
            UTType.image.identifier,
            "com.microsoft.word.doc",
            "org.openxmlformats.wordprocessingml.document",
            "public.data"
        ]
        for provider in providers {
            for type in candidateTypes where provider.hasItemConformingToTypeIdentifier(type) {
                if type == UTType.url.identifier || type == "public.url" {
                    if let resolvedFromItem = await loadRealFileURLFromItem(provider: provider, typeIdentifier: type) {
                        return (resolvedFromItem, buildOriginalFileName(provider: provider, copiedURL: resolvedFromItem))
                    }
                }
                if let url = await loadFileURL(provider: provider, typeIdentifier: type) {
                    let resolved = resolveActualInboundFileURL(from: url)
                    return (resolved, buildOriginalFileName(provider: provider, copiedURL: resolved))
                }
                if let value = await loadItem(provider: provider, typeIdentifier: type),
                   let url = value as? URL {
                    let resolved = resolveActualInboundFileURL(from: url)
                    return (resolved, buildOriginalFileName(provider: provider, copiedURL: resolved))
                }
            }
        }
        return nil
    }

    private func loadRealFileURLFromItem(provider: NSItemProvider, typeIdentifier: String) async -> URL? {
        guard let item = await loadItem(provider: provider, typeIdentifier: typeIdentifier) else { return nil }
        if let url = item as? URL, url.isFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let text = item as? String,
           let url = ImportedNoticeTextExtractor.resolveLikelyFileURL(from: text),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let data = item as? Data,
           let url = ImportedNoticeTextExtractor.resolveWrappedFileURL(from: data),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    private func hasInboundFileCandidate(providers: [NSItemProvider]) -> Bool {
        let candidateTypes = [
            UTType.fileURL.identifier,
            UTType.url.identifier,
            "public.url",
            UTType.pdf.identifier,
            "com.adobe.pdf",
            UTType.image.identifier,
            "com.microsoft.word.doc",
            "org.openxmlformats.wordprocessingml.document",
            "public.data"
        ]
        return providers.contains { provider in
            candidateTypes.contains(where: { provider.hasItemConformingToTypeIdentifier($0) })
        }
    }

    private func buildOriginalFileName(provider: NSItemProvider, copiedURL: URL) -> String {
        let ext = copiedURL.pathExtension
        if let suggested = provider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !suggested.isEmpty,
           !isGenericURLLabel(suggested) {
            if ext.isEmpty || suggested.lowercased().hasSuffix(".\(ext.lowercased())") {
                return suggested
            }
            return "\(suggested).\(ext)"
        }
        let raw = copiedURL.lastPathComponent
        if raw.count > 37 {
            let prefix = String(raw.prefix(36))
            if UUID(uuidString: prefix) != nil, raw[raw.index(raw.startIndex, offsetBy: 36)] == "-" {
                let start = raw.index(raw.startIndex, offsetBy: 37)
                return String(raw[start...])
            }
        }
        return raw
    }

    private func isGenericURLLabel(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
        return normalized == "file url" || normalized == "url"
    }

    /// 某些来源（如 public.url）给到的是一个小文本文件，内容才是真实 file:// 路径。
    /// 这里尝试把“URL描述文件”还原成真实文件 URL。
    private func resolveActualInboundFileURL(from candidate: URL) -> URL {
        if candidate.isFileURL, FileManager.default.fileExists(atPath: candidate.path) {
            if let data = try? Data(contentsOf: candidate),
               data.count > 0, data.count <= 8_192,
               let resolved = ImportedNoticeTextExtractor.resolveWrappedFileURL(from: data),
               FileManager.default.fileExists(atPath: resolved.path) {
                return resolved
            }
            return candidate
        }
        return candidate
    }

}
