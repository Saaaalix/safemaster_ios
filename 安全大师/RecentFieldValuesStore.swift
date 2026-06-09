//
//  RecentFieldValuesStore.swift
//  安全大师
//

import Foundation

enum RecentFieldKind {
    case projectName
    case inspectorName
    case location
    case rectificationResponsible
    case rectificationResponsibleUnit

    var storageKey: String {
        switch self {
        case .projectName:
            return "safemasterRecentProjectNames"
        case .inspectorName:
            return "safemasterRecentInspectorNames"
        case .location:
            return "safemasterRecentLocations"
        case .rectificationResponsible:
            return "safemasterRecentRectificationResponsible"
        case .rectificationResponsibleUnit:
            return "safemasterRecentRectificationResponsibleUnits"
        }
    }
}

struct RecentQuickInspectionFields {
    var projectName: String
    var inspectorName: String
    var location: String
    var responsiblePerson: String
    var responsibleUnit: String
}

enum RecentFieldValuesStore {
    private static let maxCount = 15

    static func record(_ value: String, for kind: RecentFieldKind) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = recent(for: kind).filter { $0 != trimmed }
        list.insert(trimmed, at: 0)
        if list.count > maxCount {
            list = Array(list.prefix(maxCount))
        }
        UserDefaults.standard.set(list, forKey: kind.storageKey)
    }

    static func recent(for kind: RecentFieldKind) -> [String] {
        UserDefaults.standard.stringArray(forKey: kind.storageKey) ?? []
    }

    static func recordReportCover(projectName: String, inspectorName: String) {
        record(projectName, for: .projectName)
        record(inspectorName, for: .inspectorName)
    }

    static func lastQuickInspectionFields() -> RecentQuickInspectionFields {
        RecentQuickInspectionFields(
            projectName: recent(for: .projectName).first ?? "",
            inspectorName: recent(for: .inspectorName).first ?? "",
            location: recent(for: .location).first ?? "",
            responsiblePerson: recent(for: .rectificationResponsible).first ?? "",
            responsibleUnit: recent(for: .rectificationResponsibleUnit).first ?? ""
        )
    }

    static func recordQuickInspectionFields(
        projectName: String,
        inspectorName: String,
        location: String,
        responsiblePerson: String,
        responsibleUnit: String
    ) {
        recordReportCover(projectName: projectName, inspectorName: inspectorName)
        record(location, for: .location)
        record(responsiblePerson, for: .rectificationResponsible)
        record(responsibleUnit, for: .rectificationResponsibleUnit)
    }
}
