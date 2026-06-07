//
//  HazardSpeechIntentParser.swift
//  安全大师
//

import Foundation

/// 本地规则解析语音转写文本，不依赖网络。
struct HazardSpeechIntent: Equatable {
    var locationHint: String?
    /// 去掉已识别地点/时间/整改口令后的描述；若无法清理则保留原文。
    var supplementaryText: String
    var rectificationIntent: HazardRectificationIntent
    var plannedDueAt: Date?
    var riskLevelHint: String?
    var hazardTags: [String]
}

enum HazardSpeechIntentParser {
    private static let locationKeywords: [String] = [
        "二层东侧", "三层西侧", "一层", "地下一层", "地下室", "屋面", "基坑", "临边", "洞口", "楼梯间",
        "施工电梯", "塔吊", "配电房", "钢筋加工区", "木工棚", "生活区", "办公区", "料场", "通道",
        "隧道", "涵洞", "围堰", "码头", "栈桥", "脚手架", "外架", "内架", "作业面", "泵房",
        "锅炉房", "危险品库", "搅拌站", "预制场", "钢筋笼", "承台", "地下室顶板", "负一层", "负二层"
    ]

    private static let hazardTagLexicon: [String] = [
        "高处坠落", "物体打击", "机械伤害", "触电", "坍塌", "火灾", "灼烫", "淹溺", "中毒窒息",
        "临边防护", "洞口防护", "安全网", "安全带", "安全帽", "脚手架", "模板支撑", "起重吊装",
        "施工用电", "消防安全", "危化品", "有限空间", "动火作业", "基坑支护", "高处作业",
        "违章作业", "警示标识", "文明施工", "扬尘", "噪声", "临建宿舍"
    ]

    private static let immediatePhrases = [
        "立即整改", "马上整改", "当即整改", "即刻整改", "现场整改", "马上处理", "立即处理", "立即消除"
    ]

    private static let scheduledPhrases = [
        "限期整改", "限期内整改", "计划整改", "限期完成", "限期内完成", "限期消除", "限期处理"
    ]

    private static let riskLevelPhrases: [(phrase: String, label: String)] = [
        ("重大隐患", "重大风险"),
        ("较大隐患", "较大风险"),
        ("一般隐患", "一般风险"),
        ("重大风险", "重大风险"),
        ("较大风险", "较大风险"),
        ("一般风险", "一般风险"),
        ("低风险", "低风险")
    ]

    static func parse(_ raw: String, referenceDate: Date = Date()) -> HazardSpeechIntent {
        let normalized = normalize(raw)
        let tags = matchTags(in: normalized)
        let risk = matchRiskLevel(in: normalized)
        let rectIntent = matchRectificationIntent(in: normalized)
        let due = matchPlannedDue(in: normalized, referenceDate: referenceDate)
        let location = matchLocation(in: normalized)
        let cleaned = cleanSupplementary(
            normalized,
            location: location,
            rectIntent: rectIntent,
            duePhraseMatched: due != nil
        )

        return HazardSpeechIntent(
            locationHint: location,
            supplementaryText: cleaned.isEmpty ? normalized : cleaned,
            rectificationIntent: rectIntent,
            plannedDueAt: due,
            riskLevelHint: risk,
            hazardTags: tags
        )
    }

    // MARK: - Normalization

    private static func normalize(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "\n", with: " ")
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        return s
    }

    // MARK: - Tags & risk

    private static func matchTags(in text: String) -> [String] {
        hazardTagLexicon.filter { text.contains($0) }
    }

    private static func matchRiskLevel(in text: String) -> String? {
        for item in riskLevelPhrases where text.contains(item.phrase) {
            return HazardRiskLevel.normalizedForStorage(item.label)
        }
        return nil
    }

    // MARK: - Rectification

    private static func matchRectificationIntent(in text: String) -> HazardRectificationIntent {
        let hasScheduled = scheduledPhrases.contains { text.contains($0) }
        let hasImmediate = immediatePhrases.contains { text.contains($0) }
        if hasScheduled, !hasImmediate { return .scheduled }
        if hasImmediate, !hasScheduled { return .immediate }
        if hasScheduled { return .scheduled }
        return .immediate
    }

    // MARK: - Relative time (zh_CN)

    private static func matchPlannedDue(in text: String, referenceDate: Date) -> Date? {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: referenceDate)

        if text.contains("今天") || text.contains("当日") || text.contains("当天") {
            return startOfToday
        }
        if text.contains("明天") {
            return cal.date(byAdding: .day, value: 1, to: startOfToday)
        }
        if text.contains("后天") {
            return cal.date(byAdding: .day, value: 2, to: startOfToday)
        }
        if text.contains("大后天") {
            return cal.date(byAdding: .day, value: 3, to: startOfToday)
        }

        if let days = firstCapturedInt(in: text, patterns: [
            #"(\d+)\s*个?\s*工作日"#,
            #"(\d+)\s*个?\s*工作日内"#,
            #"(\d+)\s*个?\s*自然日"#,
            #"(\d+)\s*个?\s*天内"#,
            #"(\d+)\s*日之内"#,
            #"(\d+)\s*日之内完成"#
        ]) {
            return cal.date(byAdding: .day, value: days, to: startOfToday)
        }

        if text.contains("24小时") || text.contains("二十四小时") {
            return cal.date(byAdding: .hour, value: 24, to: referenceDate).map { cal.startOfDay(for: $0) }
                ?? cal.date(byAdding: .day, value: 1, to: startOfToday)
        }
        if text.contains("48小时") || text.contains("四十八小时") {
            return cal.date(byAdding: .day, value: 2, to: startOfToday)
        }
        if text.contains("72小时") || text.contains("七十二小时") {
            return cal.date(byAdding: .day, value: 3, to: startOfToday)
        }

        if text.contains("本周") || text.contains("本周末") {
            return endOfWeek(containing: referenceDate, calendar: cal)
        }
        if text.contains("下周") {
            let nextWeek = cal.date(byAdding: .weekOfYear, value: 1, to: referenceDate) ?? referenceDate
            return endOfWeek(containing: nextWeek, calendar: cal)
        }
        if text.contains("一周内") || text.contains("一个星期内") {
            return cal.date(byAdding: .day, value: 7, to: startOfToday)
        }
        if text.contains("半个月") {
            return cal.date(byAdding: .day, value: 15, to: startOfToday)
        }
        if text.contains("一个月") || text.contains("一月内") {
            return cal.date(byAdding: .month, value: 1, to: startOfToday)
        }

        if let absolute = matchChineseMonthDay(in: text, referenceDate: referenceDate) {
            return absolute
        }

        return nil
    }

    private static func endOfWeek(containing date: Date, calendar: Calendar) -> Date? {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return nil }
        return calendar.date(byAdding: .day, value: -1, to: interval.end)
            .map { calendar.startOfDay(for: $0) }
    }

    private static func firstCapturedInt(in text: String, patterns: [String]) -> Int? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: text),
                  let n = Int(text[r])
            else { continue }
            return n
        }
        return nil
    }

    private static func matchChineseMonthDay(in text: String, referenceDate: Date) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,2})\s*月\s*(\d{1,2})\s*日"#),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges >= 3,
              let monthRange = Range(m.range(at: 1), in: text),
              let dayRange = Range(m.range(at: 2), in: text),
              let month = Int(text[monthRange]),
              let day = Int(text[dayRange])
        else { return nil }

        var comps = Calendar.current.dateComponents([.year], from: referenceDate)
        comps.month = month
        comps.day = day
        guard var date = Calendar.current.date(from: comps) else { return nil }
        if date < Calendar.current.startOfDay(for: referenceDate) {
            comps.year = (comps.year ?? 0) + 1
            date = Calendar.current.date(from: comps) ?? date
        }
        return Calendar.current.startOfDay(for: date)
    }

    // MARK: - Location

    /// 含以下子串的片段视为隐患/整改语义，不能作为地点。
    private static let locationRejectSubstrings: [String] = [
        "隐患", "风险", "整改", "较大", "一般", "重大", "低风险",
        "限期", "立即", "马上", "应当", "建议", "发现", "存在", "消除"
    ]

    /// 「在 X 作业/施工…」中 X 在动词前的截止模式。
    private static let locationCaptureStopSuffix =
        "(?:作业|施工|进行|导致|造成|存在|发现|没有|未按|违法|违章|挖掘|吊装)"

    private static func matchLocation(in text: String) -> String? {
        for kw in locationKeywords where text.contains(kw) {
            if let span = extractSpan(around: kw, in: text), isConfidentLocationHint(span) {
                return span
            }
            if isConfidentLocationHint(kw) {
                return kw
            }
        }

        if let preposition = matchLocationAfterPreposition(in: text) {
            return preposition
        }

        let structuralPatterns = [
            #"((?:\d+|[一二三四五六七八九十]+)\s*(?:层|楼|栋|段))"#,
            #"((?:东|西|南|北|中)(?:侧|区|部|头|端|角)?(?:\s*(?:\d+|[一二三四五六七八九十]+)?\s*(?:层|楼))?)"#
        ]
        for pattern in structuralPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: text)
            else { continue }
            let candidate = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            if isConfidentLocationHint(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// 「在/于/位于」后截取短片段，仅当命中词表或明确结构（层/侧等）时返回。
    private static func matchLocationAfterPreposition(in text: String) -> String? {
        let pattern = "(?:在|于|位于)\\s*([^，,。；;：:\\s]{1,12}?)(?="
            + locationCaptureStopSuffix + "|[，,。；;：:]|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text)
        else { return nil }

        let fragment = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard fragment.count >= 2 else { return nil }

        if let lex = bestLexiconMatch(in: fragment), isConfidentLocationHint(lex) {
            return lex
        }
        if isConfidentLocationHint(fragment) {
            return fragment
        }
        return nil
    }

    private static func bestLexiconMatch(in fragment: String) -> String? {
        let hits = locationKeywords.filter { fragment.contains($0) }
        return hits.max(by: { $0.count < $1.count })
    }

    /// 仅词表命中或典型工点结构（层/栋/侧等），且不含隐患/风险类词。
    private static func isConfidentLocationHint(_ hint: String) -> Bool {
        let h = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard h.count >= 2, h.count <= 16 else { return false }
        for bad in locationRejectSubstrings where h.contains(bad) { return false }

        if locationKeywords.contains(where: { h == $0 || h.contains($0) }) {
            return true
        }
        if locationKeywords.contains(where: { $0.contains(h) && h.count >= 2 }) {
            return true
        }

        let structural = #"^(?:[\d一二三四五六七八九十]+\s*(?:层|楼|栋|段)|(?:东|西|南|北|中)(?:侧|区|部|头|端|角)(?:\s*[\d一二三四五六七八九十]*\s*(?:层|楼))?|[\d一二三四五六七八九十]+层(?:东|西|南|北)侧)$"#
        if h.range(of: structural, options: .regularExpression) != nil {
            return true
        }
        if (h.contains("层") || h.contains("栋") || h.contains("楼") || h.hasSuffix("侧") || h.hasSuffix("区")),
           !h.contains("作业"), !h.contains("挖掘") {
            return true
        }
        return false
    }

    private static func extractSpan(around keyword: String, in text: String) -> String? {
        guard let range = text.range(of: keyword) else { return nil }
        let lower = text.distance(from: text.startIndex, to: range.lowerBound)
        let upper = text.distance(from: text.startIndex, to: range.upperBound)
        let start = max(0, lower - 6)
        let end = min(text.count, upper + 4)
        let startIdx = text.index(text.startIndex, offsetBy: start)
        let endIdx = text.index(text.startIndex, offsetBy: end)
        var span = String(text[startIdx..<endIdx])
        span = span.trimmingCharacters(in: CharacterSet(charactersIn: "，,。；;：:在位于 "))
        if span.count >= 2 { return span }
        return keyword
    }

    // MARK: - Clean description

    private static func cleanSupplementary(
        _ text: String,
        location: String?,
        rectIntent: HazardRectificationIntent,
        duePhraseMatched: Bool
    ) -> String {
        var s = text
        if let location {
            s = s.replacingOccurrences(of: location, with: "")
            for prefix in ["在", "于", "位于"] {
                s = s.replacingOccurrences(of: "\(prefix)\(location)", with: "")
            }
        }
        for phrase in immediatePhrases + scheduledPhrases {
            s = s.replacingOccurrences(of: phrase, with: "")
        }
        for item in riskLevelPhrases {
            s = s.replacingOccurrences(of: item.phrase, with: "")
        }
        let timePhrases = [
            "今天", "明天", "后天", "大后天", "24小时内", "二十四小时内", "48小时内", "72小时内",
            "一周内", "一个星期内", "半个月", "一个月", "一月内", "本周", "下周", "本周末"
        ]
        if duePhraseMatched {
            for p in timePhrases {
                s = s.replacingOccurrences(of: p, with: "")
            }
        }
        s = s.replacingOccurrences(of: "  ", with: " ")
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "，,。；;：: \t\n"))
        return s
    }
}

// MARK: - Manual speech intent cases (no unit test target)
//
// parse("挖掘机在河里作业较大隐患")
//   → locationHint: nil, supplementaryText: "挖掘机在河里作业", riskLevelHint: "较大风险"
// parse("二层东侧脚手架缺失一般隐患")
//   → locationHint: "二层东侧" (or span containing it), risk: "一般风险"
// parse("基坑周边无限期整改明天完成")
//   → locationHint: "基坑", rectificationIntent: .scheduled
// parse("在配电房发现电缆裸露较大隐患")
//   → locationHint: "配电房", supplementaryText cleaned of risk phrase
