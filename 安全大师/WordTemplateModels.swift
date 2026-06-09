//
//  WordTemplateModels.swift
//  安全大师
//

import Foundation

enum WordTemplateFieldKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case ignored
    case projectName
    case inspectedUnit
    case inspectionUnit
    case inspectionDate
    case noticeNumber
    case location
    case hazardDescription
    case rectificationRequirement
    case rectificationDeadline
    case responsiblePerson
    case inspector
    case receiver
    case reviewOpinion
    case rectificationSituation
    case legalBasis

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ignored: return "不填充"
        case .projectName: return "项目名称"
        case .inspectedUnit: return "被检查单位"
        case .inspectionUnit: return "检查单位"
        case .inspectionDate: return "检查日期"
        case .noticeNumber: return "通知编号"
        case .location: return "部位/地点"
        case .hazardDescription: return "隐患问题"
        case .rectificationRequirement: return "整改要求"
        case .rectificationDeadline: return "整改期限"
        case .responsiblePerson: return "责任人"
        case .inspector: return "检查人员"
        case .receiver: return "签收人"
        case .reviewOpinion: return "复查意见"
        case .rectificationSituation: return "整改情况"
        case .legalBasis: return "整改依据"
        }
    }
}

enum WordTemplatePlaceholderAnchor: Codable, Hashable {
    case text(raw: String)
    case emptyTableCell(index: Int)
}

struct TemplateFieldStyle: Codable, Hashable {
    var fontName: String?
    var fontSizeHalfPoints: String?
    var isBold: Bool
    var isItalic: Bool
    var underline: String?
    var colorHex: String?
    var paragraphAlignment: String?
    var lineSpacing: String?
    var beforeSpacing: String?
    var afterSpacing: String?

    static let empty = TemplateFieldStyle()

    init(
        fontName: String? = nil,
        fontSizeHalfPoints: String? = nil,
        isBold: Bool = false,
        isItalic: Bool = false,
        underline: String? = nil,
        colorHex: String? = nil,
        paragraphAlignment: String? = nil,
        lineSpacing: String? = nil,
        beforeSpacing: String? = nil,
        afterSpacing: String? = nil
    ) {
        self.fontName = fontName
        self.fontSizeHalfPoints = fontSizeHalfPoints
        self.isBold = isBold
        self.isItalic = isItalic
        self.underline = underline
        self.colorHex = colorHex
        self.paragraphAlignment = paragraphAlignment
        self.lineSpacing = lineSpacing
        self.beforeSpacing = beforeSpacing
        self.afterSpacing = afterSpacing
    }

    var isEmpty: Bool {
        fontName == nil &&
            fontSizeHalfPoints == nil &&
            !isBold &&
            !isItalic &&
            underline == nil &&
            colorHex == nil &&
            paragraphAlignment == nil &&
            lineSpacing == nil &&
            beforeSpacing == nil &&
            afterSpacing == nil
    }

    var summary: String {
        var parts: [String] = []
        if let fontName, !fontName.isEmpty {
            parts.append(fontName)
        }
        if let fontSizeHalfPoints, let halfPoints = Double(fontSizeHalfPoints) {
            parts.append("\(String(format: "%.1f", halfPoints / 2))pt")
        } else if let fontSizeHalfPoints, !fontSizeHalfPoints.isEmpty {
            parts.append("\(fontSizeHalfPoints)半磅")
        }
        if isBold {
            parts.append("加粗")
        }
        if isItalic {
            parts.append("斜体")
        }
        if let paragraphAlignment {
            let display = [
                "center": "居中",
                "right": "右对齐",
                "both": "两端对齐",
                "left": "左对齐"
            ][paragraphAlignment] ?? paragraphAlignment
            parts.append(display)
        }
        return parts.joined(separator: " · ")
    }
}

struct WordTemplatePlaceholder: Identifiable, Codable, Hashable {
    var id: UUID
    var anchor: WordTemplatePlaceholderAnchor
    var context: String
    var suggestedKind: WordTemplateFieldKind
    var boundKind: WordTemplateFieldKind
    var style: TemplateFieldStyle

    init(
        id: UUID = UUID(),
        anchor: WordTemplatePlaceholderAnchor,
        context: String,
        suggestedKind: WordTemplateFieldKind,
        style: TemplateFieldStyle = .empty
    ) {
        self.id = id
        self.anchor = anchor
        self.context = context
        self.suggestedKind = suggestedKind
        self.boundKind = suggestedKind
        self.style = style
    }

    enum CodingKeys: String, CodingKey {
        case id
        case anchor
        case context
        case suggestedKind
        case boundKind
        case style
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        anchor = try container.decode(WordTemplatePlaceholderAnchor.self, forKey: .anchor)
        context = try container.decode(String.self, forKey: .context)
        suggestedKind = try container.decode(WordTemplateFieldKind.self, forKey: .suggestedKind)
        boundKind = try container.decode(WordTemplateFieldKind.self, forKey: .boundKind)
        style = try container.decodeIfPresent(TemplateFieldStyle.self, forKey: .style) ?? .empty
    }
}

struct ImportedWordTemplate: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var originalFileName: String
    var storedFileName: String
    var placeholders: [WordTemplatePlaceholder]
    var createdAt: Date
    var updatedAt: Date

    var activeBindingCount: Int {
        placeholders.filter { $0.boundKind != .ignored }.count
    }
}
