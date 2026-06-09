//
//  ImportedWordTemplateStore.swift
//  安全大师
//

import Foundation

enum ImportedWordTemplateStore {
    enum StoreError: LocalizedError {
        case unsupportedFile
        case copyFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedFile:
                return "当前仅支持导入 .docx 空白模板。"
            case .copyFailed:
                return "无法保存模板文件，请稍后重试。"
            }
        }
    }

    private static let templatesKey = "safemaster.importedWordTemplates.v1"
    private static let folderName = "ImportedWordTemplates"

    static func load() -> [ImportedWordTemplate] {
        guard let data = UserDefaults.standard.data(forKey: templatesKey),
              let decoded = try? JSONDecoder().decode([ImportedWordTemplate].self, from: data)
        else { return [] }
        return decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func save(_ templates: [ImportedWordTemplate]) {
        guard let data = try? JSONEncoder().encode(templates.sorted { $0.updatedAt > $1.updatedAt }) else { return }
        UserDefaults.standard.set(data, forKey: templatesKey)
    }

    static func upsert(_ template: ImportedWordTemplate) {
        var templates = load()
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
        } else {
            templates.append(template)
        }
        save(templates)
    }

    static func delete(_ template: ImportedWordTemplate) {
        var templates = load()
        templates.removeAll { $0.id == template.id }
        save(templates)
        try? FileManager.default.removeItem(at: fileURL(for: template))
    }

    static func importTemplate(from sourceURL: URL) throws -> ImportedWordTemplate {
        guard sourceURL.pathExtension.lowercased() == "docx" else { throw StoreError.unsupportedFile }
        let folder = try templatesFolder()
        let id = UUID()
        let storedName = "\(id.uuidString).docx"
        let target = folder.appendingPathComponent(storedName)
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scoped { sourceURL.stopAccessingSecurityScopedResource() }
        }
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: sourceURL, to: target)
        } catch {
            throw StoreError.copyFailed
        }
        let result = try WordTemplateParser.parse(url: target)
        let template = ImportedWordTemplate(
            id: id,
            name: sourceURL.deletingPathExtension().lastPathComponent,
            originalFileName: sourceURL.lastPathComponent,
            storedFileName: storedName,
            placeholders: result.placeholders,
            createdAt: Date(),
            updatedAt: Date()
        )
        upsert(template)
        return template
    }

    static func fileURL(for template: ImportedWordTemplate) -> URL {
        (try? templatesFolder())?.appendingPathComponent(template.storedFileName)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(template.storedFileName)
    }

    private static func templatesFolder() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = base.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }
}

