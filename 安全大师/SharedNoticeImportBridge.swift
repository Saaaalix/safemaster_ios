//
//  SharedNoticeImportBridge.swift
//  安全大师
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum SharedNoticeImportBridge {
    static let appGroupID = "group.com.safeMaster.aqds.share"
    static let pendingTextKey = "safemaster.share.pendingText"
    static let pendingFileNameKey = "safemaster.share.pendingFileName"
    static let pendingInboundFileNameKey = "safemaster.share.pendingInboundFileName"
    static let pendingInboundOriginalNameKey = "safemaster.share.pendingInboundOriginalName"
    static let pendingTimestampKey = "safemaster.share.pendingAt"
    static let pasteboardKeyPrefix = "[safemaster-share]"
    static let sharedImportDirectoryName = "shared-import"
    static let sharedInboundDirectoryName = "shared-inbound-files"

    enum PendingImport {
        case text(String)
        case fileStored(fileName: String)
    }

    /// 默认不读系统剪贴板，避免 App 每次激活触发 iOS 粘贴授权弹窗。
    static func consumePendingText(includePasteboardFallback: Bool = false) async -> String? {
        if case .text(let text) = await consumePendingImport(includePasteboardFallback: includePasteboardFallback) {
            return text
        }
        return nil
    }

    static func consumePendingImport(includePasteboardFallback: Bool = false) async -> PendingImport? {
        if let result = await consumeFromAppGroup() {
            return result
        }
        guard includePasteboardFallback else { return nil }
        if let text = consumeFromPasteboard() {
            return .text(text)
        }
        return nil
    }

    private static func consumeFromAppGroup() async -> PendingImport? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }

        if let fileName = defaults.string(forKey: pendingFileNameKey),
           let text = consumeFromSharedFile(containerURL: containerURL, fileName: fileName) {
            defaults.removeObject(forKey: pendingFileNameKey)
            defaults.removeObject(forKey: pendingInboundFileNameKey)
            defaults.removeObject(forKey: pendingInboundOriginalNameKey)
            defaults.removeObject(forKey: pendingTextKey)
            defaults.removeObject(forKey: pendingTimestampKey)
            return .text(text)
        }

        if let inboundFileName = defaults.string(forKey: pendingInboundFileNameKey) {
            let originalName = defaults.string(forKey: pendingInboundOriginalNameKey)
            let inboundURL = containerURL
                .appendingPathComponent(sharedInboundDirectoryName, isDirectory: true)
                .appendingPathComponent(inboundFileName)
            let imported = await ImportedNoticeDocumentStore.importInboundSharedFile(
                from: inboundURL,
                originalFileName: originalName
            )
            if imported == nil {
                try? FileManager.default.removeItem(at: inboundURL)
            }
            defaults.removeObject(forKey: pendingFileNameKey)
            defaults.removeObject(forKey: pendingInboundFileNameKey)
            defaults.removeObject(forKey: pendingInboundOriginalNameKey)
            defaults.removeObject(forKey: pendingTextKey)
            defaults.removeObject(forKey: pendingTimestampKey)
            if let imported {
                return .fileStored(fileName: imported.fileName)
            }
            return nil
        }

        let text = defaults.string(forKey: pendingTextKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        defaults.removeObject(forKey: pendingFileNameKey)
        defaults.removeObject(forKey: pendingInboundFileNameKey)
        defaults.removeObject(forKey: pendingInboundOriginalNameKey)
        defaults.removeObject(forKey: pendingTextKey)
        defaults.removeObject(forKey: pendingTimestampKey)
        if text.isEmpty { return nil }
        return .text(text)
    }

    private static func consumeFromSharedFile(containerURL: URL, fileName: String) -> String? {
        let dir = containerURL.appendingPathComponent(sharedImportDirectoryName, isDirectory: true)
        let fileURL = dir.appendingPathComponent(fileName)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            return nil
        }
        return text
    }

    private static func consumeFromPasteboard() -> String? {
#if canImport(UIKit)
        let pb = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard pb.hasPrefix(pasteboardKeyPrefix) else { return nil }
        let text = String(pb.dropFirst(pasteboardKeyPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            UIPasteboard.general.string = ""
            return text
        }
#endif
        return nil
    }
}
