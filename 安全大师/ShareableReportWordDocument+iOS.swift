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
        let rows = findings.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        guard !rows.isEmpty else { throw BuildError.noFindings }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateStyle = .long
        let dateStr = fmt.string(from: day)

        var media: [(path: String, data: Data)] = []
        var body = DocxBodyBuilder()

        body.addTitle("安全大师 · 隐患排查报告")
        body.addMetaParagraph("日期：\(dateStr)")
        body.addMetaParagraph("共 \(rows.count) 条记录")
        body.addSeparatorParagraph()

        for (i, f) in rows.enumerated() {
            body.addHeading2("记录 \(i + 1)")

            for d in f.sitePhotoDatasOrdered {
                guard !d.isEmpty, let ui = UIImage(data: d),
                      let jpeg = scaledJPEGForReport(ui, maxWidth: 520) else { continue }
                let name = "image\(media.count + 1).jpeg"
                let pathInZip = "word/media/\(name)"
                media.append((pathInZip, jpeg))
                let (wEmu, hEmu) = imageExtentEmu(for: ui, maxWidthInch: 4)
                body.addEmbeddedImage(rId: body.nextImageRelId(), widthEmu: wEmu, heightEmu: hEmu, fileName: name)
            }

            let loc = (f.location?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "（未填）"
            body.addLabeledBlock(label: "地点", value: loc)

            let disc = f.discoveredAt ?? f.createdAt
            let timeStr: String
            if let disc {
                let tf = DateFormatter()
                tf.locale = Locale(identifier: "zh_CN")
                tf.dateStyle = .medium
                tf.timeStyle = .short
                timeStr = tf.string(from: disc)
            } else {
                timeStr = "—"
            }
            body.addLabeledBlock(label: "发现时间", value: timeStr)

            let extra = f.supplementaryText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            body.addLabeledBlock(label: "文字说明", value: extra.isEmpty ? "（本条未填写）" : extra)
            body.addLabeledBlock(label: "隐患描述", value: f.hazardDescription ?? "—")
            body.addLabeledBlock(label: "整改措施", value: f.rectificationMeasures ?? "—")
            body.addLabeledBlock(label: "风险等级", value: f.riskLevel ?? "—")
            body.addLabeledBlock(
                label: "事故类别",
                value: accidentCategoryReportLine(major: f.accidentCategoryMajor, minor: f.accidentCategoryMinor)
            )
            body.addLabeledBlock(label: "整改依据", value: f.legalBasis ?? "—")
            body.addSeparatorParagraph()
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

        let name = "安全大师_排查报告_\(Int(Date().timeIntervalSince1970)).docx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try zipData.write(to: url)
            return url
        } catch {
            throw BuildError.writeFailed
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
    private static func imageExtentEmu(for image: UIImage, maxWidthInch: CGFloat) -> (Int, Int) {
        let wPt = max(image.size.width, 1)
        let hPt = max(image.size.height, 1)
        let aspect = hPt / wPt
        let wEmu = Int(Double(maxWidthInch * 914_400))
        let hEmu = max(1, Int(Double(wEmu) * Double(aspect)))
        return (wEmu, hEmu)
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

// MARK: - document.xml 拼装（小四 12pt ≈ sz 24；标题 22pt ≈ sz 44）

private struct DocxBodyBuilder {
    private var chunks: [String] = []
    private var imageRelCounter = 1
    private var docPrCounter = 1

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
        chunks.append(paragraphLeft(text, bold: false, fontHalfPt: 24, afterSpacingTwips: 40))
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

    mutating func addLabeledBlock(label: String, value: String) {
        chunks.append(paragraphLeft(label, bold: true, fontHalfPt: 24, beforeSpacingTwips: 120, afterSpacingTwips: 40))
        chunks.append(paragraphJustifiedMultiline(value, fontHalfPt: 24, afterSpacingTwips: 80))
    }

    mutating func addEmbeddedImage(rId: String, widthEmu: Int, heightEmu: Int, fileName: String) {
        let dp = docPrCounter
        docPrCounter += 1
        let safeName = xmlEscape(fileName)
        chunks.append(
            """
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
        )
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
            <w:spacing w:before="\(beforeSpacingTwips)" w:after="\(afterSpacingTwips)" w:line="360" w:lineRule="auto"/>
          </w:pPr>
          \(runs)
        </w:p>
        """
    }

    private func paragraphJustifiedMultiline(_ text: String, fontHalfPt: Int, afterSpacingTwips: Int) -> String {
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
            <w:jc w:val="both"/>
            <w:spacing w:before="0" w:after="\(afterSpacingTwips)" w:line="360" w:lineRule="auto"/>
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
