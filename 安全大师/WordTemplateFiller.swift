//
//  WordTemplateFiller.swift
//  安全大师
//

import Foundation

enum WordTemplateFiller {
    enum FillError: LocalizedError {
        case unreadableTemplate
        case missingDocumentXML
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .unreadableTemplate:
                return "无法读取单位 Word 模板。"
            case .missingDocumentXML:
                return "模板缺少 Word 主文档内容。"
            case .writeFailed:
                return "生成 Word 文书失败，请稍后重试。"
            }
        }
    }

    static func buildDocument(
        template: ImportedWordTemplate,
        editableFields: ReportTemplateEditableFields,
        previewData: ReportTemplatePreviewData,
        outputKind: ShareableReportKind = .inspection
    ) throws -> URL {
        let sourceURL = ImportedWordTemplateStore.fileURL(for: template)
        let data = try Data(contentsOf: sourceURL)
        guard var entries = DocxArchive.entries(in: data) else { throw FillError.unreadableTemplate }
        guard let documentIndex = entries.firstIndex(where: { $0.path == "word/document.xml" }),
              var xml = String(data: entries[documentIndex].data, encoding: .utf8)
        else { throw FillError.missingDocumentXML }

        let values = fieldValues(editableFields: editableFields, previewData: previewData)
        for placeholder in template.placeholders where placeholder.boundKind != .ignored {
            let value = values[placeholder.boundKind]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { continue }
            switch placeholder.anchor {
            case .text(let raw):
                xml = replaceTextPlaceholder(raw, with: value, style: placeholder.style, in: xml)
            case .emptyTableCell(let index):
                xml = fillEmptyTableCell(at: index, with: value, style: placeholder.style, in: xml)
            }
        }

        entries[documentIndex].data = Data(xml.utf8)
        guard let output = DocxArchive.build(entries: entries) else { throw FillError.writeFailed }
        let url = ReportExportFileNameBuilder.fileURL(
            projectName: editableFields.projectName,
            documentName: outputKind == .inspection ? "隐患整改通知单" : "隐患整改回复报告",
            fileExtension: "docx"
        )
        do {
            try output.write(to: url)
            return url
        } catch {
            throw FillError.writeFailed
        }
    }

    private static func fieldValues(
        editableFields: ReportTemplateEditableFields,
        previewData: ReportTemplatePreviewData
    ) -> [WordTemplateFieldKind: String] {
        let firstItem = previewData.rectificationItems.first
        return [
            .projectName: editableFields.displayValue(\.projectName, fallback: previewData.basicInfo.projectName),
            .inspectedUnit: editableFields.displayValue(\.inspectedUnit, fallback: previewData.basicInfo.inspectedUnit),
            .inspectionUnit: editableFields.displayValue(\.inspectionUnit, fallback: previewData.basicInfo.inspectionUnit),
            .inspectionDate: editableFields.displayValue(\.inspectionDate, fallback: previewData.basicInfo.inspectionTime),
            .noticeNumber: editableFields.noticeNumber,
            .location: firstItem?.issueDescription ?? "",
            .hazardDescription: firstItem?.issueDescription ?? editableFields.narrativeText,
            .rectificationRequirement: firstItem?.rectificationStatus ?? editableFields.narrativeText,
            .rectificationDeadline: editableFields.displayValue(\.rectificationDeadline, fallback: firstItem?.deadline ?? ""),
            .responsiblePerson: editableFields.displayValue(\.rectificationResponsiblePerson, fallback: firstItem?.responsibleParty ?? ""),
            .inspector: editableFields.inspector,
            .receiver: editableFields.receiver,
            .reviewOpinion: editableFields.reviewOpinion,
            .rectificationSituation: firstItem?.rectificationStatus ?? "",
            .legalBasis: editableFields.additionalNotes
        ]
    }

    private static func replaceTextPlaceholder(_ raw: String, with value: String, style: TemplateFieldStyle, in xml: String) -> String {
        let escapedRaw = escapeXML(raw)
        let escapedValue = escapeXML(value)
        if xml.contains(escapedRaw) {
            if let replaced = replaceTextRun(raw: escapedRaw, with: escapedValue, style: style, in: xml) {
                return replaced
            }
            return xml.replacingOccurrences(of: escapedRaw, with: escapedValue, options: [], range: xml.range(of: escapedRaw))
        }
        if xml.contains(raw) {
            if let replaced = replaceTextRun(raw: raw, with: escapedValue, style: style, in: xml) {
                return replaced
            }
            return xml.replacingOccurrences(of: raw, with: escapedValue, options: [], range: xml.range(of: raw))
        }
        return xml
    }

    private static func replaceTextRun(raw: String, with escapedValue: String, style: TemplateFieldStyle, in xml: String) -> String? {
        guard !style.isEmpty,
              let regex = try? NSRegularExpression(pattern: "<w:r[\\s\\S]*?</w:r>")
        else { return nil }

        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        for match in regex.matches(in: xml, range: nsRange) {
            guard let range = Range(match.range, in: xml) else { continue }
            let run = String(xml[range])
            guard run.contains(raw) else { continue }
            let styledRun = applyRunStyle(to: run.replacingOccurrences(of: raw, with: escapedValue), style: style)
            var copy = xml
            copy.replaceSubrange(range, with: styledRun)
            return copy
        }
        return nil
    }

    private static func fillEmptyTableCell(at targetIndex: Int, with value: String, style: TemplateFieldStyle, in xml: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<w:tc[\\s\\S]*?</w:tc>") else { return xml }
        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let matches = regex.matches(in: xml, range: nsRange)
        var emptyIndex = 0
        for match in matches {
            guard let range = Range(match.range, in: xml) else { continue }
            let cell = String(xml[range])
            let text = WordTemplateParser.plainText(from: cell).trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.isEmpty else { continue }
            if emptyIndex == targetIndex {
                let filled = cell.replacingOccurrences(
                    of: "</w:tc>",
                    with: "\(styledParagraphXML(value: value, style: style))</w:tc>"
                )
                var copy = xml
                copy.replaceSubrange(range, with: filled)
                return copy
            }
            emptyIndex += 1
        }
        return xml
    }

    private static func styledParagraphXML(value: String, style: TemplateFieldStyle) -> String {
        "<w:p>\(paragraphPropertiesXML(style))<w:r>\(runPropertiesXML(style))<w:t>\(escapeXML(value))</w:t></w:r></w:p>"
    }

    private static func applyRunStyle(to runXML: String, style: TemplateFieldStyle) -> String {
        let properties = runPropertiesXML(style)
        guard !properties.isEmpty else { return runXML }

        if let propertiesRange = runXML.range(of: "<w:rPr[\\s\\S]*?</w:rPr>", options: .regularExpression) {
            var copy = runXML
            copy.replaceSubrange(propertiesRange, with: properties)
            return copy
        }

        guard let insertionPoint = runXML.range(of: ">")?.upperBound else { return runXML }
        var copy = runXML
        copy.insert(contentsOf: properties, at: insertionPoint)
        return copy
    }

    private static func runPropertiesXML(_ style: TemplateFieldStyle) -> String {
        var parts: [String] = []
        if let fontName = style.fontName, !fontName.isEmpty {
            let escaped = escapeXML(fontName)
            parts.append("<w:rFonts w:ascii=\"\(escaped)\" w:eastAsia=\"\(escaped)\" w:hAnsi=\"\(escaped)\"/>")
        }
        if style.isBold {
            parts.append("<w:b/>")
        }
        if style.isItalic {
            parts.append("<w:i/>")
        }
        if let underline = style.underline, !underline.isEmpty, underline != "none" {
            parts.append("<w:u w:val=\"\(escapeXML(underline))\"/>")
        }
        if let colorHex = style.colorHex, !colorHex.isEmpty, colorHex.lowercased() != "auto" {
            parts.append("<w:color w:val=\"\(escapeXML(colorHex))\"/>")
        }
        if let fontSizeHalfPoints = style.fontSizeHalfPoints, !fontSizeHalfPoints.isEmpty {
            let escaped = escapeXML(fontSizeHalfPoints)
            parts.append("<w:sz w:val=\"\(escaped)\"/>")
            parts.append("<w:szCs w:val=\"\(escaped)\"/>")
        }
        guard !parts.isEmpty else { return "" }
        return "<w:rPr>\(parts.joined())</w:rPr>"
    }

    private static func paragraphPropertiesXML(_ style: TemplateFieldStyle) -> String {
        var parts: [String] = []
        if let paragraphAlignment = style.paragraphAlignment, !paragraphAlignment.isEmpty {
            parts.append("<w:jc w:val=\"\(escapeXML(paragraphAlignment))\"/>")
        }

        var spacingAttributes: [String] = []
        if let lineSpacing = style.lineSpacing, !lineSpacing.isEmpty {
            spacingAttributes.append("w:line=\"\(escapeXML(lineSpacing))\"")
        }
        if let beforeSpacing = style.beforeSpacing, !beforeSpacing.isEmpty {
            spacingAttributes.append("w:before=\"\(escapeXML(beforeSpacing))\"")
        }
        if let afterSpacing = style.afterSpacing, !afterSpacing.isEmpty {
            spacingAttributes.append("w:after=\"\(escapeXML(afterSpacing))\"")
        }
        if !spacingAttributes.isEmpty {
            parts.append("<w:spacing \(spacingAttributes.joined(separator: " "))/>")
        }

        guard !parts.isEmpty else { return "" }
        return "<w:pPr>\(parts.joined())</w:pPr>"
    }

    private static func escapeXML(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
