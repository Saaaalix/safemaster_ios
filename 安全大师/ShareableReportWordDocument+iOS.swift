//
//  ShareableReportWordDocument+iOS.swift
//  安全大师
//
//  生成标准 .docx（OOXML：ZIP + XML + 内嵌 JPEG），Microsoft Word / WPS 可直接打开并编辑。
//

#if os(iOS)

import CoreData
import UIKit
import zlib

enum ShareableReportWordDocumentBuilder {
    enum BuildError: Error {
        case noFindings
        case writeFailed
        case zipFailed
    }

    static func buildTemporaryFileURL(findings: [InspectionFinding], day: Date) throws -> URL {
        try buildTemporaryFileURL(findings: findings, kind: .inspection, headerDateOverride: day)
    }

    static func buildTemporaryFileURL(
        findings: [InspectionFinding],
        kind: ShareableReportKind
    ) throws -> URL {
        try buildTemporaryFileURL(findings: findings, kind: kind, headerDateOverride: nil)
    }

    private static func buildTemporaryFileURL(
        findings: [InspectionFinding],
        kind: ShareableReportKind,
        headerDateOverride: Date?
    ) throws -> URL {
        let rows = DaySummaryBuilder.sortedForReport(findings)
        guard !rows.isEmpty else { throw BuildError.noFindings }
        let template = ReportTemplateSettings.current

        let dateStr: String
        if let headerDateOverride {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "zh_CN")
            fmt.dateStyle = .long
            dateStr = fmt.string(from: headerDateOverride)
        } else {
            dateStr = DaySummaryBuilder.reportHeaderDateLine(for: rows)
        }

        var media: [(path: String, data: Data)] = []
        var body = DocxBodyBuilder()

        appendCoverSection(to: &body, kind: kind, dateStr: dateStr, rows: rows, template: template)
        appendSummaryTable(to: &body, rows: rows, kind: kind, template: template)

        for (i, f) in rows.enumerated() {
            body.addPageBreak()
            appendDetailSection(
                to: &body,
                media: &media,
                finding: f,
                index: i + 1,
                kind: kind,
                template: template
            )
        }
        if template.includeSignoff {
            appendSignoffSection(to: &body, template: template)
        }
        if template.includeLegalAppendix {
            appendLegalBasisAppendixSection(to: &body, rows: rows)
        }

        body.closeBodyWithSection()

        let documentXML = body.documentXML
        let relsXML = body.documentRelsXML(mediaFileNames: media.map { URL(fileURLWithPath: $0.path).lastPathComponent })

        var entries: [(path: String, data: Data)] = []
        entries.append(("[Content_Types].xml", Data(contentTypesXML(mediaCount: media.count).utf8)))
        entries.append(("_rels/.rels", Data(rootRelsXML.utf8)))
        entries.append(("word/document.xml", Data(documentXML.utf8)))
        entries.append(("word/_rels/document.xml.rels", Data(relsXML.utf8)))
        entries.append(contentsOf: media)

        guard let zipData = DocxZip.build(entries: entries) else { throw BuildError.zipFailed }

        let name = "\(kind.fileNamePrefix)_\(Int(Date().timeIntervalSince1970)).docx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try zipData.write(to: url)
            return url
        } catch {
            throw BuildError.writeFailed
        }
    }

    private static func appendCoverSection(
        to body: inout DocxBodyBuilder,
        kind: ShareableReportKind,
        dateStr: String,
        rows: [InspectionFinding],
        template: ReportTemplateSettings
    ) {
        body.addTitle(kind.coverTitle)
        body.addMetaParagraph("文号：\(DaySummaryBuilder.reportDocumentCode(kind: kind, projectName: rows.first?.recordProjectNameSnapshot))")
        body.addMetaParagraph("项目名称：\(ReportProjectSettingsStore.coverProjectName(for: rows))")
        body.addMetaParagraph(
            kind == .inspection
                ? "检查人：\(ReportProjectSettingsStore.coverInspectorName(for: rows))"
                : "回复人：\(ReportProjectSettingsStore.coverInspectorName(for: rows))"
        )
        body.addMetaParagraph(kind == .inspection ? "检查日期：\(dateStr)" : "回复日期：\(dateStr)")
        body.addMetaParagraph("共 \(rows.count) 条隐患")
        appendCoverUnitMetaParagraphs(to: &body, template: template)
        body.addSeparatorParagraph()
        body.addHeading2("目录")
    }

    private static func appendCoverUnitMetaParagraphs(to body: inout DocxBodyBuilder, template: ReportTemplateSettings) {
        let units = [
            ("检查单位", template.inspectionUnit),
            ("施工单位", template.constructionUnit),
            ("监理单位", template.supervisionUnit)
        ]
        for (label, value) in units {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                body.addMetaParagraph("\(label)：\(trimmed)")
            }
        }
    }

    private static func appendSummaryTable(
        to body: inout DocxBodyBuilder,
        rows: [InspectionFinding],
        kind: ShareableReportKind,
        template: ReportTemplateSettings
    ) {
        var tableRows: [[String]]
        if kind == .inspection {
            var header = ["序号", "部位"]
            if template.includeRiskLevel { header.append("风险等级") }
            if template.includeDeadline { header.append("整改期限") }
            header.append("通知编号")
            tableRows = [header]
        } else {
            tableRows = [["序号", "部位", "验收结论", "验收时间", "回复编号"]]
        }
        for (i, f) in rows.enumerated() {
            if kind == .inspection {
                var row = [
                    "\(i + 1)",
                    f.reportLocationPart
                ]
                if template.includeRiskLevel { row.append(f.reportRiskLevelDisplay) }
                if template.includeDeadline { row.append(f.reportDeadlineLine) }
                row.append(DaySummaryBuilder.itemDocumentCode(kind: .inspection, finding: f, index: i + 1))
                tableRows.append(row)
            } else {
                tableRows.append([
                    "\(i + 1)",
                    f.reportLocationPart,
                    f.reportRectificationAcceptanceOpinion,
                    f.reportRectificationAcceptanceTime,
                    DaySummaryBuilder.itemDocumentCode(kind: .rectification, finding: f, index: i + 1)
                ])
            }
        }
        body.addTable(rows: tableRows, headerBold: true)
        body.addSeparatorParagraph()
    }

    private static func appendDetailSection(
        to body: inout DocxBodyBuilder,
        media: inout [(path: String, data: Data)],
        finding f: InspectionFinding,
        index: Int,
        kind: ShareableReportKind,
        template: ReportTemplateSettings
    ) {
        body.addHeading2(kind.coverTitle)
        body.addMetaParagraph("编号：\(DaySummaryBuilder.itemDocumentCode(kind: kind, finding: f, index: index))")

        switch kind {
        case .inspection:
            body.addMetaParagraph("部位：\(f.reportLocationPart)")
            embedReportPhotos(
                f.sitePhotoDatasOrdered,
                media: &media,
                body: &body,
                maxWidthInch: CGFloat(template.photoLayout.wordMaxWidthInch),
                maxHeightInch: CGFloat(template.photoLayout.wordMaxHeightInch)
            )
            appendRiskAndCategoryBlocks(to: &body, finding: f, template: template)
            body.addLabeledBlock(label: "存在问题", value: f.reportFormalIssueDescription())
        case .rectification:
            appendRectificationComparison(
                to: &body,
                media: &media,
                finding: f,
                template: template
            )
        }

        if kind == .inspection {
            body.addLabeledBlock(label: "整改要求", value: f.reportFormalRectificationRequirement)
            if template.includeLegalBasis {
                body.addLabeledBlock(label: "整改依据", value: f.reportLegalBasisReferenceSummary())
            }
            body.addLabeledBlock(label: "整改责任人", value: f.reportResponsibleParty)
            if template.includeDeadline {
                body.addLabeledBlock(label: "限期", value: f.reportDeadlineLine)
            }
        }
    }

    private static func appendRiskAndCategoryBlocks(
        to body: inout DocxBodyBuilder,
        finding f: InspectionFinding,
        template: ReportTemplateSettings
    ) {
        if template.includeAccidentCategory, template.includeRiskLevel {
            body.addLabeledBlock(
                label: "事故类别 / 风险等级",
                value: "\(f.reportAccidentCategoryDisplay) / \(f.reportRiskLevelDisplay)"
            )
        } else if template.includeAccidentCategory {
            body.addLabeledBlock(label: "事故类别", value: f.reportAccidentCategoryDisplay)
        } else if template.includeRiskLevel {
            body.addLabeledBlock(label: "风险等级", value: f.reportRiskLevelDisplay)
        }
    }

    private static func appendRectificationComparison(
        to body: inout DocxBodyBuilder,
        media: inout [(path: String, data: Data)],
        finding f: InspectionFinding,
        template: ReportTemplateSettings
    ) {
        var left = DocxCellContentBuilder()
        left.addColumnHeading("整改前")
        left.addLabeledBlock(label: "部位/地点", value: f.reportLocationPart)
        left.append(embedReportPhotoParagraphs(
            f.sitePhotoDatasOrdered,
            media: &media,
            body: &body,
            maxWidthInch: CGFloat(template.photoLayout.wordMaxWidthInch),
            maxHeightInch: CGFloat(template.photoLayout.wordMaxHeightInch)
        ))
        if f.sitePhotoDatasOrdered.isEmpty {
        left.addMetaParagraph("（无整改前照片）")
        }
        left.addLabeledBlock(label: "检查情况", value: f.reportFormalInspectionSituation)
        left.addLabeledBlock(label: "存在问题", value: f.reportFormalIssueDescription())
        if template.includeLegalBasis {
            left.addLabeledBlock(label: "整改依据", value: f.reportLegalBasisReferenceSummary())
        }
        left.addLabeledBlock(label: "整改要求", value: f.reportFormalRectificationRequirement)
        if template.includeRiskLevel {
            left.addLabeledBlock(label: "风险等级", value: f.reportRiskLevelDisplay)
        }
        if template.includeDeadline {
            left.addLabeledBlock(label: "限期", value: f.reportDeadlineLine)
        }
        if template.includeAccidentCategory {
            left.addLabeledBlock(label: "事故类别", value: f.reportAccidentCategoryDisplay)
        }

        var right = DocxCellContentBuilder()
        right.addColumnHeading("整改后")
        if let after = f.reportAfterRectificationPhotoData {
            right.append(embedReportPhotoParagraphs(
                [after],
                media: &media,
                body: &body,
                maxWidthInch: CGFloat(template.photoLayout.wordMaxWidthInch),
                maxHeightInch: CGFloat(template.photoLayout.wordMaxHeightInch)
            ))
        } else {
            right.addMetaParagraph("（无整改后照片）")
        }
        right.addLabeledBlock(label: "整改情况", value: f.reportRectificationSituation)
        right.addLabeledBlock(label: "整改责任人", value: f.reportResponsibleParty)
        right.addLabeledBlock(label: "验收意见", value: f.reportRectificationAcceptanceOpinion)
        right.addLabeledBlock(label: "验收时间", value: f.reportRectificationAcceptanceTime)

        body.addTwoColumnTable(leftXML: left.xml, rightXML: right.xml)
    }

    private static func appendSignoffSection(to body: inout DocxBodyBuilder, template: ReportTemplateSettings) {
        body.addSeparatorParagraph()
        body.addHeading2("签字确认")
        for label in template.normalized().signoffLabels {
            body.addMetaParagraph("\(label)（签字）：___________    日期：___________")
        }
    }

    private static func appendLegalBasisAppendixSection(
        to body: inout DocxBodyBuilder,
        rows: [InspectionFinding]
    ) {
        let appendixRows = rows.compactMap { finding -> (title: String, body: String)? in
            guard let full = finding.reportLegalBasisAppendixText else { return nil }
            return (finding.reportLocationPart, full)
        }
        guard !appendixRows.isEmpty else { return }
        body.addPageBreak()
        body.addHeading2("附录：整改依据原文")
        for (idx, row) in appendixRows.enumerated() {
            body.addLabeledBlock(label: "[\(idx + 1)] \(row.title)", value: row.body)
        }
    }

    // MARK: - OOXML 片段

    private static let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """

    private static func contentTypesXML(mediaCount: Int) -> String {
        var overrides = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        """
        if mediaCount > 0 {
            overrides += "\n<Default Extension=\"jpeg\" ContentType=\"image/jpeg\"/>"
        }
        overrides += "\n</Types>"
        return overrides
    }

    // MARK: - 版式与图片

    /// 控制报告内嵌图体积，与 PDF 思路一致。
    private static func scaledJPEGForReport(_ image: UIImage, maxWidth: CGFloat, quality: CGFloat = 0.78) -> Data? {
        let iw = image.size.width
        let ih = image.size.height
        guard iw > 0, ih > 0, iw.isFinite, ih.isFinite else { return nil }
        let scale = min(1, maxWidth / iw)
        let tw = iw * scale
        let th = ih * scale
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: tw, height: th), format: format)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: CGSize(width: tw, height: th)))
        }
        return scaled.jpegData(compressionQuality: quality)
    }

    /// WordprocessingML 中 extent 使用 EMU；约 914400 EMU = 1 英寸。
    private static func imageExtentEmu(
        for image: UIImage,
        maxWidthInch: CGFloat,
        maxHeightInch: CGFloat
    ) -> (Int, Int) {
        let wPt = Swift.max(image.size.width, 1)
        let hPt = Swift.max(image.size.height, 1)
        let aspect = hPt / wPt
        var widthInch = maxWidthInch
        var heightInch = widthInch * aspect
        if heightInch > maxHeightInch {
            heightInch = maxHeightInch
            widthInch = heightInch / Swift.max(aspect, 0.0001)
        }
        let wEmu = Int(Double(widthInch * 914_400))
        let hEmu = Swift.max(1, Int(Double(heightInch * 914_400)))
        return (wEmu, hEmu)
    }

    private static func embedReportPhotos(
        _ datas: [Data],
        media: inout [(path: String, data: Data)],
        body: inout DocxBodyBuilder,
        maxWidthInch: CGFloat,
        maxHeightInch: CGFloat = 2.4
    ) {
        for xml in embedReportPhotoParagraphs(
            datas,
            media: &media,
            body: &body,
            maxWidthInch: maxWidthInch,
            maxHeightInch: maxHeightInch
        ) {
            body.appendRaw(xml)
        }
    }

    private static func embedReportPhotoParagraphs(
        _ datas: [Data],
        media: inout [(path: String, data: Data)],
        body: inout DocxBodyBuilder,
        maxWidthInch: CGFloat,
        maxHeightInch: CGFloat = 2.4
    ) -> [String] {
        var paragraphs: [String] = []
        for d in datas {
            guard !d.isEmpty, let ui = UIImage(data: d),
                  let jpeg = scaledJPEGForReport(ui, maxWidth: 520) else { continue }
            let name = "image\(media.count + 1).jpeg"
            let pathInZip = "word/media/\(name)"
            media.append((pathInZip, jpeg))
            let (wEmu, hEmu) = imageExtentEmu(
                for: ui,
                maxWidthInch: maxWidthInch,
                maxHeightInch: maxHeightInch
            )
            paragraphs.append(body.embeddedImageParagraphXML(
                rId: body.nextImageRelId(),
                widthEmu: wEmu,
                heightEmu: hEmu,
                fileName: name
            ))
        }
        return paragraphs
    }
}

// MARK: - 双栏单元格内容（整改前 | 整改后）

private struct DocxCellContentBuilder {
    private var parts: [String] = []
    private static let bodyLineTwips = 336 // 1.4x line spacing for Chinese readability
    private static let bodyAfterSpacingTwips = 60

    mutating func append(_ xml: String) {
        guard !xml.isEmpty else { return }
        parts.append(xml)
    }

    mutating func append(_ paragraphs: [String]) {
        for p in paragraphs { append(p) }
    }

    mutating func addColumnHeading(_ text: String) {
        parts.append(
            """
            <w:p>
              <w:pPr>
                <w:jc w:val="center"/>
                <w:spacing w:before="0" w:after="60" w:line="360" w:lineRule="auto"/>
              </w:pPr>
              \(runsForCell(text, bold: true, fontHalfPt: 26))
            </w:p>
            """
        )
    }

    mutating func addMetaParagraph(_ text: String) {
        parts.append(cellParagraph(text, bold: false, fontHalfPt: 22, afterSpacingTwips: Self.bodyAfterSpacingTwips))
    }

    mutating func addLabeledBlock(label: String, value: String) {
        parts.append(cellParagraph(label, bold: true, fontHalfPt: 22, beforeSpacingTwips: 80, afterSpacingTwips: Self.bodyAfterSpacingTwips))
        parts.append(cellLeftMultiline(value, fontHalfPt: 22, afterSpacingTwips: Self.bodyAfterSpacingTwips))
    }

    var xml: String { parts.joined() }

    private func cellParagraph(
        _ text: String,
        bold: Bool,
        fontHalfPt: Int,
        beforeSpacingTwips: Int = 0,
        afterSpacingTwips: Int = 0
    ) -> String {
        """
        <w:p>
          <w:pPr>
            <w:spacing w:before="\(beforeSpacingTwips)" w:after="\(afterSpacingTwips)" w:line="\(Self.bodyLineTwips)" w:lineRule="auto"/>
          </w:pPr>
          \(runsForCell(text, bold: bold, fontHalfPt: fontHalfPt))
        </w:p>
        """
    }

    private func cellLeftMultiline(_ text: String, fontHalfPt: Int, afterSpacingTwips: Int) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var inner = ""
        for (i, line) in lines.enumerated() {
            inner += runsForCell(line, bold: false, fontHalfPt: fontHalfPt)
            if i < lines.count - 1 {
                inner += "<w:r><w:br/></w:r>"
            }
        }
        return """
        <w:p>
          <w:pPr>
            <w:jc w:val="left"/>
            <w:spacing w:before="0" w:after="\(afterSpacingTwips)" w:line="\(Self.bodyLineTwips)" w:lineRule="auto"/>
          </w:pPr>
          \(inner)
        </w:p>
        """
    }

    private func runsForCell(_ text: String, bold: Bool, fontHalfPt: Int) -> String {
        let esc = xmlEscape(text)
        let b = bold ? "<w:b/><w:bCs/>" : ""
        return """
        <w:r>
          <w:rPr>
            <w:rFonts w:ascii="SimSun" w:eastAsia="SimSun" w:hAnsi="SimSun"/>
            \(b)
            <w:sz w:val="\(fontHalfPt)"/>
            <w:szCs w:val="\(fontHalfPt)"/>
          </w:rPr>
          <w:t xml:space="preserve">\(esc)</w:t>
        </w:r>
        """
    }
}

// MARK: - document.xml 拼装（小四 12pt ≈ sz 24；标题 22pt ≈ sz 44）

private struct DocxBodyBuilder {
    private var chunks: [String] = []
    private var imageRelCounter = 1
    private var docPrCounter = 1
    private static let bodyLineTwips = 336 // 1.4x line spacing
    private static let bodyAfterSpacingTwips = 60

    private static let documentOpen = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
     xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
     xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
     xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
     xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
    <w:body>
    """

    private static let documentClose = """
    </w:body>
    </w:document>
    """

    mutating func nextImageRelId() -> String {
        defer { imageRelCounter += 1 }
        return "rId\(imageRelCounter)"
    }

    var documentXML: String {
        Self.documentOpen + chunks.joined() + Self.documentClose
    }

    func documentRelsXML(mediaFileNames: [String]) -> String {
        var lines = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        """
        for (i, name) in mediaFileNames.enumerated() {
            let rid = "rId\(i + 1)"
            lines += """
            \n<Relationship Id="\(rid)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/\(xmlEscape(name))"/>
            """
        }
        lines += "\n</Relationships>"
        return lines
    }

    mutating func addTitle(_ text: String) {
        chunks.append(paragraphCenteredBold(text, eastAsiaFont: "SimHei", fontHalfPt: 44, afterSpacingTwips: 120))
    }

    mutating func addMetaParagraph(_ text: String) {
        chunks.append(paragraphLeft(text, bold: false, fontHalfPt: 24, afterSpacingTwips: Self.bodyAfterSpacingTwips))
    }

    mutating func addHeading2(_ text: String) {
        chunks.append(
            paragraphLeft(text, bold: true, eastAsiaFont: "SimHei", fontHalfPt: 30, beforeSpacingTwips: 200, afterSpacingTwips: 80)
        )
    }

    mutating func addSeparatorParagraph() {
        chunks.append(
            """
            <w:p><w:pPr><w:spacing w:before="120" w:after="120" w:line="360" w:lineRule="auto"/></w:pPr>\
            <w:r><w:t>————————————————————</w:t></w:r></w:p>
            """
        )
    }

    mutating func addPageBreak() {
        chunks.append("<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>")
    }

    mutating func addFootnoteParagraph(_ text: String) {
        chunks.append(paragraphLeft(text, bold: false, fontHalfPt: 20, beforeSpacingTwips: 40, afterSpacingTwips: 60))
    }

    mutating func addTable(rows: [[String]], headerBold: Bool) {
        guard let colCount = rows.map(\.count).max(), colCount > 0 else { return }
        let colWidth = max(900, 8800 / colCount)
        var xml = """
        <w:tbl>
          <w:tblPr>
            <w:tblW w:w="0" w:type="auto"/>
            <w:tblBorders>
              <w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/>
              <w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>
              <w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/>
              <w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/>
              <w:insideH w:val="single" w:sz="4" w:space="0" w:color="auto"/>
              <w:insideV w:val="single" w:sz="4" w:space="0" w:color="auto"/>
            </w:tblBorders>
          </w:tblPr>
        """
        for (rowIndex, row) in rows.enumerated() {
            let bold = headerBold && rowIndex == 0
            xml += "<w:tr>"
            for col in 0 ..< colCount {
                let cellText = col < row.count ? row[col] : ""
                xml += tableCell(text: cellText, widthTwips: colWidth, bold: bold)
            }
            xml += "</w:tr>"
        }
        xml += "</w:tbl>"
        chunks.append(xml)
        chunks.append(
            """
            <w:p><w:pPr><w:spacing w:before="80" w:after="80"/></w:pPr></w:p>
            """
        )
    }

    private func tableCell(text: String, widthTwips: Int, bold: Bool) -> String {
        let runs = runsForPlainText(text, bold: bold, eastAsiaFont: "SimSun", fontHalfPt: 22)
        return """
        <w:tc>
          <w:tcPr><w:tcW w:w="\(widthTwips)" w:type="dxa"/></w:tcPr>
          <w:p><w:pPr><w:spacing w:before="40" w:after="40"/></w:pPr>\(runs)</w:p>
        </w:tc>
        """
    }

    mutating func addLabeledBlock(label: String, value: String) {
        chunks.append(paragraphLeft(label, bold: true, fontHalfPt: 24, beforeSpacingTwips: 120, afterSpacingTwips: Self.bodyAfterSpacingTwips))
        chunks.append(paragraphLeftMultiline(value, fontHalfPt: 24, afterSpacingTwips: Self.bodyAfterSpacingTwips))
    }

    mutating func appendRaw(_ xml: String) {
        chunks.append(xml)
    }

    /// 整改回复单：左右对照（整改前 | 整改后）。
    mutating func addTwoColumnTable(leftXML: String, rightXML: String) {
        let colWidth = 4300
        let xml = """
        <w:tbl>
          <w:tblPr>
            <w:tblW w:w="0" w:type="auto"/>
            <w:tblBorders>
              <w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/>
              <w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>
              <w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/>
              <w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/>
              <w:insideH w:val="single" w:sz="4" w:space="0" w:color="auto"/>
              <w:insideV w:val="single" w:sz="4" w:space="0" w:color="auto"/>
            </w:tblBorders>
          </w:tblPr>
          <w:tblGrid>
            <w:gridCol w:w="\(colWidth)"/>
            <w:gridCol w:w="\(colWidth)"/>
          </w:tblGrid>
          <w:tr>
            \(comparisonTableCell(innerXML: leftXML, widthTwips: colWidth))
            \(comparisonTableCell(innerXML: rightXML, widthTwips: colWidth))
          </w:tr>
        </w:tbl>
        """
        chunks.append(xml)
        chunks.append(
            """
            <w:p><w:pPr><w:spacing w:before="100" w:after="100"/></w:pPr></w:p>
            """
        )
    }

    private func comparisonTableCell(innerXML: String, widthTwips: Int) -> String {
        """
        <w:tc>
          <w:tcPr>
            <w:tcW w:w="\(widthTwips)" w:type="dxa"/>
            <w:tcMar>
              <w:top w:w="80" w:type="dxa"/>
              <w:left w:w="100" w:type="dxa"/>
              <w:bottom w:w="80" w:type="dxa"/>
              <w:right w:w="100" w:type="dxa"/>
            </w:tcMar>
          </w:tcPr>
          \(innerXML)
        </w:tc>
        """
    }

    mutating func addEmbeddedImage(rId: String, widthEmu: Int, heightEmu: Int, fileName: String) {
        chunks.append(embeddedImageParagraphXML(rId: rId, widthEmu: widthEmu, heightEmu: heightEmu, fileName: fileName))
    }

    mutating func embeddedImageParagraphXML(rId: String, widthEmu: Int, heightEmu: Int, fileName: String) -> String {
        let dp = docPrCounter
        docPrCounter += 1
        let safeName = xmlEscape(fileName)
        return """
        <w:p>
          <w:r>
            <w:drawing>
              <wp:inline distT="0" distB="0" distL="0" distR="0">
                <wp:extent cx="\(widthEmu)" cy="\(heightEmu)"/>
                <wp:docPr id="\(dp)" name="Picture \(dp)"/>
                <wp:cNvGraphicFramePr>
                  <a:graphicFrameLocks noChangeAspect="1"/>
                </wp:cNvGraphicFramePr>
                <a:graphic>
                  <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                    <pic:pic>
                      <pic:nvPicPr>
                        <pic:cNvPr id="0" name="\(safeName)"/>
                        <pic:cNvPicPr/>
                      </pic:nvPicPr>
                      <pic:blipFill>
                        <a:blip r:embed="\(rId)"/>
                        <a:stretch><a:fillRect/></a:stretch>
                      </pic:blipFill>
                      <pic:spPr>
                        <a:xfrm>
                          <a:off x="0" y="0"/>
                          <a:ext cx="\(widthEmu)" cy="\(heightEmu)"/>
                        </a:xfrm>
                        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                      </pic:spPr>
                    </pic:pic>
                  </a:graphicData>
                </a:graphic>
              </wp:inline>
            </w:drawing>
          </w:r>
        </w:p>
        """
    }

    mutating func closeBodyWithSection() {
        // 2.5 cm 页边距 ≈ 1417 twips；A4
        chunks.append(
            """
            <w:sectPr>
              <w:pgSz w:w="11906" w:h="16838"/>
              <w:pgMar w:top="1417" w:right="1417" w:bottom="1417" w:left="1417" w:header="708" w:footer="708" w:gutter="0"/>
            </w:sectPr>
            """
        )
    }

    private func paragraphCenteredBold(_ text: String, eastAsiaFont: String, fontHalfPt: Int, afterSpacingTwips: Int) -> String {
        let runs = runsForPlainText(text, bold: true, eastAsiaFont: eastAsiaFont, fontHalfPt: fontHalfPt)
        return """
        <w:p>
          <w:pPr>
            <w:jc w:val="center"/>
            <w:spacing w:before="0" w:after="\(afterSpacingTwips)" w:line="360" w:lineRule="auto"/>
          </w:pPr>
          \(runs)
        </w:p>
        """
    }

    private func paragraphLeft(
        _ text: String,
        bold: Bool,
        eastAsiaFont: String = "SimSun",
        fontHalfPt: Int,
        beforeSpacingTwips: Int = 0,
        afterSpacingTwips: Int = 0
    ) -> String {
        let runs = runsForPlainText(text, bold: bold, eastAsiaFont: eastAsiaFont, fontHalfPt: fontHalfPt)
        return """
        <w:p>
          <w:pPr>
            <w:jc w:val="left"/>
            <w:spacing w:before="\(beforeSpacingTwips)" w:after="\(afterSpacingTwips)" w:line="\(Self.bodyLineTwips)" w:lineRule="auto"/>
          </w:pPr>
          \(runs)
        </w:p>
        """
    }

    private func paragraphLeftMultiline(_ text: String, fontHalfPt: Int, afterSpacingTwips: Int) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var inner = ""
        for (i, line) in lines.enumerated() {
            inner += runsForPlainText(line, bold: false, eastAsiaFont: "SimSun", fontHalfPt: fontHalfPt)
            if i < lines.count - 1 {
                inner += "<w:r><w:br/></w:r>"
            }
        }
        return """
        <w:p>
          <w:pPr>
            <w:jc w:val="left"/>
            <w:spacing w:before="0" w:after="\(afterSpacingTwips)" w:line="\(Self.bodyLineTwips)" w:lineRule="auto"/>
          </w:pPr>
          \(inner)
        </w:p>
        """
    }

    private func runsForPlainText(_ text: String, bold: Bool, eastAsiaFont: String, fontHalfPt: Int) -> String {
        let esc = xmlEscape(text)
        let b = bold ? "<w:b/><w:bCs/>" : ""
        let ascii = eastAsiaFont == "SimHei" ? "SimHei" : "SimSun"
        return """
        <w:r>
          <w:rPr>
            <w:rFonts w:ascii="\(ascii)" w:eastAsia="\(eastAsiaFont)" w:hAnsi="\(ascii)"/>
            \(b)
            <w:sz w:val="\(fontHalfPt)"/>
            <w:szCs w:val="\(fontHalfPt)"/>
          </w:rPr>
          <w:t xml:space="preserve">\(esc)</w:t>
        </w:r>
        """
    }
}

private func xmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

// MARK: - 极简 ZIP（STORE + CRC32），满足 .docx 包结构

private enum DocxZip {
    static func build(entries: [(path: String, data: Data)]) -> Data? {
        var main = Data()
        var central = Data()
        var offset: UInt32 = 0
        let utf8NameFlag: UInt16 = 0x0800

        for entry in entries {
            let pathBytes = Data(entry.path.utf8)
            let crc = crc32UInt32(entry.data)
            let size = UInt32(entry.data.count)
            guard let nameLen = UInt16(exactly: pathBytes.count) else { return nil }

            var local = Data()
            local.appendUInt32(0x0403_4b50)
            local.appendUInt16(20)
            local.appendUInt16(utf8NameFlag)
            local.appendUInt16(0)
            local.appendUInt16(0)
            local.appendUInt16(0)
            local.appendUInt32(crc)
            local.appendUInt32(size)
            local.appendUInt32(size)
            local.appendUInt16(nameLen)
            local.appendUInt16(0)
            local.append(pathBytes)

            let localHeaderLen = UInt32(local.count)
            main.append(local)
            main.append(entry.data)

            var cd = Data()
            cd.appendUInt32(0x0201_4b50)
            cd.appendUInt16(20)
            cd.appendUInt16(20)
            cd.appendUInt16(utf8NameFlag)
            cd.appendUInt16(0)
            cd.appendUInt16(0)
            cd.appendUInt16(0)
            cd.appendUInt32(crc)
            cd.appendUInt32(size)
            cd.appendUInt32(size)
            cd.appendUInt16(nameLen)
            cd.appendUInt16(0)
            cd.appendUInt16(0)
            cd.appendUInt16(0)
            cd.appendUInt16(0)
            cd.appendUInt32(0)
            cd.appendUInt32(offset)
            cd.append(pathBytes)
            central.append(cd)

            offset += localHeaderLen + size
        }

        let centralSize = UInt32(central.count)
        let centralOffset = offset

        var eocd = Data()
        eocd.appendUInt32(0x0605_4b50)
        eocd.appendUInt16(0)
        eocd.appendUInt16(0)
        eocd.appendUInt16(UInt16(entries.count))
        eocd.appendUInt16(UInt16(entries.count))
        eocd.appendUInt32(centralSize)
        eocd.appendUInt32(centralOffset)
        eocd.appendUInt16(0)

        main.append(central)
        main.append(eocd)
        return main
    }
}

private func crc32UInt32(_ data: Data) -> UInt32 {
    data.withUnsafeBytes { raw in
        guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
        let len = uInt(min(data.count, Int(UInt32.max)))
        return UInt32(truncatingIfNeeded: crc32(0, base, len))
    }
}

private extension Data {
    mutating func appendUInt16(_ v: UInt16) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ v: UInt32) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}

#endif
