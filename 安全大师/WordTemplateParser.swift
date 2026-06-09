//
//  WordTemplateParser.swift
//  安全大师
//

import Compression
import Foundation

struct WordTemplateParseResult {
    var documentXML: String
    var placeholders: [WordTemplatePlaceholder]
}

enum WordTemplateParser {
    enum ParseError: LocalizedError {
        case missingDocumentXML
        case unreadableDocument

        var errorDescription: String? {
            switch self {
            case .missingDocumentXML:
                return "未找到 Word 主文档内容。"
            case .unreadableDocument:
                return "无法读取该 Word 模板，请确认文件为 .docx。"
            }
        }
    }

    static func parse(url: URL) throws -> WordTemplateParseResult {
        let data = try Data(contentsOf: url)
        guard let xmlData = DocxArchive.entryData(named: "word/document.xml", in: data),
              let xml = String(data: xmlData, encoding: .utf8)
        else { throw ParseError.missingDocumentXML }
        return WordTemplateParseResult(documentXML: xml, placeholders: detectPlaceholders(in: xml))
    }

    static func detectPlaceholders(in xml: String) -> [WordTemplatePlaceholder] {
        var placeholders: [WordTemplatePlaceholder] = []
        let plain = plainText(from: xml)
        let styledTextPlaceholders = textPlaceholderStyles(in: xml)
        var seen = Set<String>()

        let patterns = ["_{2,}", "（\\s*）", "\\(\\s*\\)"]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(plain.startIndex..<plain.endIndex, in: plain)
            for match in regex.matches(in: plain, range: range) {
                guard let swiftRange = Range(match.range, in: plain) else { continue }
                let raw = String(plain[swiftRange])
                let context = contextText(around: swiftRange, in: plain)
                let key = "\(raw)-\(context)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                placeholders.append(
                    WordTemplatePlaceholder(
                        anchor: .text(raw: raw),
                        context: context,
                        suggestedKind: guessKind(from: context),
                        style: styleForText(raw: raw, context: context, matches: styledTextPlaceholders)
                    )
                )
            }
        }

        let colonContexts = plain.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasSuffix(":") || trimmed.hasSuffix("：")
        }
        for context in colonContexts.prefix(20) {
            placeholders.append(
                WordTemplatePlaceholder(
                    anchor: .text(raw: context),
                    context: context,
                    suggestedKind: guessKind(from: context),
                    style: styleForText(raw: context, context: context, matches: styledTextPlaceholders)
                )
            )
        }

        let emptyCellContexts = emptyTableCellContexts(in: xml)
        for (index, item) in emptyCellContexts.enumerated() {
            placeholders.append(
                WordTemplatePlaceholder(
                    anchor: .emptyTableCell(index: index),
                    context: item.context.isEmpty ? "表格空单元格 \(index + 1)" : item.context,
                    suggestedKind: guessKind(from: item.context),
                    style: item.style
                )
            )
        }

        return Array(placeholders.prefix(80))
    }

    static func plainText(from xml: String) -> String {
        xml
            .replacingOccurrences(of: "</w:p>", with: "\n")
            .replacingOccurrences(of: "</w:tc>", with: "\t")
            .replacingOccurrences(of: "<w:tab/>", with: "\t")
            .replacingOccurrences(of: "<w:br/>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .decodeWordTemplateXMLEntities()
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func contextText(around range: Range<String.Index>, in text: String) -> String {
        let lower = text.index(range.lowerBound, offsetBy: -24, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: 24, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[lower..<upper])
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func emptyTableCellContexts(in xml: String) -> [(context: String, style: TemplateFieldStyle)] {
        guard let regex = try? NSRegularExpression(pattern: "<w:tc[\\s\\S]*?</w:tc>") else { return [] }
        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let cells = regex.matches(in: xml, range: nsRange).compactMap { match -> String? in
            guard let range = Range(match.range, in: xml) else { return nil }
            return String(xml[range])
        }
        var results: [(context: String, style: TemplateFieldStyle)] = []
        for (index, cell) in cells.enumerated() {
            let text = plainText(from: cell).trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.isEmpty else { continue }
            let previousText = index > 0 ? plainText(from: cells[index - 1]) : ""
            let style = styleForEmptyCell(cell, fallbackCell: index > 0 ? cells[index - 1] : nil)
            results.append((previousText, style))
        }
        return results
    }

    private static func textPlaceholderStyles(in xml: String) -> [(text: String, paragraphText: String, style: TemplateFieldStyle)] {
        guard let paragraphRegex = try? NSRegularExpression(pattern: "<w:p[\\s\\S]*?</w:p>") else { return [] }
        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        var results: [(text: String, paragraphText: String, style: TemplateFieldStyle)] = []

        for paragraphMatch in paragraphRegex.matches(in: xml, range: nsRange) {
            guard let paragraphRange = Range(paragraphMatch.range, in: xml) else { continue }
            let paragraphXML = String(xml[paragraphRange])
            let paragraphText = plainText(from: paragraphXML)
            guard !paragraphText.isEmpty else { continue }

            let runRegex = try? NSRegularExpression(pattern: "<w:r[\\s\\S]*?</w:r>")
            let paragraphNSRange = NSRange(paragraphXML.startIndex..<paragraphXML.endIndex, in: paragraphXML)
            let runs = runRegex?.matches(in: paragraphXML, range: paragraphNSRange) ?? []

            for runMatch in runs {
                guard let runRange = Range(runMatch.range, in: paragraphXML) else { continue }
                let runXML = String(paragraphXML[runRange])
                let runText = plainText(from: runXML)
                guard !runText.isEmpty else { continue }
                results.append((
                    text: runText,
                    paragraphText: paragraphText,
                    style: extractStyle(runXML: runXML, paragraphXML: paragraphXML)
                ))
            }

            if runs.isEmpty {
                results.append((
                    text: paragraphText,
                    paragraphText: paragraphText,
                    style: extractStyle(runXML: nil, paragraphXML: paragraphXML)
                ))
            }
        }

        return results
    }

    private static func styleForText(
        raw: String,
        context: String,
        matches: [(text: String, paragraphText: String, style: TemplateFieldStyle)]
    ) -> TemplateFieldStyle {
        if let exact = matches.first(where: { $0.text.contains(raw) && !$0.style.isEmpty }) {
            return exact.style
        }
        if let paragraph = matches.first(where: {
            ($0.paragraphText.contains(raw) || context.contains($0.paragraphText) || $0.paragraphText.contains(context)) && !$0.style.isEmpty
        }) {
            return paragraph.style
        }
        return .empty
    }

    private static func styleForEmptyCell(_ cellXML: String, fallbackCell: String?) -> TemplateFieldStyle {
        if let style = firstNonEmptyStyle(in: cellXML) {
            return style
        }
        if let fallbackCell, let style = firstNonEmptyStyle(in: fallbackCell) {
            return style
        }
        return .empty
    }

    private static func firstNonEmptyStyle(in xml: String) -> TemplateFieldStyle? {
        let paragraphXML = firstMatch(pattern: "<w:p[\\s\\S]*?</w:p>", in: xml)
        let runXML = firstMatch(pattern: "<w:r[\\s\\S]*?</w:r>", in: xml)
        let style = extractStyle(runXML: runXML, paragraphXML: paragraphXML ?? xml)
        return style.isEmpty ? nil : style
    }

    private static func extractStyle(runXML: String?, paragraphXML: String?) -> TemplateFieldStyle {
        let runProperties = runXML.flatMap { firstMatch(pattern: "<w:rPr[\\s\\S]*?</w:rPr>", in: $0) } ?? runXML ?? ""
        let paragraphProperties = paragraphXML.flatMap { firstMatch(pattern: "<w:pPr[\\s\\S]*?</w:pPr>", in: $0) } ?? ""
        let fontsTag = firstMatch(pattern: "<w:rFonts\\b[^>]*/?>", in: runProperties)
        let sizeTag = firstMatch(pattern: "<w:sz\\b[^>]*/?>", in: runProperties)
        let underlineTag = firstMatch(pattern: "<w:u\\b[^>]*/?>", in: runProperties)
        let colorTag = firstMatch(pattern: "<w:color\\b[^>]*/?>", in: runProperties)
        let alignmentTag = firstMatch(pattern: "<w:jc\\b[^>]*/?>", in: paragraphProperties)
        let spacingTag = firstMatch(pattern: "<w:spacing\\b[^>]*/?>", in: paragraphProperties)

        return TemplateFieldStyle(
            fontName: attribute(["w:eastAsia", "w:ascii", "w:hAnsi"], in: fontsTag),
            fontSizeHalfPoints: attribute(["w:val"], in: sizeTag),
            isBold: hasOnOffTag("w:b", in: runProperties),
            isItalic: hasOnOffTag("w:i", in: runProperties),
            underline: attribute(["w:val"], in: underlineTag),
            colorHex: attribute(["w:val"], in: colorTag),
            paragraphAlignment: attribute(["w:val"], in: alignmentTag),
            lineSpacing: attribute(["w:line"], in: spacingTag),
            beforeSpacing: attribute(["w:before"], in: spacingTag),
            afterSpacing: attribute(["w:after"], in: spacingTag)
        )
    }

    private static func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text)
        else { return nil }
        return String(text[swiftRange])
    }

    private static func attribute(_ names: [String], in tag: String?) -> String? {
        guard let tag else { return nil }
        for name in names {
            let pattern = "\(NSRegularExpression.escapedPattern(for: name))=\"([^\"]+)\""
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
            guard let match = regex.firstMatch(in: tag, range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: tag)
            else { continue }
            return String(tag[valueRange])
        }
        return nil
    }

    private static func hasOnOffTag(_ tagName: String, in xml: String) -> Bool {
        guard let tag = firstMatch(pattern: "<\(tagName)\\b[^>]*/?>", in: xml) else { return false }
        let value = attribute(["w:val"], in: tag)?.lowercased()
        return value == nil || value == "1" || value == "true" || value == "on"
    }

    private static func guessKind(from rawContext: String) -> WordTemplateFieldKind {
        let context = rawContext.replacingOccurrences(of: " ", with: "")
        let rules: [(String, WordTemplateFieldKind)] = [
            ("项目", .projectName),
            ("被检查单位", .inspectedUnit),
            ("受检单位", .inspectedUnit),
            ("检查单位", .inspectionUnit),
            ("检查日期", .inspectionDate),
            ("检查时间", .inspectionDate),
            ("通知编号", .noticeNumber),
            ("文号", .noticeNumber),
            ("部位", .location),
            ("地点", .location),
            ("隐患", .hazardDescription),
            ("存在问题", .hazardDescription),
            ("整改要求", .rectificationRequirement),
            ("整改措施", .rectificationRequirement),
            ("整改期限", .rectificationDeadline),
            ("期限", .rectificationDeadline),
            ("责任人", .responsiblePerson),
            ("检查人", .inspector),
            ("检查人员", .inspector),
            ("签收", .receiver),
            ("接收", .receiver),
            ("复查意见", .reviewOpinion),
            ("验收意见", .reviewOpinion),
            ("整改情况", .rectificationSituation),
            ("整改依据", .legalBasis),
            ("依据", .legalBasis)
        ]
        return rules.first { context.contains($0.0) }?.1 ?? .ignored
    }
}

private extension String {
    func decodeWordTemplateXMLEntities() -> String {
        replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
