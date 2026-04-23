//
//  LawEvidenceRetriever.swift
//  安全大师
//
//  laws_playbook.jsonl — 《建筑安全操作准则》展开条目（整改措施优先）
//  laws_basis.jsonl — 安全生产法、JGJ59、国标/JGJ 等（整改依据）

import Foundation

struct LawRetrievalRecord: Codable, Sendable, Hashable {
    var id: String
    var lawId: String?
    var lawName: String?
    var chapter: String?
    var articleNo: String?
    var articleTitle: String?
    var title: String?
    var text: String?
    var searchText: String?
    var keywords: [String]?
    var sceneTags: [String]?
    var priority: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case lawId = "law_id"
        case lawName = "law_name"
        case chapter
        case articleNo = "article_no"
        case articleTitle = "article_title"
        case title
        case text
        case searchText = "search_text"
        case keywords
        case sceneTags = "scene_tags"
        case priority
    }
}

actor LawEvidenceRetriever {
    static let shared = LawEvidenceRetriever()

    private var playbookRecords: [LawRetrievalRecord]?
    private var basisRecords: [LawRetrievalRecord]?

    func retrievePlaybook(query: String, topK: Int) async -> [LawRetrievalRecord] {
        let all = await loadPlaybook()
        return Self.rankAndTopK(all, query: query, userEmphasis: "", topK: topK)
    }

    /// `userEmphasis` 一般为用户补充说明原文，用于对「箱门/上锁/线缆」等与条文表述不完全一致时的**加权**，避免整段证据被 JGJ 59「30m/3m」类条文占满。
    func retrieveBasis(query: String, userEmphasis: String = "", topK: Int) async -> [LawRetrievalRecord] {
        let all = await loadBasis()
        let k = userEmphasis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? topK : max(topK, 16)
        return Self.rankAndTopK(all, query: query, userEmphasis: userEmphasis, topK: k)
    }

    private func loadPlaybook() async -> [LawRetrievalRecord] {
        if let playbookRecords { return playbookRecords }
        let url = Bundle.main.url(forResource: "laws_playbook", withExtension: "jsonl")
        let parsed: [LawRetrievalRecord] = await loadFromBundle(url: url)
        playbookRecords = parsed
        return parsed
    }

    private func loadBasis() async -> [LawRetrievalRecord] {
        if let basisRecords { return basisRecords }
        let url = Bundle.main.url(forResource: "laws_basis", withExtension: "jsonl")
        let parsed: [LawRetrievalRecord] = await loadFromBundle(url: url)
        basisRecords = parsed
        return parsed
    }

    private func loadFromBundle(url: URL?) async -> [LawRetrievalRecord] {
        guard let url else { return [] }
        return await Task.detached(priority: .userInitiated) {
            Self.parseJsonlFile(url: url)
        }.value
    }

    private static func rankAndTopK(
        _ all: [LawRetrievalRecord],
        query: String,
        userEmphasis: String,
        topK: Int
    ) -> [LawRetrievalRecord] {
        let k = max(1, min(topK, 28))
        guard !all.isEmpty else { return [] }

        let terms = tokenizeQuery(query)
        guard !terms.isEmpty else { return Array(all.prefix(k)) }

        let emphTerms = emphasisBonusTerms(for: userEmphasis)

        var scored: [(Double, LawRetrievalRecord)] = []
        scored.reserveCapacity(all.count)

        for rec in all {
            var s = scoreRecord(rec, terms: terms).0
            if !emphTerms.isEmpty {
                s += userEmphasisMatchBonus(rec, emphTerms: emphTerms)
            }
            if s > 0 {
                scored.append((s, rec))
            }
        }

        if scored.isEmpty {
            // 查询里已有中文词但仍零命中时（极少见），用 priority 弱兜底，避免 evidence 完全空白。
            let hasSubstantiveCJK = terms.contains { t in
                t.count >= 2 && t.unicodeScalars.contains { (0x4E00 ... 0x9FFF).contains($0.value) }
            }
            if hasSubstantiveCJK {
                return Self.priorityFallbackPrefix(all, topK: k)
            }
            return []
        }

        scored.sort { $0.0 > $1.0 }
        var out: [LawRetrievalRecord] = []
        out.reserveCapacity(k)
        var seenIDs = Set<String>()
        for (_, rec) in scored where seenIDs.insert(rec.id).inserted {
            out.append(rec)
            if out.count >= k { break }
        }
        return out
    }

    /// 无关键词命中时的弱兜底：优先高 priority（如安全生产法），避免 evidence 完全为空。
    private static func priorityFallbackPrefix(_ all: [LawRetrievalRecord], topK: Int) -> [LawRetrievalRecord] {
        let sorted = all.sorted { ($0.priority ?? 2) > ($1.priority ?? 2) }
        return Array(sorted.prefix(topK))
    }

    nonisolated private static func parseJsonlFile(url: URL) -> [LawRetrievalRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        var rows: [LawRetrievalRecord] = []
        rows.reserveCapacity(2000)
        let nl = UInt8(ascii: "\n")
        var lineStart = data.startIndex
        var i = data.startIndex
        while i < data.endIndex {
            if data[i] == nl {
                let line = data[lineStart ..< i]
                if !line.isEmpty, let rec = decodeLine(line) {
                    rows.append(rec)
                }
                lineStart = data.index(after: i)
            }
            i = data.index(after: i)
        }
        if lineStart < data.endIndex, !data[lineStart ..< data.endIndex].isEmpty,
           let rec = decodeLine(data[lineStart ..< data.endIndex])
        {
            rows.append(rec)
        }
        return rows
    }

    nonisolated private static func decodeLine(_ sub: Data.SubSequence) -> LawRetrievalRecord? {
        try? JSONDecoder().decode(LawRetrievalRecord.self, from: Data(sub))
    }

    // MARK: - Scoring

    private static func normalize(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\u{3000}", with: " ")
        t = t.replacingOccurrences(of: "\u{00a0}", with: " ")
        let parts = t.split { $0.isWhitespace }
        t = parts.joined(separator: " ")
        return t.lowercased()
    }

    /// 中文检索词：旧版用「连续 1～8 个汉字」贪婪切分，会得到「基坑底部存在少量积」等大块，
    /// 在法规 `search_text` 里几乎从不出现，导致得分恒为 0。改为：汉字串上的 2 字/3 字滑动窗口
    /// （+ 较短整段）+ 英文数字 token，与条文中的「基坑」「降排水」「材料管理」等更容易对齐。
    private static let cjkStopUnigrams: Set<Character> = [
        "的", "了", "在", "是", "和", "与", "及", "或", "等", "应", "将", "对", "为", "以", "中", "有", "不", "可", "需", "须", "宜", "并", "其", "该", "此", "均", "所", "由", "被", "于", "而", "之", "也", "又", "若", "则", "但", "如", "即",
    ]

    private static func tokenizeQuery(_ q: String) -> [String] {
        let n = normalize(q)
        guard !n.isEmpty else { return [] }

        var seen = Set<String>()
        var out: [String] = []
        let maxTerms = 160

        func add(_ s: String) {
            guard out.count < maxTerms else { return }
            if s.isEmpty { return }
            if s.count == 1, let ch = s.first {
                guard ch.unicodeScalars.allSatisfy({ (0x4E00 ... 0x9FFF).contains($0.value) }) else { return }
                if cjkStopUnigrams.contains(ch) { return }
            }
            if seen.insert(s).inserted {
                out.append(s)
            }
        }

        let fullRange = NSRange(n.startIndex ..< n.endIndex, in: n)

        if let asciiRe = try? NSRegularExpression(pattern: "[a-z0-9][a-z0-9\\-\\.]*", options: []) {
            asciiRe.enumerateMatches(in: n, options: [], range: fullRange) { match, _, _ in
                guard let match, let r = Range(match.range, in: n) else { return }
                add(String(n[r]))
            }
        }

        guard let cjkRunRe = try? NSRegularExpression(pattern: "[\\u4e00-\\u9fff]+", options: []) else {
            return out
        }

        cjkRunRe.enumerateMatches(in: n, options: [], range: fullRange) { match, _, _ in
            guard let match, let r = Range(match.range, in: n) else { return }
            let run = String(n[r])
            let chars = Array(run)
            let L = chars.count
            if L == 0 { return }

            if L <= 10 {
                add(run)
            }
            if L >= 2 {
                for i in 0 ..< (L - 1) {
                    add(String(chars[i]) + String(chars[i + 1]))
                }
            }
            if L >= 3 {
                for i in 0 ..< (L - 2) {
                    add(String(chars[i]) + String(chars[i + 1]) + String(chars[i + 2]))
                }
            }
        }

        return out
    }

    private static func termCount(_ text: String, _ term: String) -> Int {
        guard !term.isEmpty else { return 0 }
        var count = 0
        var searchRange = text.startIndex ..< text.endIndex
        while let r = text.range(of: term, range: searchRange) {
            count += 1
            searchRange = r.upperBound ..< text.endIndex
        }
        return count
    }

    private static func scoreRecord(_ rec: LawRetrievalRecord, terms: [String]) -> (Double, [String: Double]) {
        let searchText = normalize(rec.searchText ?? "")
        if searchText.isEmpty { return (0, [:]) }

        let kw = (rec.keywords ?? []).map { normalize($0) }
        let tags = (rec.sceneTags ?? []).map { normalize($0) }
        let title = normalize(rec.title ?? "")

        var score = 0.0
        var detail: [String: Double] = [
            "hit": 0, "title": 0, "kw": 0, "tag": 0, "priority": 0,
        ]

        for t in terms {
            let c = termCount(searchText, t)
            if c > 0 {
                let part = 1.8 * (1.0 + log(1.0 + Double(c)))
                score += part
                detail["hit", default: 0] += part
            }

            if title.contains(t) {
                score += 1.2
                detail["title", default: 0] += 1.2
            }

            if kw.contains(where: { t.contains($0) || $0.contains(t) }) {
                score += 1.0
                detail["kw", default: 0] += 1.0
            }

            if tags.contains(where: { t.contains($0) || $0.contains(t) }) {
                score += 1.0
                detail["tag", default: 0] += 1.0
            }
        }

        let pr = rec.priority ?? 2
        let prBoost: Double
        switch pr {
        case 1: prBoost = 0.0
        case 3: prBoost = 1.0
        default: prBoost = 0.6
        }
        score += prBoost
        detail["priority"] = prBoost

        return (score, detail)
    }

    /// 从用户原话派生额外匹配词（如「锁闭」与条文「关门上锁」对齐）。
    private static func emphasisBonusTerms(for raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var seen = Set<String>()
        var out: [String] = []
        func push(_ s: String) {
            let n = normalize(s)
            guard n.count >= 2 else { return }
            if seen.insert(n).inserted {
                out.append(n)
            }
        }

        for t in tokenizeQuery(trimmed) {
            push(t)
        }

        let low = normalize(trimmed)
        if low.contains("锁") || low.contains("箱门") || low.contains("未锁") || low.contains("闭合") || low.contains("敞开") {
            push("上锁")
            push("关门")
            push("配锁")
        }
        if low.contains("缆") || low.contains("杂乱") || low.contains("拖地") || low.contains("绞绕") {
            push("明设")
            push("地面")
            push("敷设")
            push("机械损伤")
        }

        return out
    }

    private static func userEmphasisMatchBonus(_ rec: LawRetrievalRecord, emphTerms: [String]) -> Double {
        let blob = normalize((rec.searchText ?? "") + " " + (rec.text ?? ""))
        var bonus = 0.0
        for t in emphTerms where t.count >= 2 {
            if blob.contains(t) {
                bonus += 4.0
            }
        }
        return min(bonus, 30.0)
    }

    // MARK: - Prompt blocks

    static func formatPlaybookBlock(_ rows: [LawRetrievalRecord]) -> String {
        if rows.isEmpty {
            return """
            【安全操作准则匹配】（最高优先级 · 整改措施）
            （本段无命中：请结合现场与通用施工安全要求提出整改措施。）
            """
        }

        var lines: [String] = [
            "【安全操作准则匹配】（最高优先级 · 整改措施）",
            "编写 hazard_description 与 rectification_measures 时，必须优先下列条目中的「操作要求」「检查要点」与逻辑说明，可改写为分条措施但不要改变安全含义。",
            "",
        ]
        for (idx, r) in rows.enumerated() {
            let tag = "[P\(idx + 1)]"
            let raw = (r.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("\(tag) \(r.chapter ?? "") · \(r.articleTitle ?? "")")
            if let no = r.articleNo?.trimmingCharacters(in: .whitespacesAndNewlines), !no.isEmpty {
                lines.append("要点：\(no)")
            }
            lines.append("内容：「\(raw)」")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func formatBasisBlock(_ rows: [LawRetrievalRecord]) -> String {
        if rows.isEmpty {
            return """
            【法规条文依据】（整改依据）
            （无匹配条目：legal_basis 中请说明内置法规库未命中，仅可建议对照的规范主题方向，禁止编造条号与原文。）
            """
        }

        var lines: [String] = [
            "【法规条文依据】（整改依据）",
            "legal_basis 必须仅引用本段中的规范原文；使用证据编号 [E1]、[E2]… 与下列条文对应。不得把「建筑安全操作准则」当作国家法律或强制性标准条文引用。",
            "若用户或画面涉及箱门未锁、电缆拖地等，应优先引用本段中**语义可对应**的条文（如「关门上锁」对应箱门未闭、「严禁沿地面明设」对应电缆拖地），并在 legal_basis 中简要说明对应关系；勿因条文未逐字出现「配电箱」「锁闭」而拒引。避免仅用三级配电间距、漏保额定值等与本次可见现象无关的条目凑数。",
            "",
        ]
        for (idx, r) in rows.enumerated() {
            let tag = "[E\(idx + 1)]"
            let name = r.lawName ?? "（未知规范）"
            let no = r.articleNo.map { "条文编号：\($0)" } ?? ""
            let raw = (r.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("\(tag) 《\(name)》\(no)")
            if let chap = r.chapter?.trimmingCharacters(in: .whitespacesAndNewlines), !chap.isEmpty {
                lines.append("章节：\(chap)")
            }
            lines.append("原文：「\(raw)」")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
