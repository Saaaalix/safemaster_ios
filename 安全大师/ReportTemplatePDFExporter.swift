//
//  ReportTemplatePDFExporter.swift
//  安全大师
//

#if os(iOS)

import UIKit

enum ReportTemplatePDFExporter {
    enum ExportError: LocalizedError {
        case noEnabledModules
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .noEnabledModules:
                return "请至少开启一个报告模块后再导出。"
            case .writeFailed:
                return "无法写入临时 PDF 文件。"
            }
        }
    }

    static func buildTemporaryFileURL(
        template: ReportTemplate,
        previewData: ReportTemplatePreviewData,
        editableFields: ReportTemplateEditableFields,
        documentKind: ReportDocumentKind = .rectificationReply
    ) throws -> URL {
        let modules = template.enabledModules
        guard !modules.isEmpty else { throw ExportError.noEnabledModules }

        let pageCount = renderPDF(
            template: template,
            modules: modules,
            previewData: previewData,
            editableFields: editableFields,
            documentKind: documentKind,
            totalPages: nil
        ).pageCount
        let rendered = renderPDF(
            template: template,
            modules: modules,
            previewData: previewData,
            editableFields: editableFields,
            documentKind: documentKind,
            totalPages: pageCount
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("安全大师_模板报告_\(Int(Date().timeIntervalSince1970)).pdf")
        do {
            try rendered.data.write(to: url)
            return url
        } catch {
            throw ExportError.writeFailed
        }
    }

    private static func renderPDF(
        template: ReportTemplate,
        modules: [ReportModule],
        previewData: ReportTemplatePreviewData,
        editableFields: ReportTemplateEditableFields,
        documentKind: ReportDocumentKind,
        totalPages: Int?
    ) -> (data: Data, pageCount: Int) {
        let bounds = CGRect(x: 0, y: 0, width: PDFPage.width, height: PDFPage.height)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        var finalPageCount = 0
        let data = renderer.pdfData { context in
            var session = PDFDrawingSession(context: context, totalPages: totalPages)
            session.beginPage()
            drawCoverTitle(template: template, previewData: previewData, editableFields: editableFields, session: &session)

            for module in modules {
                session.ensureSpace(64)
                session.drawSectionTitle(module.title)
                switch module.type {
                case .basicInfo:
                    drawBasicInfo(previewData.basicInfo, editableFields: editableFields, documentKind: documentKind, session: &session)
                case .narrative:
                    session.drawParagraph(editableFields.displayValue(\.narrativeText), firstLineHeadIndent: 24)
                case .rectificationList:
                    drawRectificationList(previewData.rectificationItems, session: &session)
                case .photoComparison:
                    drawPhotoComparisons(previewData.photoComparisons, session: &session)
                case .signature:
                    drawSignature(editableFields, documentKind: documentKind, session: &session)
                case .notes:
                    drawNotes(editableFields, documentKind: documentKind, session: &session)
                }
                session.y += 12
            }
            session.finish()
            finalPageCount = session.pageNumber
        }
        return (data, finalPageCount)
    }

    private static func drawCoverTitle(
        template: ReportTemplate,
        previewData: ReportTemplatePreviewData,
        editableFields: ReportTemplateEditableFields,
        session: inout PDFDrawingSession
    ) {
        session.drawParagraph(
            editableFields.displayValue(\.reportTitle, fallback: template.name),
            font: .boldSystemFont(ofSize: 24),
            alignment: .center,
            lineHeightMultiple: 1.3,
            bottomSpacing: 6
        )
        session.drawParagraph(
            "报告日期：\(editableFields.displayValue(\.signatureDate, fallback: previewData.basicInfo.reportDate))",
            font: .systemFont(ofSize: 12),
            color: .darkGray,
            alignment: .center,
            bottomSpacing: 18
        )
        session.drawDivider()
    }

    private static func drawBasicInfo(
        _ info: ReportBasicInfoPreviewData,
        editableFields: ReportTemplateEditableFields,
        documentKind: ReportDocumentKind,
        session: inout PDFDrawingSession
    ) {
        let rows: [(String, String)]
        switch documentKind {
        case .hazardNotice:
            rows = [
                ("通知编号", editableFields.displayValue(\.noticeNumber)),
                ("检查单位", editableFields.displayValue(\.inspectionUnit)),
                ("受检单位", editableFields.displayValue(\.inspectedUnit)),
                ("检查时间", editableFields.displayValue(\.inspectionDate)),
                ("整改期限", editableFields.displayValue(\.rectificationDeadline)),
                ("检查人", editableFields.displayValue(\.inspector)),
                ("接收人", editableFields.displayValue(\.receiver)),
                ("隐患数量", "\(info.recordCount) 项")
            ]
        case .rectificationReply:
            rows = [
                ("项目名称", editableFields.displayValue(\.projectName)),
                ("受检单位", editableFields.displayValue(\.inspectedUnit)),
                ("检查时间", editableFields.displayValue(\.inspectionDate)),
                ("记录数量", "\(info.recordCount) 项")
            ]
        case .safetyEducationRecord:
            rows = [
                ("教育主题", editableFields.displayValue(\.educationTopic)),
                ("教育时间", editableFields.displayValue(\.educationDate)),
                ("教育地点", editableFields.displayValue(\.educationLocation)),
                ("主讲人", editableFields.displayValue(\.lecturer)),
                ("参加人员", editableFields.displayValue(\.participants))
            ]
        case .monthlyReport:
            rows = [
                ("月份", editableFields.displayValue(\.reportMonth)),
                ("本月检查次数", editableFields.displayValue(\.monthlyInspectionCount)),
                ("本月隐患数量", editableFields.displayValue(\.monthlyHazardCount)),
                ("已整改数量", editableFields.displayValue(\.monthlyRectifiedCount)),
                ("未整改数量", editableFields.displayValue(\.monthlyUnrectifiedCount)),
                ("教育培训次数", editableFields.displayValue(\.monthlyEducationCount))
            ]
        }
        session.drawKeyValueTable(rows)
    }

    private static func drawRectificationList(
        _ items: [ReportRectificationItemPreviewData],
        session: inout PDFDrawingSession
    ) {
        let columns: [PDFTableColumn] = [
            PDFTableColumn(title: "序号", width: 32),
            PDFTableColumn(title: "隐患描述", width: 142),
            PDFTableColumn(title: "整改措施/整改情况", width: 152),
            PDFTableColumn(title: "风险等级", width: 64),
            PDFTableColumn(title: "责任人", width: PDFPage.contentWidth - 32 - 142 - 152 - 64)
        ]
        session.drawTableHeader(columns: columns)
        if items.isEmpty {
            session.drawTableRow(["-", "未填写", "未填写", "未填写", "未填写"], columns: columns, repeatsHeader: true)
            return
        }
        for item in items {
            session.drawTableRow(
                [
                    "\(item.index)",
                    item.issueDescription,
                    item.rectificationStatus,
                    item.riskLevel,
                    item.responsibleParty
                ],
                columns: columns,
                repeatsHeader: true
            )
        }
    }

    private static func drawPhotoComparisons(
        _ items: [ReportPhotoComparisonPreviewData],
        session: inout PDFDrawingSession
    ) {
        guard !items.isEmpty else {
            session.drawBorderedText(title: nil, body: "暂无照片")
            return
        }

        for item in items {
            session.ensureSpace(260)
            session.drawSmallHeading("隐患 \(item.index)")
            session.drawBorderedText(title: "问题说明", body: item.issueDescription)
            session.drawBorderedText(title: "整改说明", body: item.rectificationDescription)

            let imageHeight: CGFloat = 145
            session.ensureSpace(imageHeight + 34)
            let gap: CGFloat = 14
            let imageWidth = (PDFPage.contentWidth - gap) / 2
            let top = session.y
            session.drawImageBox(
                data: item.beforePhotoData,
                placeholder: "整改前照片未添加",
                title: "整改前",
                rect: CGRect(x: PDFPage.margin, y: top, width: imageWidth, height: imageHeight)
            )
            session.drawImageBox(
                data: item.afterPhotoData,
                placeholder: "整改后照片未添加",
                title: "整改后",
                rect: CGRect(x: PDFPage.margin + imageWidth + gap, y: top, width: imageWidth, height: imageHeight)
            )
            session.y = top + imageHeight + 34
        }
    }

    private static func drawSignature(
        _ editableFields: ReportTemplateEditableFields,
        documentKind: ReportDocumentKind,
        session: inout PDFDrawingSession
    ) {
        let rows: [(String, String)]
        if documentKind == .hazardNotice {
            rows = [
                ("检查人", editableFields.displayValue(\.inspector)),
                ("接收人", editableFields.displayValue(\.receiver)),
                ("日期", editableFields.displayValue(\.signatureDate))
            ]
        } else if documentKind == .safetyEducationRecord {
            rows = [
                ("主讲人", editableFields.displayValue(\.lecturer)),
                ("参加人员", editableFields.displayValue(\.participants)),
                ("日期", editableFields.displayValue(\.signatureDate))
            ]
        } else {
            rows = [
                ("整改负责人", editableFields.displayValue(\.rectificationResponsiblePerson)),
                ("安全总监", editableFields.displayValue(\.safetyDirector)),
                ("项目负责人", editableFields.displayValue(\.projectManager)),
                ("复查人", editableFields.displayValue(\.reviewer)),
                ("日期", editableFields.displayValue(\.signatureDate))
            ]
        }
        session.drawSignatureGrid(rows)
    }

    private static func drawNotes(
        _ editableFields: ReportTemplateEditableFields,
        documentKind: ReportDocumentKind,
        session: inout PDFDrawingSession
    ) {
        switch documentKind {
        case .monthlyReport:
            session.drawBorderedText(
                title: "下月计划",
                body: editableFields.displayValue(\.nextMonthPlan, fallback: "暂无备注")
            )
        case .safetyEducationRecord:
            session.drawBorderedText(
                title: "教育内容",
                body: editableFields.displayValue(\.educationContent, fallback: "暂无备注")
            )
        default:
            session.drawBorderedText(
                title: "复查意见",
                body: editableFields.displayValue(\.reviewOpinion, fallback: "暂无备注")
            )
        }
        session.drawBorderedText(
            title: "补充说明",
            body: editableFields.displayValue(\.additionalNotes, fallback: "暂无备注")
        )
    }
}

private enum PDFPage {
    static let width: CGFloat = 595
    static let height: CGFloat = 842
    static let margin: CGFloat = 62
    static let footerHeight: CGFloat = 32
    static var contentWidth: CGFloat { width - margin * 2 }
    static var contentBottom: CGFloat { height - margin - footerHeight }
}

private struct PDFTableColumn {
    var title: String
    var width: CGFloat
}

private struct PDFDrawingSession {
    var context: UIGraphicsPDFRendererContext
    var totalPages: Int?
    var pageNumber = 0
    var y: CGFloat = PDFPage.margin
    private var lastTableColumns: [PDFTableColumn] = []

    init(context: UIGraphicsPDFRendererContext, totalPages: Int?) {
        self.context = context
        self.totalPages = totalPages
    }

    mutating func beginPage() {
        context.beginPage()
        pageNumber += 1
        y = PDFPage.margin
    }

    mutating func finish() {
        drawFooterIfNeeded()
    }

    mutating func ensureSpace(_ needed: CGFloat) {
        if y + needed > PDFPage.contentBottom {
            drawFooterIfNeeded()
            beginPage()
        }
    }

    mutating func drawSectionTitle(_ title: String) {
        drawParagraph(title, font: .boldSystemFont(ofSize: 16), bottomSpacing: 8)
    }

    mutating func drawSmallHeading(_ title: String) {
        drawParagraph(title, font: .boldSystemFont(ofSize: 13), bottomSpacing: 6)
    }

    mutating func drawParagraph(
        _ text: String,
        font: UIFont = .systemFont(ofSize: 12),
        color: UIColor = .black,
        alignment: NSTextAlignment = .left,
        lineHeightMultiple: CGFloat = 1.45,
        firstLineHeadIndent: CGFloat = 0,
        bottomSpacing: CGFloat = 10
    ) {
        let attrs = Self.textAttributes(
            font: font,
            color: color,
            alignment: alignment,
            lineHeightMultiple: lineHeightMultiple,
            firstLineHeadIndent: firstLineHeadIndent
        )
        let height = Self.textHeight(text, width: PDFPage.contentWidth, attributes: attrs)
        ensureSpace(height + bottomSpacing)
        (text as NSString).draw(
            with: CGRect(x: PDFPage.margin, y: y, width: PDFPage.contentWidth, height: height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        )
        y += height + bottomSpacing
    }

    mutating func drawDivider() {
        ensureSpace(14)
        UIColor(white: 0.78, alpha: 1).setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: PDFPage.margin, y: y))
        path.addLine(to: CGPoint(x: PDFPage.width - PDFPage.margin, y: y))
        path.lineWidth = 0.8
        path.stroke()
        y += 18
    }

    mutating func drawKeyValueTable(_ rows: [(String, String)]) {
        let labelWidth: CGFloat = 110
        for row in rows {
            let labelAttrs = Self.textAttributes(font: .boldSystemFont(ofSize: 11), color: .darkGray)
            let valueAttrs = Self.textAttributes(font: .systemFont(ofSize: 11))
            let labelHeight = Self.textHeight(row.0, width: labelWidth - 12, attributes: labelAttrs)
            let valueHeight = Self.textHeight(row.1, width: PDFPage.contentWidth - labelWidth - 12, attributes: valueAttrs)
            let rowHeight = max(28, max(labelHeight, valueHeight) + 12)
            ensureSpace(rowHeight)
            drawCellBackground(CGRect(x: PDFPage.margin, y: y, width: labelWidth, height: rowHeight), fill: UIColor(white: 0.95, alpha: 1))
            drawCellBackground(CGRect(x: PDFPage.margin + labelWidth, y: y, width: PDFPage.contentWidth - labelWidth, height: rowHeight))
            (row.0 as NSString).draw(
                with: CGRect(x: PDFPage.margin + 6, y: y + 6, width: labelWidth - 12, height: rowHeight - 12),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: labelAttrs,
                context: nil
            )
            (row.1 as NSString).draw(
                with: CGRect(x: PDFPage.margin + labelWidth + 6, y: y + 6, width: PDFPage.contentWidth - labelWidth - 12, height: rowHeight - 12),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: valueAttrs,
                context: nil
            )
            y += rowHeight
        }
        y += 12
    }

    mutating func drawTableHeader(columns: [PDFTableColumn]) {
        lastTableColumns = columns
        let attrs = Self.textAttributes(font: .boldSystemFont(ofSize: 10))
        let heights = columns.map { Self.textHeight($0.title, width: $0.width - 10, attributes: attrs) + 10 }
        let rowHeight = max(28, heights.max() ?? 28)
        ensureSpace(rowHeight)
        drawTableCells(columns.map(\.title), columns: columns, rowHeight: rowHeight, attrs: attrs, fill: UIColor(white: 0.93, alpha: 1))
    }

    mutating func drawTableRow(_ values: [String], columns: [PDFTableColumn], repeatsHeader: Bool) {
        let attrs = Self.textAttributes(font: .systemFont(ofSize: 10), color: .darkGray)
        let heights = values.enumerated().map { index, value in
            Self.textHeight(value, width: columns[index].width - 10, attributes: attrs) + 10
        }
        let rowHeight = max(30, heights.max() ?? 30)
        if y + rowHeight > PDFPage.contentBottom {
            drawFooterIfNeeded()
            beginPage()
            if repeatsHeader {
                drawTableHeader(columns: columns)
            }
        }
        drawTableCells(values, columns: columns, rowHeight: rowHeight, attrs: attrs, fill: .white)
    }

    mutating func drawBorderedText(title: String?, body: String) {
        let titleAttrs = Self.textAttributes(font: .boldSystemFont(ofSize: 11), color: .darkGray)
        let bodyAttrs = Self.textAttributes(font: .systemFont(ofSize: 11), lineHeightMultiple: 1.4)
        let titleHeight: CGFloat = title.map { Self.textHeight($0, width: PDFPage.contentWidth - 14, attributes: titleAttrs) + 4 } ?? 0
        let bodyHeight = Self.textHeight(body, width: PDFPage.contentWidth - 14, attributes: bodyAttrs)
        let boxHeight = max(44, titleHeight + bodyHeight + 16)
        ensureSpace(boxHeight + 8)
        let rect = CGRect(x: PDFPage.margin, y: y, width: PDFPage.contentWidth, height: boxHeight)
        drawCellBackground(rect)
        var textY = y + 8
        if let title {
            (title as NSString).draw(
                with: CGRect(x: PDFPage.margin + 7, y: textY, width: PDFPage.contentWidth - 14, height: titleHeight),
                options: [.usesLineFragmentOrigin],
                attributes: titleAttrs,
                context: nil
            )
            textY += titleHeight
        }
        (body as NSString).draw(
            with: CGRect(x: PDFPage.margin + 7, y: textY, width: PDFPage.contentWidth - 14, height: bodyHeight),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: bodyAttrs,
            context: nil
        )
        y += boxHeight + 10
    }

    mutating func drawSignatureGrid(_ rows: [(String, String)]) {
        let colGap: CGFloat = 16
        let colWidth = (PDFPage.contentWidth - colGap) / 2
        let rowHeight: CGFloat = 38
        for pairStart in stride(from: 0, to: rows.count, by: 2) {
            ensureSpace(rowHeight)
            for offset in 0..<2 {
                let index = pairStart + offset
                guard rows.indices.contains(index) else { continue }
                let x = PDFPage.margin + CGFloat(offset) * (colWidth + colGap)
                drawSignatureCell(title: rows[index].0, value: rows[index].1, rect: CGRect(x: x, y: y, width: colWidth, height: rowHeight))
            }
            y += rowHeight + 10
        }
    }

    func drawImageBox(data: Data?, placeholder: String, title: String, rect: CGRect) {
        let imageRect = rect.insetBy(dx: 0, dy: 18)
        if let data, let image = UIImage(data: data), image.size.width > 1, image.size.height > 1 {
            drawFittedImage(image, in: imageRect)
        } else {
            drawPlaceholder(placeholder, in: imageRect)
        }
        let attrs = Self.textAttributes(font: .boldSystemFont(ofSize: 10), color: .darkGray, alignment: .center)
        (title as NSString).draw(
            with: CGRect(x: rect.minX, y: imageRect.maxY + 5, width: rect.width, height: 16),
            options: [.usesLineFragmentOrigin],
            attributes: attrs,
            context: nil
        )
    }

    private func drawFittedImage(_ image: UIImage, in rect: CGRect) {
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let imageRect = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        UIColor(white: 0.98, alpha: 1).setFill()
        UIBezierPath(rect: rect).fill()
        image.draw(in: imageRect)
        UIColor(white: 0.75, alpha: 1).setStroke()
        UIBezierPath(rect: rect).stroke()
    }

    private func drawPlaceholder(_ text: String, in rect: CGRect) {
        UIColor(white: 0.96, alpha: 1).setFill()
        UIBezierPath(rect: rect).fill()
        UIColor(white: 0.75, alpha: 1).setStroke()
        UIBezierPath(rect: rect).stroke()
        let attrs = Self.textAttributes(font: .systemFont(ofSize: 11), color: .gray, alignment: .center)
        (text as NSString).draw(
            with: rect.insetBy(dx: 8, dy: max(8, rect.height / 2 - 10)),
            options: [.usesLineFragmentOrigin],
            attributes: attrs,
            context: nil
        )
    }

    private mutating func drawTableCells(
        _ values: [String],
        columns: [PDFTableColumn],
        rowHeight: CGFloat,
        attrs: [NSAttributedString.Key: Any],
        fill: UIColor
    ) {
        var x = PDFPage.margin
        for (index, value) in values.enumerated() {
            let width = columns[index].width
            let rect = CGRect(x: x, y: y, width: width, height: rowHeight)
            drawCellBackground(rect, fill: fill)
            (value as NSString).draw(
                with: rect.insetBy(dx: 5, dy: 5),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs,
                context: nil
            )
            x += width
        }
        y += rowHeight
    }

    private func drawCellBackground(_ rect: CGRect, fill: UIColor = .white) {
        fill.setFill()
        UIBezierPath(rect: rect).fill()
        UIColor(white: 0.72, alpha: 1).setStroke()
        let path = UIBezierPath(rect: rect)
        path.lineWidth = 0.6
        path.stroke()
    }

    private func drawSignatureCell(title: String, value: String, rect: CGRect) {
        let attrs = Self.textAttributes(font: .systemFont(ofSize: 11))
        let text = "\(title)：\(value)"
        (text as NSString).draw(
            with: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 18),
            options: [.usesLineFragmentOrigin],
            attributes: attrs,
            context: nil
        )
        UIColor(white: 0.35, alpha: 1).setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + 66, y: rect.minY + 28))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 28))
        path.lineWidth = 0.7
        path.stroke()
    }

    private func drawFooterIfNeeded() {
        guard let totalPages else { return }
        let footer = "第 \(pageNumber) 页 / 共 \(totalPages) 页"
        let attrs = Self.textAttributes(font: .systemFont(ofSize: 10), color: .gray, alignment: .center)
        (footer as NSString).draw(
            with: CGRect(x: PDFPage.margin, y: PDFPage.height - PDFPage.margin - 8, width: PDFPage.contentWidth, height: 16),
            options: [.usesLineFragmentOrigin],
            attributes: attrs,
            context: nil
        )
    }

    private static func textAttributes(
        font: UIFont,
        color: UIColor = .black,
        alignment: NSTextAlignment = .left,
        lineHeightMultiple: CGFloat = 1.35,
        firstLineHeadIndent: CGFloat = 0
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineHeightMultiple = lineHeightMultiple
        paragraph.firstLineHeadIndent = firstLineHeadIndent
        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    }

    private static func textHeight(_ text: String, width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        ceil((text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).height)
    }
}

#endif
