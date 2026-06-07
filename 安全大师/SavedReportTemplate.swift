//
//  SavedReportTemplate.swift
//  安全大师
//

import Foundation

struct SavedReportTemplate: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var description: String?
    var documentKind: ReportDocumentKind
    var template: ReportTemplate
    var editableFields: ReportTemplateEditableFields?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        documentKind: ReportDocumentKind = .rectificationReply,
        template: ReportTemplate,
        editableFields: ReportTemplateEditableFields? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.documentKind = documentKind
        self.template = template
        self.editableFields = editableFields
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case documentKind
        case template
        case editableFields
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        documentKind = try container.decodeIfPresent(ReportDocumentKind.self, forKey: .documentKind) ?? .rectificationReply
        template = try container.decode(ReportTemplate.self, forKey: .template)
        editableFields = try container.decodeIfPresent(ReportTemplateEditableFields.self, forKey: .editableFields)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    static var defaultTemplate: SavedReportTemplate {
        let template = ReportTemplate.default
        return SavedReportTemplate(
            id: template.id,
            name: template.name,
            description: "系统默认模板",
            documentKind: .rectificationReply,
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
            let presets = ReportTemplatePresets.builtInTemplates
            save(presets)
            return presets
        }
        let normalized = decoded.map(normalized)
        if normalized.isEmpty {
            let presets = ReportTemplatePresets.builtInTemplates
            save(presets)
            return presets
        }
        return normalized.sortedByUpdatedAt()
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
        if copy.editableFields?.reportTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            copy.editableFields?.reportTitle = copy.documentKind.defaultReportTitle
        }
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
