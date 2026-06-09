//
//  ExternalNoticeRecognizer.swift
//  安全大师
//

import Foundation

enum ExternalNoticeRecognizedField: CaseIterable {
    case documentType
    case issuer
    case inspectedUnit
    case inspectorName
    case noticeNo
    case noticeDate
    case projectName
    case hazardCount
    case responsibleParty
    case dueDate
    case location
    case hazardDescription
    case rectificationMeasures
    case rectificationSituation
    case legalBasis
    case summary
}

struct ExternalNoticeIssueItem: Hashable {
    var title: String
    var location: String?
    var hazardDescription: String
    var rectificationMeasures: String?
}

enum ExternalNoticeRecognitionStatus: Hashable {
    case archiveFieldsRecognized
    case archiveFieldsNeedSupplement
}

struct ExternalNoticeRecognitionDraft {
    var documentType: ImportedNoticeDocumentType = .unknown
    var originalText: String = ""
    var cleanedText: String = ""
    var summary: String?
    var issuer: String?
    var inspectedUnit: String?
    var inspectorName: String?
    var noticeNo: String?
    var noticeDate: Date?
    var projectName: String?
    var hazardCount: Int?
    var responsibleParty: String?
    var dueDate: Date?
    var location: String?
    var hazardDescription: String?
    var rectificationMeasures: String?
    var rectificationSituation: String?
    var legalBasis: String?
    var issueItems: [ExternalNoticeIssueItem] = []
    var status: ExternalNoticeRecognitionStatus = .archiveFieldsNeedSupplement
    var hazardsRecognized: Bool = false
    var confidence: [ExternalNoticeRecognizedField: Double] = [:]
    var warnings: [String] = []
}

enum ExternalNoticeRecognizer {
    static func recognize(from rawText: String) -> ExternalNoticeRecognitionDraft {
        let text = normalize(rawText)
        var draft = ExternalNoticeRecognitionDraft()
        draft.originalText = rawText
        draft.cleanedText = text

        draft.issuer = matchLineValue(
            in: text,
            labels: ["发文单位", "检查单位", "通知单位", "下发单位", "签发单位"]
        )
        if draft.issuer != nil { draft.confidence[.issuer] = 0.92 }

        draft.noticeNo = matchLineValue(
            in: text,
            labels: ["通知单编号", "文号", "编号", "通知编号"]
        )
        if draft.noticeNo != nil { draft.confidence[.noticeNo] = 0.95 }

        draft.inspectedUnit = matchLineValue(
            in: text,
            labels: ["受检单位", "被检单位", "受查单位", "项目部"]
        )
        if draft.inspectedUnit != nil { draft.confidence[.inspectedUnit] = 0.9 }

        draft.projectName = matchLineValue(
            in: text,
            labels: ["项目名称", "工程名称", "项目", "工程项目"]
        )
        if draft.projectName == nil {
            draft.projectName = extractProjectNameFromInspectedUnit(in: text)
            if draft.projectName != nil { draft.confidence[.projectName] = 0.78 }
        }
        if draft.projectName != nil { draft.confidence[.projectName] = 0.9 }

        draft.issueItems = parseIssueItems(from: text)
        draft.hazardsRecognized = !draft.issueItems.isEmpty
        if let explicitCount = matchHazardCount(in: text) {
            draft.hazardCount = explicitCount
            draft.confidence[.hazardCount] = 0.9
        } else if !draft.issueItems.isEmpty {
            draft.hazardCount = draft.issueItems.count
            draft.confidence[.hazardCount] = 0.74
        }

        draft.responsibleParty = matchLineValue(
            in: text,
            labels: ["整改责任人", "责任人", "责任单位", "整改负责人", "整改责任单位", "落实责任人"]
        )
        if draft.responsibleParty != nil { draft.confidence[.responsibleParty] = 0.86 }

        draft.inspectorName = matchLineValue(
            in: text,
            labels: ["检查人", "检查人员", "检查考核负责人", "检查组成员", "复查人", "检查负责人"]
        )
        if draft.inspectorName != nil { draft.confidence[.inspectorName] = 0.84 }

        draft.location = matchLineValue(
            in: text,
            labels: ["隐患部位", "隐患地点", "整改部位", "部位", "地点"]
        )
        if draft.location != nil { draft.confidence[.location] = 0.88 }

        draft.rectificationSituation = matchMultiLineValue(
            in: text,
            labels: ["整改情况", "整改完成情况", "处理结果", "复查情况", "落实情况"],
            maxLength: 320
        )
        if draft.rectificationSituation != nil { draft.confidence[.rectificationSituation] = 0.88 }

        draft.legalBasis = matchMultiLineValue(
            in: text,
            labels: ["整改依据", "法律依据", "依据条款", "参考依据"],
            maxLength: 320
        )
        if draft.legalBasis != nil { draft.confidence[.legalBasis] = 0.82 }

        draft.noticeDate = matchDate(
            in: text,
            labels: ["来文日期", "下发日期", "通知日期", "检查日期", "检查时间"]
        )
        if draft.noticeDate != nil { draft.confidence[.noticeDate] = 0.93 }

        draft.dueDate = matchDate(
            in: text,
            labels: ["整改期限", "整改完成期限", "限期整改", "完成时限", "整改截至", "整改截止日期", "限期完成时间"]
        )
        if draft.dueDate != nil { draft.confidence[.dueDate] = 0.9 }

        draft.documentType = inferDocumentType(from: text, draft: draft)
        if draft.documentType != .unknown {
            draft.confidence[.documentType] = 0.82
        }

        // 外部通知导入采用归档优先策略。
        // hazards 仅作为可选参考信息，不作为建档失败或入库阻断条件。
        if draft.hazardDescription == nil {
            draft.hazardDescription = draft.issueItems.first?.hazardDescription
                ?? fallbackHazardDescription(from: extractIssueFocusedText(from: text))
            if draft.hazardDescription != nil { draft.confidence[.hazardDescription] = draft.issueItems.isEmpty ? 0.58 : 0.72 }
        }
        if draft.rectificationMeasures == nil {
            draft.rectificationMeasures = draft.issueItems.first?.rectificationMeasures
                ?? fallbackRectificationMeasures(from: extractIssueFocusedText(from: text))
            if draft.rectificationMeasures != nil { draft.confidence[.rectificationMeasures] = draft.issueItems.isEmpty ? 0.55 : 0.7 }
        }
        if draft.location == nil, let location = draft.issueItems.first?.location {
            draft.location = location
            draft.confidence[.location] = 0.66
        }
        let hasHazardDescription = draft.hazardDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        let hasRectificationMeasures = draft.rectificationMeasures?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        draft.hazardsRecognized = draft.hazardsRecognized
            || hasHazardDescription
            || hasRectificationMeasures

        draft.summary = summary(from: draft, text: text)
        if draft.summary != nil { draft.confidence[.summary] = 0.7 }
        draft.status = archiveFieldRecognitionStatus(for: draft)

        if draft.projectName == nil {
            draft.warnings.append("未识别出“项目名称”，请手动补充。")
        }
        if draft.issuer == nil {
            draft.warnings.append("未识别出“检查单位/发文单位”，请手动补充。")
        }
        if draft.noticeDate == nil {
            draft.warnings.append("未识别出“检查时间/来文日期”，请手动补充。")
        }
        if !draft.hazardsRecognized {
            draft.warnings.append("隐患条目未完整识别，不影响归档。你可以归档后在记录详情中继续补充。")
        }
        return draft
    }

    private static func archiveFieldRecognitionStatus(for draft: ExternalNoticeRecognitionDraft) -> ExternalNoticeRecognitionStatus {
        let recognizedArchiveFields = [
            draft.issuer,
            draft.noticeNo,
            draft.inspectedUnit,
            draft.projectName,
            draft.noticeDate.map { _ in "date" },
            draft.dueDate.map { _ in "deadline" },
            draft.summary
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return recognizedArchiveFields.count >= 2 ? .archiveFieldsRecognized : .archiveFieldsNeedSupplement
    }

    private static func inferDocumentType(from text: String, draft: ExternalNoticeRecognitionDraft) -> ImportedNoticeDocumentType {
        let rectificationKeywords = ["整改完成", "整改情况", "复查意见", "验收通过", "闭环", "复查结论", "已整改", "整改回复"]
        let hazardKeywords = ["限期整改", "存在问题", "隐患", "整改要求", "整改期限", "责令"]
        let rectificationScore = rectificationKeywords.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
            + (draft.rectificationSituation == nil ? 0 : 2)
        let hazardScore = hazardKeywords.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
            + (draft.dueDate == nil ? 0 : 1)
            + (draft.issueItems.isEmpty ? 0 : 1)
        if rectificationScore > hazardScore {
            return .rectificationReply
        }
        if hazardScore > 0 {
            return .hazardNotice
        }
        return .unknown
    }

    private static func summary(from draft: ExternalNoticeRecognitionDraft, text: String) -> String? {
        let candidates = [
            draft.projectName,
            draft.noticeNo,
            draft.hazardDescription,
            draft.rectificationSituation,
            firstMeaningfulLine(in: text)
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private static func firstMeaningfulLine(in text: String) -> String? {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.count >= 8 && !looksLikeLabelLine($0) }
            .map { String($0.prefix(120)) }
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "：", with: ":")
    }

    private static func matchLineValue(in text: String, labels: [String]) -> String? {
        if let value = matchColonLineValue(in: text, labels: labels) {
            return value
        }
        if let value = matchNextLineValue(in: text, labels: labels) {
            return value
        }
        return nil
    }

    private static func matchColonLineValue(in text: String, labels: [String]) -> String? {
        for label in labels {
            if let value = capture(
                pattern: "(?:^|\\n)\\s*\(NSRegularExpression.escapedPattern(for: label))\\s*[:：]\\s*([^\\n]+)",
                in: text
            ) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func matchNextLineValue(in text: String, labels: [String]) -> String? {
        let lines = text.components(separatedBy: .newlines)
        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard labels.contains(where: { line == $0 || line.hasPrefix($0) }) else { continue }
            var collected: [String] = []
            var cursor = index + 1
            while cursor < lines.count && collected.count < 3 {
                let candidate = lines[cursor].trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.isEmpty {
                    if !collected.isEmpty { break }
                    cursor += 1
                    continue
                }
                if looksLikeLabelLine(candidate) { break }
                collected.append(candidate)
                cursor += 1
            }
            let merged = collected.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if merged.count >= 2 {
                return merged
            }
        }
        return nil
    }

    private static func matchMultiLineValue(in text: String, labels: [String], maxLength: Int) -> String? {
        for label in labels {
            if let value = captureLabeledSegment(in: text, label: label, maxLength: maxLength) {
                let cleaned = cleanSegment(value)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return nil
    }

    private static func fallbackHazardDescription(from text: String) -> String? {
        let candidates = extractSentences(from: text).filter {
            $0.contains("隐患") || $0.contains("风险") || $0.contains("问题")
        }
        return joinTopSentences(candidates, limit: 3, maxLength: 320)
    }

    private static func fallbackRectificationMeasures(from text: String) -> String? {
        let candidates = extractSentences(from: text).filter {
            $0.contains("整改") || $0.contains("限期") || $0.contains("立即") || $0.contains("要求")
        }
        return joinTopSentences(candidates, limit: 3, maxLength: 360)
    }

    private static func matchDate(in text: String, labels: [String]) -> Date? {
        for label in labels {
            if let value = capture(
                pattern: "(?:^|\\n|。|；|;)\\s*[^\\n。；;]{0,24}\(NSRegularExpression.escapedPattern(for: label))[^0-9\\n]{0,12}([0-9]{4}[./-][0-9]{1,2}[./-][0-9]{1,2}|[0-9]{4}年[0-9]{1,2}月[0-9]{1,2}日)",
                in: text
            ), let date = parseDate(value) {
                return date
            }
        }
        return nil
    }

    private static func matchHazardCount(in text: String) -> Int? {
        let patterns = [
            "(?:隐患|问题|整改事项|整改问题)\\s*(?:共|合计)?\\s*([0-9一二三四五六七八九十]{1,3})\\s*(?:条|项|处)",
            "(?:共|合计)\\s*([0-9一二三四五六七八九十]{1,3})\\s*(?:条|项|处)\\s*(?:隐患|问题|整改事项|整改问题)"
        ]
        for pattern in patterns {
            if let raw = capture(pattern: pattern, in: text),
               let count = parseChineseOrArabicInt(raw),
               count > 0, count <= 99 {
                return count
            }
        }
        return nil
    }

    private static func parseChineseOrArabicInt(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = Int(s) { return n }
        let map: [Character: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if s == "十" { return 10 }
        if s.hasPrefix("十"), let last = s.last, let ones = map[last] { return 10 + ones }
        if s.hasSuffix("十"), let first = s.first, let tens = map[first] { return tens * 10 }
        if s.contains("十") {
            let parts = s.split(separator: "十", omittingEmptySubsequences: false)
            guard let first = parts.first?.first, let tens = map[first] else { return nil }
            let ones = parts.dropFirst().first?.first.flatMap { map[$0] } ?? 0
            return tens * 10 + ones
        }
        if s.count == 1, let first = s.first { return map[first] }
        return nil
    }

    private static func parseDate(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = ["yyyy-MM-dd", "yyyy/M/d", "yyyy.M.d", "yyyy年M月d日"]
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = .current
        for format in formats {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    private static func cleanSegment(_ raw: String) -> String {
        let stopKeywords = [
            "发文单位", "通知单编号", "项目名称", "整改责任人", "整改期限", "来文日期", "检查日期", "整改依据"
        ]
        var lines: [String] = []
        for rawLine in raw.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if stopKeywords.contains(where: { line.contains($0 + ":") || line.contains($0 + "：") }) { break }
            lines.append(line)
            if lines.count >= 4 { break }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func captureLabeledSegment(in text: String, label: String, maxLength: Int) -> String? {
        let labelVariants = ["\(label):", "\(label)："]
        let lower = text.lowercased()
        var bestStart: String.Index?
        for variant in labelVariants {
            if let range = lower.range(of: variant.lowercased()) {
                let start = range.upperBound
                if bestStart == nil || start < bestStart! {
                    bestStart = start
                }
            }
        }
        guard let start = bestStart else { return nil }

        let stopLabels = [
            "发文单位", "检查单位", "受检单位", "来文编号", "通知单编号", "项目名称", "责任人",
            "整改期限", "来文日期", "检查日期", "整改依据", "限期整改问题", "检查照片"
        ]
        var end = text.endIndex
        for stop in stopLabels {
            if let stopRange = text.range(of: stop, range: start..<text.endIndex),
               stopRange.lowerBound < end {
                end = stopRange.lowerBound
            }
        }
        let hardEnd = text.index(start, offsetBy: min(maxLength, text.distance(from: start, to: end)), limitedBy: text.endIndex) ?? end
        let candidate = String(text[start..<hardEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? nil : candidate
    }

    private static func extractIssueFocusedText(from text: String) -> String {
        let starts = ["限期整改问题", "现场施工部分", "整改问题", "存在问题"]
        let ends = ["其它提示事项", "检查照片", "联系人", "复查闭合意见", "注:"]
        guard let start = starts.compactMap({ text.range(of: $0)?.lowerBound }).min() else { return text }
        var end = text.endIndex
        for marker in ends {
            if let r = text.range(of: marker, range: start..<text.endIndex), r.lowerBound < end {
                end = r.lowerBound
            }
        }
        let section = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return section.isEmpty ? text : section
    }

    private static func extractSentences(from text: String) -> [String] {
        text
            .replacingOccurrences(of: "\n", with: "。")
            .components(separatedBy: CharacterSet(charactersIn: "。！？!?;；"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count >= 8 }
    }

    private static func joinTopSentences(_ sentences: [String], limit: Int, maxLength: Int) -> String? {
        guard !sentences.isEmpty else { return nil }
        var picked: [String] = []
        var total = 0
        for sentence in sentences.prefix(limit) {
            let next = total + sentence.count + (picked.isEmpty ? 0 : 1)
            if next > maxLength { break }
            picked.append(sentence)
            total = next
        }
        let merged = picked.joined(separator: "；").trimmingCharacters(in: .whitespacesAndNewlines)
        return merged.isEmpty ? nil : merged
    }

    private static func parseIssueItems(from text: String) -> [ExternalNoticeIssueItem] {
        let issueSection = extractIssueSection(from: text)
        let lines = issueSection.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return [] }

        var blocks: [String] = []
        var current: [String] = []
        for line in lines {
            let isNew = isIssueLineStart(line)
            if isNew, !current.isEmpty {
                blocks.append(current.joined(separator: " "))
                current = [line]
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            blocks.append(current.joined(separator: " "))
        }
        if blocks.isEmpty {
            blocks = lines.filter { $0.contains("隐患") || $0.contains("问题") || $0.contains("整改") }
        }

        var items: [ExternalNoticeIssueItem] = []
        var index = 1
        for block in blocks {
            let cleaned = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleaned.count >= 10 else { continue }
            let hazard = extractHazardSentence(from: cleaned) ?? cleaned
            let measure = extractMeasureSentence(from: cleaned)
            let location = inferLocation(from: cleaned)
            let item = ExternalNoticeIssueItem(
                title: "问题\(index)",
                location: location,
                hazardDescription: hazard,
                rectificationMeasures: measure
            )
            items.append(item)
            index += 1
            if items.count >= 8 { break }
        }
        return items
    }

    private static func isIssueLineStart(_ line: String) -> Bool {
        if capture(pattern: "^\\s*(?:问题\\s*\\d+|[0-9]{1,2}[#、.．])", in: line) != nil {
            return true
        }
        if capture(pattern: "^\\s*现场施工部分\\s*[:：]?$", in: line) != nil {
            return true
        }
        return line.contains("问题") && (line.contains("：") || line.contains(":"))
    }

    private static func extractHazardSentence(from text: String) -> String? {
        let sentences = extractSentences(from: text)
        let picked = sentences.filter {
            $0.contains("隐患") || $0.contains("风险") || $0.contains("未") || $0.contains("无") || $0.contains("存在")
        }
        return joinTopSentences(picked.isEmpty ? sentences : picked, limit: 2, maxLength: 260)
    }

    private static func extractMeasureSentence(from text: String) -> String? {
        let sentences = extractSentences(from: text)
        let picked = sentences.filter {
            $0.contains("整改") || $0.contains("要求") || $0.contains("立即") || $0.contains("尽快") || $0.contains("请")
        }
        return joinTopSentences(picked, limit: 2, maxLength: 260)
    }

    private static func inferLocation(from text: String) -> String? {
        let candidates = ["旁", "处", "区域", "现场", "部位", "地点", "周边"]
        let head = text.components(separatedBy: CharacterSet(charactersIn: "，,:：。")).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard head.count >= 2 else { return nil }
        if candidates.contains(where: { head.contains($0) }) {
            return String(head.prefix(36))
        }
        return nil
    }

    private static func looksLikeLabelLine(_ line: String) -> Bool {
        let labels = [
            "发文单位", "检查单位", "受检单位", "来文编号", "通知单编号", "项目名称",
            "工程名称", "责任人", "整改期限", "来文日期", "检查日期", "整改依据"
        ]
        if labels.contains(where: { line == $0 || line.hasPrefix($0 + ":") || line.hasPrefix($0 + "：") }) {
            return true
        }
        return false
    }

    private static func extractProjectNameFromInspectedUnit(in text: String) -> String? {
        guard let block = extractBlockAfterLabel(in: text, label: "受检单位", maxLines: 4) else {
            return nil
        }
        let lines = block
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let full = lines.first(where: { $0.contains("项目部") || $0.contains("项目") }) {
            return String(full.prefix(80))
        }
        return lines.first
    }

    private static func extractIssueSection(from text: String) -> String {
        let starts = ["限期整改问题", "现场施工部分", "整改问题", "存在问题"]
        let ends = ["三、其它提示事项", "其它提示事项", "检查照片", "联系人", "复查闭合意见", "注:"]
        guard let start = starts.compactMap({ text.range(of: $0)?.lowerBound }).min() else { return text }
        var end = text.endIndex
        for marker in ends {
            if let r = text.range(of: marker, range: start..<text.endIndex), r.lowerBound < end {
                end = r.lowerBound
            }
        }
        let section = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return section.isEmpty ? text : section
    }

    private static func extractBlockAfterLabel(in text: String, label: String, maxLines: Int) -> String? {
        let lines = text.components(separatedBy: .newlines)
        guard let idx = lines.firstIndex(where: {
            let l = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return l == label || l.hasPrefix(label + ":") || l.hasPrefix(label + "：")
        }) else {
            return nil
        }
        var collected: [String] = []
        var cursor = idx + 1
        while cursor < lines.count && collected.count < maxLines {
            let line = lines[cursor].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                if !collected.isEmpty { break }
                cursor += 1
                continue
            }
            if looksLikeLabelLine(line) { break }
            collected.append(line)
            cursor += 1
        }
        let merged = collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return merged.isEmpty ? nil : merged
    }

    private static func capture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[valueRange])
    }
}
