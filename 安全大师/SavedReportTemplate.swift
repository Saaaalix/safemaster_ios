//
//  SavedReportTemplate.swift
//  安全大师
//

import Foundation

struct SavedReportTemplate: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var description: String?
    var template: ReportTemplate
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        template: ReportTemplate,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.template = template
        self.updatedAt = updatedAt
    }

    static var defaultTemplate: SavedReportTemplate {
        let template = ReportTemplate.default
        return SavedReportTemplate(
            id: template.id,
            name: template.name,
            description: "系统默认模板",
            template: template
        )
    }
}

enum SavedReportTemplateStore {
    private static let storageKey = "safemaster.savedReportTemplates.v1"

    static func load() -> [SavedReportTemplate] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SavedReportTemplate].self, from: data)
        else {
            return [SavedReportTemplate.defaultTemplate]
        }
        let normalized = decoded.map(normalized)
        return normalized.isEmpty ? [SavedReportTemplate.defaultTemplate] : normalized.sortedByUpdatedAt()
    }

    static func save(_ templates: [SavedReportTemplate]) {
        let normalized = templates.map(normalized).sortedByUpdatedAt()
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func normalized(_ savedTemplate: SavedReportTemplate) -> SavedReportTemplate {
        var copy = savedTemplate
        let name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = name.isEmpty ? "未命名模板" : name
        copy.description = copy.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.description?.isEmpty == true {
            copy.description = nil
        }
        copy.template.name = copy.name
        copy.template.modules = copy.template.modules.sorted { $0.sortIndex < $1.sortIndex }
        return copy
    }
}

private extension Array where Element == SavedReportTemplate {
    func sortedByUpdatedAt() -> [SavedReportTemplate] {
        sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.updatedAt > $1.updatedAt
        }
    }
}
