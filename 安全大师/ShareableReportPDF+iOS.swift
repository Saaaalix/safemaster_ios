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
    /// 报告内插图最大高度（点），避免单张照片占满一页。
    private static let maxReportImageHeight: CGFloat = 190
    /// 插图最大宽度为正文区域的比例
    private static let maxReportImageWidthFraction: CGFloat = 0.48

    /// 写入临时目录；调用方通过分享面板发出，系统稍后会清理临时文件。
    static func buildTemporaryFileURL(findings: [InspectionFinding], day: Date) throws -> URL {
        let rows = findings.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        guard !rows.isEmpty else { throw BuildError.noFindings }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateStyle = .long
        let dateStr = fmt.string(from: day)

        let bounds = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)

        let data = renderer.pdfData { context in
            context.beginPage()
            var y = margin

            // 版式对齐常用报告：标题居中略大；正文小四 12pt；1.5 倍行距
            drawParagraph(
                "安全大师 · 隐患排查报告",
                font: .boldSystemFont(ofSize: 22),
                alignment: .center,
                lineHeightMultiple: 1.5,
                y: &y,
                context: context
            )
            drawParagraph("日期：\(dateStr)", font: .systemFont(ofSize: 12), lineHeightMultiple: 1.5, y: &y, context: context)
            drawParagraph("共 \(rows.count) 条记录", font: .systemFont(ofSize: 12), lineHeightMultiple: 1.5, y: &y, context: context)
            y += 8
            drawParagraph(String(repeating: "—", count: 28), font: .systemFont(ofSize: 12), lineHeightMultiple: 1.5, y: &y, context: context)
            y += 8

            for (i, f) in rows.enumerated() {
                drawParagraph(
                    "记录 \(i + 1)",
                    font: .boldSystemFont(ofSize: 15),
                    lineHeightMultiple: 1.5,
                    y: &y,
                    context: context
                )

                for d in f.sitePhotoDatasOrdered {
                    guard !d.isEmpty, let ui = UIImage(data: d) else { continue }
                    drawImageIfValid(ui, y: &y, context: context)
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

                let extra = f.supplementaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                drawLabeledBlock(title: "文字说明", body: extra.isEmpty ? "（本条未填写）" : extra, y: &y, context: context)
                drawLabeledBlock(title: "隐患描述", body: f.hazardDescription ?? "—", y: &y, context: context)
                drawLabeledBlock(title: "整改措施", body: f.rectificationMeasures ?? "—", y: &y, context: context)
                drawLabeledBlock(title: "风险等级", body: f.riskLevel ?? "—", y: &y, context: context)
                drawLabeledBlock(
                    title: "事故类别",
                    body: Self.accidentCategoryReportLine(major: f.accidentCategoryMajor, minor: f.accidentCategoryMinor),
                    y: &y,
                    context: context
                )
                drawLabeledBlock(title: "整改依据", body: f.legalBasis ?? "—", y: &y, context: context)

                y += 16
                drawParagraph(String(repeating: "·", count: 20), font: .systemFont(ofSize: 8), color: .gray, y: &y, context: context)
                y += 8
            }
        }

        let name = "安全大师_排查报告_\(Int(Date().timeIntervalSince1970)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return url
        } catch {
            throw BuildError.writeFailed
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
        lineHeightMultiple: CGFloat = 1.5,
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
        ensureSpace(context, y: &y, needed: h + 8)
        let drawRect = CGRect(x: margin, y: y, width: contentW, height: h)
        ns.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        y += h + 8
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
        titlePara.lineHeightMultiple = 1.5
        let bodyPara = NSMutableParagraphStyle()
        bodyPara.lineHeightMultiple = 1.5
        bodyPara.alignment = .justified
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

        let total = titleH + 4 + bodyH + 10
        ensureSpace(context, y: &y, needed: total)

        titleStr.draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
        y += titleH + 4
        bodyStr.draw(
            with: CGRect(x: margin, y: y, width: contentW, height: bodyH),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: bodyAttrs,
            context: nil
        )
        y += bodyH + 10
    }

    private static func drawImageIfValid(_ image: UIImage, y: inout CGFloat, context: UIGraphicsPDFRendererContext) {
        let iw = image.size.width
        let ih = image.size.height
        guard iw > 0, ih > 0, iw.isFinite, ih.isFinite else { return }

        let maxW = contentW * maxReportImageWidthFraction
        var w = min(maxW, iw)
        var h = ih * (w / iw)
        if h > maxReportImageHeight {
            h = maxReportImageHeight
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
        image.draw(in: CGRect(x: margin, y: y, width: w, height: h))
        y += h + 12
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
