//
//  ReportTemplateModel.swift
//  安全大师
//

import Foundation

enum ReportModuleType: String, CaseIterable, Codable, Hashable, Identifiable {
    case basicInfo
    case narrative
    case rectificationList
    case photoComparison
    case signature
    case notes

    var id: String { rawValue }
}

struct ReportModule: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var type: ReportModuleType
    var title: String
    var isEnabled: Bool
    var sortIndex: Int

    init(
        id: UUID = UUID(),
        type: ReportModuleType,
        title: String,
        isEnabled: Bool = true,
        sortIndex: Int
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.isEnabled = isEnabled
        self.sortIndex = sortIndex
    }
}

struct ReportTemplate: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var modules: [ReportModule]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        modules: [ReportModule] = ReportTemplate.defaultModules,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.modules = modules.sortedBySortIndex()
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static let defaultModules: [ReportModule] = [
        ReportModule(type: .basicInfo, title: "基本信息", sortIndex: 0),
        ReportModule(type: .narrative, title: "隐患描述", sortIndex: 1),
        ReportModule(type: .rectificationList, title: "整改清单", sortIndex: 2),
        ReportModule(type: .photoComparison, title: "照片对比", sortIndex: 3),
        ReportModule(type: .signature, title: "签字确认", sortIndex: 4),
        ReportModule(type: .notes, title: "备注", sortIndex: 5)
    ]

    static var `default`: ReportTemplate {
        ReportTemplate(name: "默认模板")
    }

    var enabledModules: [ReportModule] {
        modules
            .filter(\.isEnabled)
            .sortedBySortIndex()
    }
}

private extension Array where Element == ReportModule {
    func sortedBySortIndex() -> [ReportModule] {
        sorted {
            if $0.sortIndex == $1.sortIndex {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.sortIndex < $1.sortIndex
        }
    }
}
