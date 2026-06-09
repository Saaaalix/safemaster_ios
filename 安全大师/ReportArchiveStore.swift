//
//  ReportArchiveStore.swift
//  安全大师
//

import Foundation

struct ArchivedReport: Identifiable, Codable, Hashable {
    let id: UUID
    var fileName: String
    var kindTitle: String
    var projectName: String
    var recordCount: Int
    var archivedAt: Date

    var fileExtension: String {
        URL(fileURLWithPath: fileName).pathExtension.lowercased()
    }
}

enum ReportArchiveStore {
    private static let storageKey = "safemaster.reportArchive.items.v1"
    private static let folderName = "ArchivedReports"

    static func allReports() -> [ArchivedReport] {
        load()
            .filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
            .sorted { $0.archivedAt > $1.archivedAt }
    }

    static func fileURL(for report: ArchivedReport) -> URL {
        archiveDirectory().appendingPathComponent(report.fileName)
    }

    static func archive(
        sourceURL: URL,
        kindTitle: String,
        projectName: String,
        recordCount: Int,
        at date: Date = Date()
    ) throws -> ArchivedReport {
        try ensureArchiveDirectory()
        let ext = sourceURL.pathExtension.isEmpty ? "dat" : sourceURL.pathExtension
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let destination = uniqueURL(baseName: baseName, fileExtension: ext)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        let report = ArchivedReport(
            id: UUID(),
            fileName: destination.lastPathComponent,
            kindTitle: kindTitle,
            projectName: normalizedProjectName(projectName),
            recordCount: recordCount,
            archivedAt: date
        )
        var reports = load()
        reports.removeAll { $0.fileName == report.fileName }
        reports.append(report)
        save(reports)
        return report
    }

    static func delete(_ report: ArchivedReport) {
        try? FileManager.default.removeItem(at: fileURL(for: report))
        var reports = load()
        reports.removeAll { $0.id == report.id || $0.fileName == report.fileName }
        save(reports)
    }

    private static func archiveDirectory() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    private static func ensureArchiveDirectory() throws {
        try FileManager.default.createDirectory(
            at: archiveDirectory(),
            withIntermediateDirectories: true
        )
    }

    private static func uniqueURL(baseName: String, fileExtension: String) -> URL {
        let cleanBase = sanitized(baseName).isEmpty ? "安全大师报告" : sanitized(baseName)
        let directory = archiveDirectory()
        var candidate = directory.appendingPathComponent(cleanBase).appendingPathExtension(fileExtension)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(cleanBase)_\(index)").appendingPathExtension(fileExtension)
            index += 1
        }
        return candidate
    }

    private static func load() -> [ArchivedReport] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([ArchivedReport].self, from: data)) ?? []
    }

    private static func save(_ reports: [ArchivedReport]) {
        guard let data = try? JSONEncoder().encode(reports) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func normalizedProjectName(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "未填写项目" : text
    }

    private static func sanitized(_ raw: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\r\t")
        return raw
            .components(separatedBy: illegal)
            .joined(separator: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
