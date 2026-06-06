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

    private static let pageWidth: CGFloat = 595
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat = 72 * 2.5 / 2.54
    private static var contentWidth: CGFloat { pageWidth - margin * 2 }
    private static let rowPadding: CGFloat = 6
    private static let maxImageHeight: CGFloat = 145

    static func buildTemporaryFileURL(
        template: ReportTemplate,
        previewData: ReportTemplatePreviewData
    ) throws -> URL {
        let modules = template.enabledModules
        guard !modules.isEmpty else { throw ExportError.noEnabledModules }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        let data = renderer.pdfData { context in
            context.beginPage()
            var y = margin

            drawParagraph(
                template.name,
                font: .boldSystemFont(ofSize: 22),
                alignment: .center,
                y: &y,
                context: context
            )
            drawParagraph("报告日期：\(previewData.basicInfo.reportDate)", font: .systemFont(ofSize: 12), alignment: .center, y: &y, context: context)
            y += 8

            for module in modules {
                ensureSpace(context, y: &y, needed: 60)
                drawParagraph(module.title, font: .boldSystemFont(ofSize: 16), y: &y, context: context)

                switch module.type {
                case .basicInfo:
                    drawBasicInfo(previewData.basicInfo, y: &y, context: context)
                case .narrative:
                    drawParagraph(previewData.narrative, font: .systemFont(ofSize: 12), y: &y, context: context)
                case .rectificationList:
                    drawRectificationList(previewData.rectificationItems, y: &y, context: context)
                case .photoComparison:
                    drawPhotoComparisons(previewData.photoComparisons, y: &y, context: context)
                case .signature:
                    drawSignature(previewData.signature, y: &y, context: context)
                case .notes:
                    drawNotes(previewData.notes, y: &y, context: context)
                }

                y += 10
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("安全大师_模板报告_\(Int(Date().timeIntervalSince1970)).pdf")
        do {
            try data.write(to: url)
            return url
        } catch {
            throw ExportError.writeFailed
        }
    }

    private static func drawBasicInfo(
        _ info: ReportBasicInfoPreviewData,
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        drawKeyValueRows([
            ("项目名称", info.projectName),
            ("检查单位", info.inspectionUnit),
            ("受检单位", info.inspectedUnit),
            ("检查时间", info.inspectionTime),
            ("记录数量", "\(info.recordCount) 项")
        ], y: &y, context: context)
    }

    private static func drawRectificationList(
        _ items: [ReportRectificationItemPreviewData],
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        let columnWidths: [CGFloat] = [32, 140, 140, 66, contentWidth - 32 - 140 - 140 - 66]
        drawTableRow(["序号", "隐患描述", "整改情况", "风险等级", "责任人"], columnWidths: columnWidths, isHeader: true, y: &y, context: context)
        if items.isEmpty {
            drawTableRow(["-", "未填写", "未填写", "未填写", "未填写"], columnWidths: columnWidths, y: &y, context: context)
            return
        }
        for item in items {
            drawTableRow(
                [
                    "\(item.index)",
                    item.issueDescription,
                    item.rectificationStatus,
                    item.riskLevel,
                    item.responsibleParty
                ],
                columnWidths: columnWidths,
                y: &y,
                context: context
            )
        }
    }

    private static func drawPhotoComparisons(
        _ items: [ReportPhotoComparisonPreviewData],
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        if items.isEmpty {
            drawParagraph("暂无照片", font: .systemFont(ofSize: 12), color: .gray, y: &y, context: context)
            return
        }

        let gap: CGFloat = 12
        let imageWidth = (contentWidth - gap) / 2
        for item in items {
            ensureSpace(context, y: &y, needed: 220)
            drawParagraph("隐患 \(item.index)", font: .boldSystemFont(ofSize: 13), y: &y, context: context)

            let startY = y
            let leftHeight = drawImageOrPlaceholder(
                data: item.beforePhotoData,
                placeholder: "整改前照片未添加",
                x: margin,
                y: y,
                width: imageWidth
            )
            let rightHeight = drawImageOrPlaceholder(
                data: item.afterPhotoData,
                placeholder: "整改后照片未添加",
                x: margin + imageWidth + gap,
                y: y,
                width: imageWidth
            )
            y = startY + max(leftHeight, rightHeight) + 10

            drawLabeledBlock(title: "问题说明", body: item.issueDescription, y: &y, context: context)
            drawLabeledBlock(title: "整改说明", body: item.rectificationDescription, y: &y, context: context)
        }
    }

    private static func drawSignature(
        _ signature: ReportSignaturePreviewData,
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        drawKeyValueRows([
            ("整改负责人", signature.rectificationResponsible),
            ("安全总监", signature.safetyDirector),
            ("项目负责人", signature.projectManager),
            ("复查人", signature.reviewer),
            ("日期", signature.date)
        ], y: &y, context: context)
    }

    private static func drawNotes(
        _ notes: ReportNotesPreviewData,
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        drawLabeledBlock(title: "复查意见", body: notes.reviewOpinion, y: &y, context: context)
        drawLabeledBlock(title: "补充说明", body: notes.supplementaryNotes, y: &y, context: context)
    }

    private static func drawKeyValueRows(
        _ rows: [(String, String)],
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        for row in rows {
            drawLabeledBlock(title: row.0, body: row.1, y: &y, context: context)
        }
    }

    private static func drawTableRow(
        _ values: [String],
        columnWidths: [CGFloat],
        isHeader: Bool = false,
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        let font = isHeader ? UIFont.boldSystemFont(ofSize: 10) : UIFont.systemFont(ofSize: 10)
        let attrs = textAttributes(font: font, color: isHeader ? .black : .darkGray)
        let heights = values.enumerated().map { index, value in
            textHeight(value, width: columnWidths[index] - rowPadding * 2, attributes: attrs) + rowPadding * 2
        }
        let rowHeight = max(28, (heights.max() ?? 28))
        ensureSpace(context, y: &y, needed: rowHeight + 2)

        var x = margin
        for (index, value) in values.enumerated() {
            let width = columnWidths[index]
            let rect = CGRect(x: x, y: y, width: width, height: rowHeight)
            (isHeader ? UIColor(white: 0.94, alpha: 1) : UIColor.white).setFill()
            UIBezierPath(rect: rect).fill()
            UIColor(white: 0.78, alpha: 1).setStroke()
            UIBezierPath(rect: rect).stroke()
            (value as NSString).draw(
                with: rect.insetBy(dx: rowPadding, dy: rowPadding),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs,
                context: nil
            )
            x += width
        }
        y += rowHeight
    }

    private static func drawLabeledBlock(
        title: String,
        body: String,
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        let titleFont = UIFont.boldSystemFont(ofSize: 12)
        let bodyFont = UIFont.systemFont(ofSize: 12)
        let titleAttrs = textAttributes(font: titleFont, color: UIColor(white: 0.18, alpha: 1))
        let bodyAttrs = textAttributes(font: bodyFont)
        let titleText = "\(title)："
        let titleHeight = textHeight(titleText, width: contentWidth, attributes: titleAttrs)
        let bodyHeight = textHeight(body, width: contentWidth, attributes: bodyAttrs)
        ensureSpace(context, y: &y, needed: titleHeight + bodyHeight + 12)

        (titleText as NSString).draw(with: CGRect(x: margin, y: y, width: contentWidth, height: titleHeight), options: [.usesLineFragmentOrigin], attributes: titleAttrs, context: nil)
        y += titleHeight + 2
        (body as NSString).draw(with: CGRect(x: margin, y: y, width: contentWidth, height: bodyHeight), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: bodyAttrs, context: nil)
        y += bodyHeight + 10
    }

    private static func drawParagraph(
        _ text: String,
        font: UIFont,
        color: UIColor = .black,
        alignment: NSTextAlignment = .left,
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        let attrs = textAttributes(font: font, color: color, alignment: alignment)
        let height = textHeight(text, width: contentWidth, attributes: attrs)
        ensureSpace(context, y: &y, needed: height + 8)
        (text as NSString).draw(with: CGRect(x: margin, y: y, width: contentWidth, height: height), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        y += height + 8
    }

    @discardableResult
    private static func drawImageOrPlaceholder(
        data: Data?,
        placeholder: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        guard let data, let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return drawPlaceholder(placeholder, x: x, y: y, width: width)
        }

        let ratio = min(width / image.size.width, maxImageHeight / image.size.height)
        let drawWidth = image.size.width * ratio
        let drawHeight = image.size.height * ratio
        let rect = CGRect(x: x, y: y, width: drawWidth, height: drawHeight)
        image.draw(in: rect)
        UIColor(white: 0.8, alpha: 1).setStroke()
        UIBezierPath(rect: rect).stroke()
        return drawHeight
    }

    @discardableResult
    private static func drawPlaceholder(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        let height: CGFloat = 92
        let rect = CGRect(x: x, y: y, width: width, height: height)
        UIColor(white: 0.96, alpha: 1).setFill()
        UIBezierPath(rect: rect).fill()
        UIColor(white: 0.75, alpha: 1).setStroke()
        UIBezierPath(rect: rect).stroke()
        let attrs = textAttributes(font: .systemFont(ofSize: 11), color: .gray, alignment: .center)
        (text as NSString).draw(with: rect.insetBy(dx: 8, dy: 34), options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
        return height
    }

    private static func ensureSpace(
        _ context: UIGraphicsPDFRendererContext,
        y: inout CGFloat,
        needed: CGFloat
    ) {
        if y + needed > pageHeight - margin {
            context.beginPage()
            y = margin
        }
    }

    private static func textAttributes(
        font: UIFont,
        color: UIColor = .black,
        alignment: NSTextAlignment = .left
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineHeightMultiple = 1.35
        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    }

    private static func textHeight(
        _ text: String,
        width: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGFloat {
        ceil((text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).height)
    }
}

#endif
