//
//  ShareableReportPDF+iOS.swift
//  安全大师
//
//  单文件 PDF：版式与「记录详情」一致（先照片再文字），分享为一份整体报告。

#if os(iOS)

import CoreData
import UIKit

enum ShareableReportPDFBuilder {
    enum BuildError: Error {
        case noFindings
        case writeFailed
    }

    private static let pageW: CGFloat = 595
    private static let pageH: CGFloat = 842
    /// 约 2.5 cm（与 Word/HTML 报告边距接近）
    private static let margin: CGFloat = 72 * 2.5 / 2.54
    private static var contentW: CGFloat { pageW - 2 * margin }
    /// 中文正文统一段落样式：左对齐、1.4 倍行距、统一段后距。
    private static let bodyLineHeight: CGFloat = 1.4
    private static let paragraphSpacingAfter: CGFloat = 8
    private static let labelBodySpacing: CGFloat = 4

    /// 写入临时目录；调用方通过分享面板发出，系统稍后会清理临时文件。
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

        let bounds = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)

        let data = renderer.pdfData { context in
            context.beginPage()
            var y = margin

            // 版式对齐常用报告：标题居中略大；正文小四 12pt；1.5 倍行距
            drawParagraph(
                kind.coverTitle,
                font: .boldSystemFont(ofSize: 22),
                alignment: .center,
                lineHeightMultiple: 1.5,
                y: &y,
                context: context
            )
            drawParagraph(
                "文号：\(DaySummaryBuilder.reportDocumentCode(kind: kind, projectName: rows.first?.recordProjectNameSnapshot))",
                font: .systemFont(ofSize: 12),
                lineHeightMultiple: 1.5,
                y: &y,
                context: context
            )
            drawParagraph("项目名称：\(ReportProjectSettingsStore.coverProjectName(for: rows))", font: .systemFont(ofSize: 12), lineHeightMultiple: 1.5, y: &y, context: context)
            drawParagraph(
                kind == .inspection
                    ? "检查人：\(ReportProjectSettingsStore.coverInspectorName(for: rows))"
                    : "回复人：\(ReportProjectSettingsStore.coverInspectorName(for: rows))",
                font: .systemFont(ofSize: 12),
                lineHeightMultiple: 1.5,
                y: &y,
                context: context
            )
            drawParagraph(kind == .inspection ? "检查日期：\(dateStr)" : "回复日期：\(dateStr)", font: .systemFont(ofSize: 12), lineHeightMultiple: 1.5, y: &y, context: context)
            drawParagraph("共 \(rows.count) 条\(kind == .rectification ? "隐患" : "记录")", font: .systemFont(ofSize: 12), lineHeightMultiple: 1.5, y: &y, context: context)
            appendCoverUnitParagraphsPDF(template: template, y: &y, context: context)
            y += 8
            drawParagraph(String(repeating: "—", count: 28), font: .systemFont(ofSize: 12), lineHeightMultiple: 1.5, y: &y, context: context)
            y += 8

            for (i, f) in rows.enumerated() {
                drawParagraph(
                    kind.coverTitle,
                    font: .boldSystemFont(ofSize: 15),
                    lineHeightMultiple: 1.5,
                    y: &y,
                    context: context
                )
                drawLabeledBlock(
                    title: "编号",
                    body: DaySummaryBuilder.itemDocumentCode(kind: kind, finding: f, index: i + 1),
                    y: &y,
                    context: context
                )

                switch kind {
                case .inspection:
                    appendInspectionDetailPDF(finding: f, template: template, y: &y, context: context)
                case .rectification:
                    appendRectificationComparisonPDF(finding: f, template: template, y: &y, context: context)
                }

                y += 16
                drawParagraph(String(repeating: "·", count: 20), font: .systemFont(ofSize: 8), color: .gray, y: &y, context: context)
                y += 8
            }
            if template.includeSignoff {
                appendSignoffPDF(template: template, y: &y, context: context)
            }
            if template.includeLegalAppendix {
                appendLegalBasisAppendixPDF(findings: rows, y: &y, context: context)
            }
        }

        let url = ReportExportFileNameBuilder.fileURL(
            findings: rows,
            kind: kind,
            fileExtension: "pdf"
        )
        do {
            try data.write(to: url)
            return url
        } catch {
            throw BuildError.writeFailed
        }
    }

    private static let comparisonColumnGap: CGFloat = 10

    private static var comparisonColumnWidth: CGFloat {
        (contentW - comparisonColumnGap) / 2
    }

    private static func appendInspectionDetailPDF(
        finding f: InspectionFinding,
        template: ReportTemplateSettings,
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        for d in f.sitePhotoDatasOrdered {
            guard !d.isEmpty, let ui = UIImage(data: d) else { continue }
            drawImageIfValid(ui, template: template, y: &y, context: context)
        }

        let loc = (f.location?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "（未填）"
        drawLabeledBlock(title: "地点", body: loc, y: &y, context: context)

        let discPDF = f.discoveredAt ?? f.createdAt
        let discStr: String
        if let discPDF {
            let tf = DateFormatter()
            tf.locale = Locale(identifier: "zh_CN")
            tf.dateStyle = .medium
            tf.timeStyle = .short
            discStr = tf.string(from: discPDF)
        } else {
            discStr = "—"
        }
        drawLabeledBlock(title: "发现时间", body: discStr, y: &y, context: context)

        appendRiskAndCategoryPDF(finding: f, template: template, y: &y, context: context)
        drawLabeledBlock(title: "存在问题", body: f.reportFormalIssueDescription(), y: &y, context: context)
        drawLabeledBlock(title: "整改要求", body: f.reportFormalRectificationRequirement, y: &y, context: context)
        if template.includeLegalBasis {
            drawLabeledBlock(title: "整改依据", body: f.reportLegalBasisReferenceSummary(), y: &y, context: context)
        }
        drawLabeledBlock(title: "整改责任人", body: f.reportResponsibleParty, y: &y, context: context)
        if template.includeDeadline {
            drawLabeledBlock(title: "限期", body: f.reportDeadlineLine, y: &y, context: context)
        }
    }

    private static func appendCoverUnitParagraphsPDF(
        template: ReportTemplateSettings,
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        let units = [
            ("检查单位", template.inspectionUnit),
            ("施工单位", template.constructionUnit),
            ("监理单位", template.supervisionUnit)
        ]
        for (label, value) in units {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                drawParagraph("\(label)：\(trimmed)", font: .systemFont(ofSize: 12), lineHeightMultiple: 1.5, y: &y, context: context)
            }
        }
    }

    private static func appendRiskAndCategoryPDF(
        finding f: InspectionFinding,
        template: ReportTemplateSettings,
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        if template.includeAccidentCategory, template.includeRiskLevel {
            drawLabeledBlock(
                title: "事故类别 / 风险等级",
                body: "\(Self.accidentCategoryReportLine(major: f.accidentCategoryMajor, minor: f.accidentCategoryMinor)) / \(f.reportRiskLevelDisplay)",
                y: &y,
                context: context
            )
        } else if template.includeAccidentCategory {
            drawLabeledBlock(title: "事故类别", body: f.reportAccidentCategoryDisplay, y: &y, context: context)
        } else if template.includeRiskLevel {
            drawLabeledBlock(title: "风险等级", body: f.reportRiskLevelDisplay, y: &y, context: context)
        }
    }

    private static func appendRectificationComparisonPDF(
        finding f: InspectionFinding,
        template: ReportTemplateSettings,
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        let leftX = margin
        let rightX = margin + comparisonColumnWidth + comparisonColumnGap
        let colW = comparisonColumnWidth
        var leftY = y
        var rightY = y

        drawParagraphInColumn("整改前", x: leftX, width: colW, font: .boldSystemFont(ofSize: 13), alignment: .center, y: &leftY, context: context)
        drawParagraphInColumn("整改后", x: rightX, width: colW, font: .boldSystemFont(ofSize: 13), alignment: .center, y: &rightY, context: context)

        drawLabeledBlockInColumn(
            title: "部位/地点",
            body: f.reportLocationPart,
            x: leftX,
            width: colW,
            y: &leftY,
            context: context
        )

        for d in f.sitePhotoDatasOrdered {
            guard !d.isEmpty, let ui = UIImage(data: d) else { continue }
            drawImageIfValid(ui: ui, x: leftX, maxWidth: colW, template: template, y: &leftY, context: context)
        }
        if f.sitePhotoDatasOrdered.isEmpty {
            drawParagraphInColumn("（无整改前照片）", x: leftX, width: colW, font: .systemFont(ofSize: 11), y: &leftY, context: context)
        }

        if let afterData = f.reportAfterRectificationPhotoData, let after = UIImage(data: afterData) {
            drawImageIfValid(ui: after, x: rightX, maxWidth: colW, template: template, y: &rightY, context: context)
        } else {
            drawParagraphInColumn("（无整改后照片）", x: rightX, width: colW, font: .systemFont(ofSize: 11), y: &rightY, context: context)
        }

        drawLabeledBlockInColumn(
            title: "检查情况",
            body: f.reportFormalInspectionSituation,
            x: leftX,
            width: colW,
            y: &leftY,
            context: context
        )
        drawLabeledBlockInColumn(
            title: "存在问题",
            body: f.reportFormalIssueDescription(),
            x: leftX,
            width: colW,
            y: &leftY,
            context: context
        )
        if template.includeLegalBasis {
            drawLabeledBlockInColumn(
                title: "整改依据",
                body: f.reportLegalBasisReferenceSummary(),
                x: leftX,
                width: colW,
                y: &leftY,
                context: context
            )
        }
        drawLabeledBlockInColumn(
            title: "整改要求",
            body: f.reportFormalRectificationRequirement,
            x: leftX,
            width: colW,
            y: &leftY,
            context: context
        )
        if template.includeRiskLevel {
            drawLabeledBlockInColumn(
                title: "风险等级",
                body: f.reportRiskLevelDisplay,
                x: leftX,
                width: colW,
                y: &leftY,
                context: context
            )
        }
        if template.includeDeadline {
            drawLabeledBlockInColumn(
                title: "限期",
                body: f.reportDeadlineLine,
                x: leftX,
                width: colW,
                y: &leftY,
                context: context
            )
        }
        if template.includeAccidentCategory {
            drawLabeledBlockInColumn(
                title: "事故类别",
                body: f.reportAccidentCategoryDisplay,
                x: leftX,
                width: colW,
                y: &leftY,
                context: context
            )
        }
        drawLabeledBlockInColumn(
            title: "整改情况",
            body: f.reportRectificationSituation,
            x: rightX,
            width: colW,
            y: &rightY,
            context: context
        )
        drawLabeledBlockInColumn(
            title: "整改责任人",
            body: f.reportResponsibleParty,
            x: rightX,
            width: colW,
            y: &rightY,
            context: context
        )
        drawLabeledBlockInColumn(
            title: "验收意见",
            body: f.reportRectificationAcceptanceOpinion,
            x: rightX,
            width: colW,
            y: &rightY,
            context: context
        )
        drawLabeledBlockInColumn(
            title: "验收时间",
            body: f.reportRectificationAcceptanceTime,
            x: rightX,
            width: colW,
            y: &rightY,
            context: context
        )

        y = max(leftY, rightY) + 8
    }

    private static func appendLegalBasisAppendixPDF(
        findings: [InspectionFinding],
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        let appendixRows = findings.compactMap { finding -> (title: String, body: String)? in
            guard let full = finding.reportLegalBasisAppendixText else { return nil }
            return (finding.reportLocationPart, full)
        }
        guard !appendixRows.isEmpty else { return }
        context.beginPage()
        y = margin
        drawParagraph("附录：整改依据原文", font: .boldSystemFont(ofSize: 16), y: &y, context: context)
        for (idx, row) in appendixRows.enumerated() {
            drawLabeledBlock(title: "[\(idx + 1)] \(row.title)", body: row.body, y: &y, context: context)
        }
    }

    private static func appendSignoffPDF(
        template: ReportTemplateSettings,
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        ensureSpace(context, y: &y, needed: 110)
        drawParagraph(String(repeating: "—", count: 24), font: .systemFont(ofSize: 10), color: .gray, y: &y, context: context)
        drawParagraph("签字确认", font: .boldSystemFont(ofSize: 15), y: &y, context: context)
        for label in template.normalized().signoffLabels {
            drawParagraph("\(label)（签字）：___________    日期：___________", font: .systemFont(ofSize: 12), lineHeightMultiple: 1.5, y: &y, context: context)
        }
    }

    private static func ensureSpace(_ context: UIGraphicsPDFRendererContext, y: inout CGFloat, needed: CGFloat) {
        if y + needed > pageH - margin {
            context.beginPage()
            y = margin
        }
    }

    private static func drawParagraph(
        _ text: String,
        font: UIFont,
        color: UIColor = .black,
        alignment: NSTextAlignment = .left,
        lineHeightMultiple: CGFloat = bodyLineHeight,
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        let ns = text as NSString
        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        para.lineBreakMode = .byWordWrapping
        para.lineHeightMultiple = lineHeightMultiple
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: para
        ]
        let maxSize = CGSize(width: contentW, height: .greatestFiniteMagnitude)
        let rect = ns.boundingRect(with: maxSize, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        let h = ceil(rect.height)
        ensureSpace(context, y: &y, needed: h + paragraphSpacingAfter)
        let drawRect = CGRect(x: margin, y: y, width: contentW, height: h)
        ns.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        y += h + paragraphSpacingAfter
    }

    private static func drawLabeledBlock(
        title: String,
        body: String,
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        let titleFont = UIFont.boldSystemFont(ofSize: 12)
        let bodyFont = UIFont.systemFont(ofSize: 12)
        let titlePara = NSMutableParagraphStyle()
        titlePara.lineHeightMultiple = bodyLineHeight
        titlePara.alignment = .left
        let bodyPara = NSMutableParagraphStyle()
        bodyPara.lineHeightMultiple = bodyLineHeight
        bodyPara.alignment = .left
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1),
            .paragraphStyle: titlePara
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.black,
            .paragraphStyle: bodyPara
        ]

        let titleStr = "\(title)" as NSString
        let titleH = ceil(titleStr.boundingRect(
            with: CGSize(width: contentW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: titleAttrs,
            context: nil
        ).height)

        let bodyStr = body as NSString
        let bodyH = ceil(bodyStr.boundingRect(
            with: CGSize(width: contentW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: bodyAttrs,
            context: nil
        ).height)

        let total = titleH + labelBodySpacing + bodyH + paragraphSpacingAfter
        ensureSpace(context, y: &y, needed: total)

        titleStr.draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
        y += titleH + labelBodySpacing
        bodyStr.draw(
            with: CGRect(x: margin, y: y, width: contentW, height: bodyH),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: bodyAttrs,
            context: nil
        )
        y += bodyH + paragraphSpacingAfter
    }

    private static func drawImageIfValid(
        _ image: UIImage,
        template: ReportTemplateSettings,
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        drawImageIfValid(ui: image, x: margin, maxWidth: contentW * template.photoLayout.pdfWidthFraction, template: template, y: &y, context: context)
    }

    private static func drawImageIfValid(
        ui image: UIImage,
        x: CGFloat,
        maxWidth: CGFloat,
        template: ReportTemplateSettings,
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        let iw = image.size.width
        let ih = image.size.height
        guard iw > 0, ih > 0, iw.isFinite, ih.isFinite else { return }

        let maxW = min(maxWidth, contentW * template.photoLayout.pdfWidthFraction)
        var w = min(maxW, iw)
        var h = ih * (w / iw)
        let colMaxH = template.photoLayout.pdfMaxHeight * 0.85
        if h > colMaxH, maxWidth < contentW * 0.6 {
            h = colMaxH
            w = iw * (h / ih)
        } else if h > template.photoLayout.pdfMaxHeight {
            h = template.photoLayout.pdfMaxHeight
            w = iw * (h / ih)
        }
        let maxSinglePageH = pageH - 2 * margin
        if h > maxSinglePageH {
            h = maxSinglePageH
            w = iw * (h / ih)
        }

        if y + h > pageH - margin {
            context.beginPage()
            y = margin
        }

        ensureSpace(context, y: &y, needed: h + 12)
        image.draw(in: CGRect(x: x, y: y, width: w, height: h))
        y += h + 12
    }

    private static func drawParagraphInColumn(
        _ text: String,
        x: CGFloat,
        width: CGFloat,
        font: UIFont,
        color: UIColor = .black,
        alignment: NSTextAlignment = .left,
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        let ns = text as NSString
        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        para.lineBreakMode = .byWordWrapping
        para.lineHeightMultiple = bodyLineHeight
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: para
        ]
        let rect = ns.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        )
        let h = ceil(rect.height)
        ensureSpace(context, y: &y, needed: h + paragraphSpacingAfter)
        ns.draw(with: CGRect(x: x, y: y, width: width, height: h), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        y += h + paragraphSpacingAfter
    }

    private static func drawLabeledBlockInColumn(
        title: String,
        body: String,
        x: CGFloat,
        width: CGFloat,
        y: inout CGFloat,
        context: UIGraphicsPDFRendererContext
    ) {
        let titleFont = UIFont.boldSystemFont(ofSize: 11)
        let bodyFont = UIFont.systemFont(ofSize: 11)
        let titlePara = NSMutableParagraphStyle()
        titlePara.lineHeightMultiple = bodyLineHeight
        titlePara.alignment = .left
        let bodyPara = NSMutableParagraphStyle()
        bodyPara.lineHeightMultiple = bodyLineHeight
        bodyPara.alignment = .left
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1),
            .paragraphStyle: titlePara
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.black,
            .paragraphStyle: bodyPara
        ]

        let titleStr = title as NSString
        let titleH = ceil(titleStr.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: titleAttrs,
            context: nil
        ).height)

        let bodyStr = body as NSString
        let bodyH = ceil(bodyStr.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: bodyAttrs,
            context: nil
        ).height)

        let total = titleH + labelBodySpacing + bodyH + paragraphSpacingAfter
        ensureSpace(context, y: &y, needed: total)

        titleStr.draw(at: CGPoint(x: x, y: y), withAttributes: titleAttrs)
        y += titleH + labelBodySpacing
        bodyStr.draw(
            with: CGRect(x: x, y: y, width: width, height: bodyH),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: bodyAttrs,
            context: nil
        )
        y += bodyH + paragraphSpacingAfter
    }

    private static func accidentCategoryReportLine(major: String?, minor: String?) -> String {
        let maj = major?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let mino = minor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if maj.isEmpty, mino.isEmpty { return "—" }
        if mino.isEmpty { return "大类：\(maj)" }
        if maj.isEmpty { return "细类：\(mino)" }
        return "大类：\(maj)；细类：\(mino)"
    }
}

#endif
