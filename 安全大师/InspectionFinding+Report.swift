//
//  InspectionFinding+Report.swift
//  安全大师
//

import CoreData
import Foundation

/// 可分享报告类型。
enum ShareableReportKind {
    /// 隐患排查通知书（方案 A）：整改前现场图，无整改后图。
    case inspection
    /// 整改回复单（方案 B）：整改前后对比，整改情况来自验收通过轮。
    case rectification

    var coverTitle: String {
        ReportTemplateSettings.current.title(for: self)
    }

    var fileNamePrefix: String {
        switch self {
        case .inspection: return "安全大师_隐患整改通知单"
        case .rectification: return "安全大师_隐患整改回复报告"
        }
    }

    var serialPrefix: String {
        switch self {
        case .inspection: return "ZGTZ"
        case .rectification: return "ZGHF"
        }
    }
}

extension InspectionFinding {
    var sourceTypeNormalized: String {
        let raw = sourceType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return raw == "external" ? "external" : "internal"
    }

    var isExternalSource: Bool {
        sourceTypeNormalized == "external"
    }

    var sourceDisplayLabel: String {
        isExternalSource ? "外部通知单" : "内部排查"
    }

    var externalNoticeSummary: String? {
        guard isExternalSource else { return nil }
        let no = externalNoticeNo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let issuer = externalIssuer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var parts: [String] = []
        if !issuer.isEmpty { parts.append("发文单位：\(issuer)") }
        if !no.isEmpty { parts.append("来文编号：\(no)") }
        if let date = externalNoticeDate {
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateStyle = .medium
            f.timeStyle = .none
            parts.append("来文日期：\(f.string(from: date))")
        }
        if parts.isEmpty { return nil }
        return parts.joined(separator: "；")
    }

    var reportTrackingID: String? {
        let fid = findingId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fid.isEmpty { return fid }
        let uri = objectID.uriRepresentation().absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        return uri.isEmpty ? nil : uri
    }

    private struct ReanalysisInput {
        let photoData: Data?
        let secondaryPhotoData: Data?
        let supplementaryText: String
        let location: String
    }

    /// 部位（导出用）。
    var reportLocationPart: String {
        let t = location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "（未填）" : t
    }

    /// 用户补充的文字说明（不含 AI 隐患描述）。
    func reportUserSupplementaryDisplay(maxLength: Int? = nil) -> String {
        reportTruncatedField(supplementaryText, maxLength: maxLength, emptyPlaceholder: "（本条未填写）")
    }

    var reportFormalInspectionSituation: String {
        reportTruncatedField(supplementaryText, maxLength: nil, emptyPlaceholder: "现场检查发现如下问题。")
    }

    /// AI 分析得出的隐患描述 / 不符合项。
    func reportAIHazardDescriptionDisplay(maxLength: Int? = nil) -> String {
        reportTruncatedField(hazardDescription, maxLength: maxLength, emptyPlaceholder: "—")
    }

    func reportFormalIssueDescription(maxLength: Int? = nil) -> String {
        let issue = reportTruncatedField(hazardDescription, maxLength: maxLength, emptyPlaceholder: "—")
        guard isDormitoryOrLivingArea, issue != "—" else { return issue }
        if issue.contains("宿舍") || issue.contains("生活区") { return issue }
        return "经检查，生活区/宿舍内存在用电安全隐患：\(issue)"
    }

    private func reportTruncatedField(_ raw: String?, maxLength: Int?, emptyPlaceholder: String) -> String {
        let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body = t.isEmpty ? emptyPlaceholder : t
        guard let maxLength, body != emptyPlaceholder, body.count > maxLength else { return body }
        let end = body.index(body.startIndex, offsetBy: maxLength)
        return String(body[..<end]) + "…"
    }

    func reportLegalBasisTruncated(maxLength: Int = 300) -> String {
        let raw = legalBasis?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty { return "—" }
        guard raw.count > maxLength else { return raw }
        let end = raw.index(raw.startIndex, offsetBy: maxLength)
        return String(raw[..<end]) + "…"
    }

    func reportFormalLegalBasis(maxLength: Int = 300) -> String {
        let raw = reportLegalBasisTruncated(maxLength: maxLength)
        guard isDormitoryOrLivingArea, raw != "—" else { return raw }
        let normalized = raw
            .replacingOccurrences(of: "施工现场", with: "现场生活区")
            .replacingOccurrences(of: "作业现场", with: "现场生活区")
        let supplement = "本条隐患同时按生活区/宿舍用电安全管理要求执行，重点核查线缆绝缘、插排负荷、私拉乱接及可燃物周边用电风险。"
        return normalized.contains("宿舍") || normalized.contains("生活区")
            ? normalized
            : normalized + "\n" + supplement
    }

    /// 正文用「整改依据」：仅保留规范名称 + 条文号，避免正文过长导致跨页。
    func reportLegalBasisReferenceSummary(maxItems: Int = 3) -> String {
        let references = legalBasisReferenceItems()
        guard !references.isEmpty else { return "—" }
        let picked = Array(references.prefix(maxItems))
        let suffix = references.count > maxItems ? "（等 \(references.count) 条）" : ""
        return picked.joined(separator: "；") + suffix
    }

    /// 附录用「整改依据原文」：保留完整文本。
    var reportLegalBasisAppendixText: String? {
        let text = legalBasis?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private func legalBasisReferenceItems() -> [String] {
        let source = legalBasis?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !source.isEmpty else { return [] }
        let lines = source
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var items: [String] = []
        for line in lines {
            if let ref = legalBasisReference(from: line), !items.contains(ref) {
                items.append(ref)
            }
        }
        if items.isEmpty, let fallback = legalBasisReference(from: source) {
            items.append(fallback)
        }
        return items
    }

    private func legalBasisReference(from text: String) -> String? {
        guard let nameRange = text.range(of: "《[^》]+》", options: .regularExpression) else { return nil }
        let name = String(text[nameRange])
        if let codeRange = text.range(of: "条文编号[:：]\\s*([0-9]+(?:\\.[0-9]+)*)", options: .regularExpression) {
            let raw = String(text[codeRange]).replacingOccurrences(of: "条文编号", with: "")
                .replacingOccurrences(of: "：", with: "")
                .replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty {
                return "\(name)第\(raw)条"
            }
        }
        if let articleRange = text.range(of: "第\\s*[0-9]+(?:\\.[0-9]+)*\\s*条", options: .regularExpression) {
            let article = String(text[articleRange]).replacingOccurrences(of: " ", with: "")
            return "\(name)\(article)"
        }
        return name
    }

    var reportRectificationRequirement: String {
        let t = rectificationMeasures?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "—" : t
    }

    var reportFormalRectificationRequirement: String {
        let raw = reportRectificationRequirement
        guard isDormitoryOrLivingArea, raw != "—" else { return raw }
        let normalized = raw
            .replacingOccurrences(of: "施工现场", with: "现场生活区")
            .replacingOccurrences(of: "作业现场", with: "现场生活区")
        let supplement = "同时应对宿舍内插排、电源线、私拉乱接及破损线缆进行排查，严禁继续使用破损或存在过载风险的用电设施。"
        return normalized.contains("宿舍") || normalized.contains("生活区")
            ? normalized
            : normalized + "\n" + supplement
    }

    var reportRiskLevelDisplay: String {
        let t = riskLevel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let normalized = HazardRiskLevel.normalizedForStorage(t) { return normalized }
        return t.isEmpty ? "—" : t
    }

    /// 简表/封面：待整改或已整改。
    var reportRectificationStatusLabel: String {
        isRectificationClosed ? "已整改" : "待整改"
    }

    /// 限期：首轮或最近一轮的计划完成日；立即整改显示「立即整改」。
    var reportDeadlineLine: String {
        let round = rectificationRoundsArray.first ?? latestRectificationRound
        guard let round else { return "—" }
        if round.modeEnum == .immediate { return "立即整改" }
        guard let due = round.plannedDueAt else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: due)
    }

    /// 最近一轮验收通过的整改轮次。
    var latestPassedRectificationRound: RectificationRound? {
        rectificationRoundsArray.last { $0.statusEnum == .passed }
    }

    /// 报告展示轮次：优先验收通过轮；无通过轮时回退最新轮次，避免“已填写但预览为空”。
    var latestReportableRectificationRound: RectificationRound? {
        latestPassedRectificationRound ?? latestRectificationRound
    }

    /// 整改回复单：验收通过轮的实际整改说明。
    var reportRectificationSituation: String {
        let t = latestReportableRectificationRound?.actionTaken?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "—" : t
    }

    /// 整改回复单：验收通过轮责任人；无则「—」。
    var reportResponsibleParty: String {
        let t = latestReportableRectificationRound?.responsibleParty?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? latestRectificationRound?.responsibleParty?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        return t.isEmpty ? "—" : t
    }

    /// 整改后佐证图（验收通过轮）。
    var reportAfterRectificationPhotoData: Data? {
        guard let d = latestReportableRectificationRound?.evidencePhotoData, !d.isEmpty else { return nil }
        return d
    }

    var isReadyForRectificationReplyExport: Bool {
        reportAfterRectificationPhotoData != nil
            && reportResponsibleParty.trimmingCharacters(in: .whitespacesAndNewlines) != "—"
    }

    /// 整改回复报告：验收意见（优先通过轮；无则回退最近轮次）。
    var reportRectificationAcceptanceOpinion: String {
        let t = latestPassedRectificationRound?.verifierNote?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? latestRectificationRound?.verifierNote?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        if !t.isEmpty { return t }
        return isRectificationClosed ? "验收通过" : "待验收"
    }

    /// 整改回复报告：验收时间。
    var reportRectificationAcceptanceTime: String {
        guard let time = latestPassedRectificationRound?.verifiedAt ?? latestRectificationRound?.verifiedAt else {
            return "—"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年MM月dd日 HH:mm"
        return f.string(from: time)
    }

    /// 报告正文「事故类别」字段取值（无「事故类别：」前缀）。
    var reportAccidentCategoryDisplay: String {
        let maj = accidentCategoryMajor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let mino = accidentCategoryMinor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if maj.isEmpty, mino.isEmpty { return "—" }
        if mino.isEmpty { return maj }
        if maj.isEmpty { return mino }
        return "\(maj) / \(mino)"
    }

    /// 详页可选小字：事故类别一行；无则 nil。
    var reportAccidentCategoryFootnote: String? {
        let display = reportAccidentCategoryDisplay
        guard display != "—" else { return nil }
        return "事故类别：\(display)"
    }

    private var isDormitoryOrLivingArea: Bool {
        let text = [location, supplementaryText, hazardDescription]
            .compactMap { $0 }
            .joined(separator: " ")
        return ["宿舍", "生活区", "寝室", "住宿区", "工人宿舍"].contains { text.contains($0) }
    }
}

extension InspectionFinding {
    /// 用于列表归档与「某日详情」筛选：有「发现时间」则按发现日，否则按创建日（与详情里可编辑的发现时间一致）。
    var effectiveArchiveDate: Date? {
        discoveredAt ?? createdAt
    }

    private func trimmedRecordSnapshot(_ raw: String?) -> String? {
        let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    /// 保存记录时快照的项目名称；旧数据可能为空。
    var recordProjectNameSnapshot: String? {
        trimmedRecordSnapshot(reportProjectName)
    }

    /// 保存记录时快照的检查人；旧数据可能为空。
    var recordInspectorNameSnapshot: String? {
        trimmedRecordSnapshot(reportInspectorName)
    }

    /// 保存记录时快照的项目名称（旧数据可能为空）。
    var recordProjectNameDisplay: String {
        recordProjectNameSnapshot ?? "（未填写项目）"
    }

    var recordInspectorNameDisplay: String {
        recordInspectorNameSnapshot ?? "（未填写检查人）"
    }

    /// 与「确定隐患详情」一致的最小确认条件（导出门禁可复用）。
    var hasConfirmedDetailFields: Bool {
        if isExternalSource {
            // 外部导入记录按“已确认归档”处理，不再走隐患详情确认门禁。
            return true
        }
        let issue = (hazardDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let requirement = (rectificationMeasures ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return recordProjectNameSnapshot != nil
            && recordInspectorNameSnapshot != nil
            && !issue.isEmpty
            && !requirement.isEmpty
    }

    /// 最近一轮整改的责任人（用于排序与搜索）。
    var latestResponsiblePartyDisplay: String {
        let t = latestRectificationRound?.responsibleParty?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "（未填写责任人）" : t
    }

    /// 无完整 AI 结论：离线占位、或措施/依据仍为待补模板。
    var needsPendingAnalysis: Bool {
        guard hasMinimumInputForAnalysis() else { return false }
        let hazard = hazardDescription ?? ""
        if hazard.contains(HazardOfflineMarkers.recordPrefix) { return true }
        let measures = rectificationMeasures ?? ""
        if measures.contains("（待联网后") || measures.contains("待联网后使用") { return true }
        let legal = legalBasis ?? ""
        if legal.contains("（离线记录：") || legal.contains("离线记录：未检索") { return true }
        return false
    }

    /// 现场主图、副图（各至多一张，顺序固定）；用于展示、导出与重新分析。
    var sitePhotoDatasOrdered: [Data] {
        var a: [Data] = []
        if let d = photoData, !d.isEmpty { a.append(d) }
        if let d = secondaryPhotoData, !d.isEmpty { a.append(d) }
        return a
    }

    /// 已持久化的 AI 整改回复草稿（不含本地回退）。
    var storedRectificationReplyDraft: String {
        rectificationReplyDraft?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// 是否有可用于生成本地回复草稿的整改措施正文。
    var hasUsableRectificationMeasures: Bool {
        let m = rectificationMeasures?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !m.isEmpty else { return false }
        if m.contains("（待联网后") || m.contains("待联网后使用") { return false }
        return true
    }

    /// 有 AI 草稿或可从措施回退；无措施且未分析过时为 false。
    var hasRectificationReplyDraftSource: Bool {
        !storedRectificationReplyDraft.isEmpty || hasUsableRectificationMeasures
    }

    /// 整改闭环「一键采用」用的正文：优先 Core Data 中的 AI 草稿，否则由整改措施生成本地简述。
    func effectiveRectificationReplyDraft(includeLocalFallback: Bool = true) -> String {
        if !storedRectificationReplyDraft.isEmpty {
            return storedRectificationReplyDraft
        }
        guard includeLocalFallback, hasUsableRectificationMeasures,
              let measures = rectificationMeasures
        else { return "" }
        return Self.synthesizedReplyDraft(fromMeasures: measures)
    }

    /// 有措施但尚无服务端草稿时，提示用户重新分析。
    var needsReplyDraftReanalysis: Bool {
        storedRectificationReplyDraft.isEmpty && hasUsableRectificationMeasures
    }

    /// 将云端/演示分析结果写回本条记录（不修改照片、地点、补充说明与创建时间）。
    func applyReanalysis(_ result: HazardAnalysisResult) {
        hazardDescription = result.hazardDescription
        rectificationMeasures = result.rectificationMeasures
        if let draft = Self.normalizedReplyDraft(result.rectificationReplyDraft) {
            rectificationReplyDraft = draft
        }
        // 风险等级以用户已保存的为准；重新分析不覆盖。
        // 实际整改说明（actionTaken）仅在用户「一键采用」时写入，此处不覆盖。
        accidentCategoryMajor = result.accidentCategoryMajor
        accidentCategoryMinor = result.accidentCategoryMinor
        legalBasis = result.legalBasis
    }

    static func normalizedReplyDraft(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// 无 `rectification_reply_draft` 时，由整改措施条目生成完成时陈述（本地回退，非模型输出）。
    static func synthesizedReplyDraft(fromMeasures measures: String) -> String {
        let lines = measures
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix("（") }

        let bullets: [String] = lines.prefix(4).compactMap { line -> String? in
            var s = line
            if let range = s.range(of: #"^[\d①②③④⑤⑥⑦⑧⑨⑩]+[\.\)、]\s*"#, options: .regularExpression) {
                s.removeSubrange(range)
            }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { return nil }
            if s.hasPrefix("已") { return s }
            for prefix in ["立即", "严禁", "禁止", "不得", "须", "应", "需"] {
                if s.hasPrefix(prefix) {
                    return "已按要求" + String(s.dropFirst(prefix.count))
                }
            }
            return "已落实：\(s)"
        }

        if !bullets.isEmpty {
            return bullets.joined(separator: "\n")
        }
        let short = String(measures.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
        return "已按排查整改要求完成现场整改与复查。要点：\(short)"
    }

    /// 基于用户已填写的整改说明 + 当前隐患上下文，生成更规范的整改记录表述。
    static func polishedActionTaken(
        from userInput: String,
        fallbackDraft: String,
        location: String?,
        riskLevel: String?,
        rectificationRequirement: String?,
        includeContextPrefix: Bool = true,
        requirementMaxItems: Int = 2
    ) -> String {
        let text = userInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n\n", with: "\n")
        guard !text.isEmpty else { return fallbackDraft }

        var lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.count == 1, let first = lines.first, !first.hasPrefix("已") {
            lines[0] = "已完成：\(first)"
        }
        var body = lines.map { line -> String in
            if line.hasPrefix("已") { return line }
            return "已\(line)"
        }.joined(separator: "；")
        body = applyDraftReferenceStyle(
            currentBody: body,
            userInput: text,
            fallbackDraft: fallbackDraft
        )

        let requirementSummary = cleanedRequirementSummary(
            from: rectificationRequirement,
            maxItems: max(1, requirementMaxItems)
        )
        if !requirementSummary.isEmpty,
           !body.contains("按整改要求"),
           !bodyHasRequirementOverlap(body, requirementSummary: requirementSummary) {
            body += "；并按整改要求落实：\(requirementSummary)"
        }

        guard includeContextPrefix else {
            return body.hasSuffix("。") ? body : body + "。"
        }

        let loc = location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let risk = HazardRiskLevel.normalizedForStorage(riskLevel) ?? ""
        var prefixParts: [String] = []
        if !loc.isEmpty { prefixParts.append("部位：\(loc)") }
        if !risk.isEmpty { prefixParts.append("风险等级：\(risk)") }
        let prefix = prefixParts.isEmpty ? "" : prefixParts.joined(separator: "，") + "。"

        let suffix = body.hasSuffix("。") ? "" : "。"
        return prefix + body + suffix
    }

    private static func cleanedRequirementSummary(from requirement: String?, maxItems: Int = 2) -> String {
        let raw = requirement?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return "" }
        if raw.contains("待联网后") || raw.contains("（待联网后") { return "" }

        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("（") }
            .compactMap { line -> String? in
                var s = line
                if let range = s.range(of: #"^[\d①②③④⑤⑥⑦⑧⑨⑩]+[\.\)、]\s*"#, options: .regularExpression) {
                    s.removeSubrange(range)
                }
                s = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return s.isEmpty ? nil : s
            }

        if lines.isEmpty { return "" }
        return lines.prefix(max(1, maxItems)).joined(separator: "；")
    }

    private static func bodyHasRequirementOverlap(_ body: String, requirementSummary: String) -> Bool {
        let separators = CharacterSet(charactersIn: "；，。、\n ")
        let bodyTokens = body.components(separatedBy: separators).filter { $0.count >= 3 }
        let reqTokens = requirementSummary.components(separatedBy: separators).filter { $0.count >= 3 }
        guard !bodyTokens.isEmpty, !reqTokens.isEmpty else { return false }
        return reqTokens.contains { token in bodyTokens.contains { $0.contains(token) || token.contains($0) } }
    }

    /// 参考 AI 草稿语气，但仅在与用户输入主题相关时补充，避免“像换了一段内容”。
    private static func applyDraftReferenceStyle(
        currentBody: String,
        userInput: String,
        fallbackDraft: String
    ) -> String {
        let draft = fallbackDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return currentBody }

        let separators = CharacterSet(charactersIn: "；，。、\n ")
        let userKeywords = userInput
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
        guard !userKeywords.isEmpty else { return currentBody }

        let draftClauses = draft
            .components(separatedBy: CharacterSet(charactersIn: "；。\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count >= 6 }

        let matched = draftClauses.first { clause in
            userKeywords.contains { keyword in clause.contains(keyword) || keyword.contains(clause) }
        }
        guard let matched else { return currentBody }

        if currentBody.contains(matched) || matched.contains(currentBody) {
            return currentBody
        }
        return currentBody + "；" + matched
    }

    /// 是否与「开始排查」相同的最低输入（至少照片或文字其一）。
    func hasMinimumInputForAnalysis() -> Bool {
        let hasPhoto = !sitePhotoDatasOrdered.isEmpty
        let text = (supplementaryText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return hasPhoto || !text.isEmpty
    }

    /// 记录详情 / 列表批量「重新分析」共用。
    /// 内部通过 `context.perform` 串行化读写，支持主线程与后台 context 复用。
    func performReanalysis(
        context: NSManagedObjectContext,
        overwriteFormalFields: Bool? = nil
    ) async throws {
        let shouldOverwriteFormalFields = overwriteFormalFields ?? needsPendingAnalysis
        let input: ReanalysisInput = try await context.performThrowing {
            guard !self.isDeleted else {
                throw NSError(domain: "InspectionFinding", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "无法分析：该条记录可能已被删除。"
                ])
            }
            guard self.hasMinimumInputForAnalysis() else {
                throw HazardAnalysisError.missingInput
            }
            let photos = self.sitePhotoDatasOrdered
            return Self.ReanalysisInput(
                photoData: photos.first,
                secondaryPhotoData: photos.count > 1 ? photos[1] : nil,
                supplementaryText: self.supplementaryText ?? "",
                location: self.location ?? ""
            )
        }

        let service = HazardAnalysisServiceFactory.makeDefault()
        let result = try await service.analyze(
            photoData: input.photoData,
            secondaryPhotoData: input.secondaryPhotoData,
            supplementaryText: input.supplementaryText,
            location: input.location
        )

        try await context.performThrowing {
            guard !self.isDeleted else {
                throw NSError(domain: "InspectionFinding", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "无法写回：该条记录可能已被删除。"
                ])
            }
            if shouldOverwriteFormalFields {
                self.applyReanalysis(result)
            } else if let draft = Self.normalizedReplyDraft(result.rectificationReplyDraft) {
                self.rectificationReplyDraft = draft
            }
            try context.save()
        }
    }

    /// - Returns: 是否已成功持久化；失败时已 `rollback`，不会留下半成品对象。
    @discardableResult
    static func savePayload(
        _ payload: HazardResultPayload,
        context: NSManagedObjectContext
    ) -> Bool {
        let f = InspectionFinding(context: context)
        f.findingId = UUID().uuidString
        let now = Date()
        f.createdAt = now
        f.discoveredAt = now
        let loc = payload.location.trimmingCharacters(in: .whitespacesAndNewlines)
        f.location = loc.isEmpty ? nil : loc
        f.photoData = payload.photoData
        f.secondaryPhotoData = payload.secondaryPhotoData
        let sup = payload.supplementaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagLine = payload.hazardTypeTags.isEmpty ? "" : "隐患类型：\(payload.hazardTypeTags.joined(separator: "、"))"
        let taggedSupplementary = [tagLine, sup].filter { !$0.isEmpty }.joined(separator: "\n")
        f.supplementaryText = taggedSupplementary.isEmpty ? nil : taggedSupplementary
        f.hazardDescription = payload.analysis.hazardDescription
        f.rectificationMeasures = payload.analysis.rectificationMeasures
        f.riskLevel = HazardRiskLevel.effectiveLevel(
            userOverride: payload.userRiskLevelOverride,
            aiLevel: payload.analysis.riskLevel
        )
        f.accidentCategoryMajor = payload.analysis.accidentCategoryMajor
        f.accidentCategoryMinor = payload.analysis.accidentCategoryMinor
        f.legalBasis = payload.analysis.legalBasis
        f.rectificationReplyDraft = Self.normalizedReplyDraft(payload.analysis.rectificationReplyDraft)
        f.sourceType = "internal"

        let project = payload.reportProjectName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        f.reportProjectName = project.isEmpty ? nil : project
        let inspector = payload.reportInspectorName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        f.reportInspectorName = inspector.isEmpty ? nil : inspector

        ReportProjectSettingsStore.persistIfNonEmpty(
            projectName: project,
            inspectorName: inspector
        )
        RecentFieldValuesStore.recordReportCover(
            projectName: project,
            inspectorName: inspector
        )
        RecentFieldValuesStore.record(loc, for: .location)
        RecentFieldValuesStore.recordQuickInspectionFields(
            projectName: project,
            inspectorName: inspector,
            location: loc,
            responsiblePerson: payload.rectificationResponsiblePerson ?? "",
            responsibleUnit: payload.rectificationResponsibleUnit ?? ""
        )

        switch payload.rectificationIntent {
        case .immediate:
            if let r = f.startFirstRectificationRound(mode: .immediate, plannedDueAt: nil, context: context) {
                InspectionFinding.applyRectificationPrefill(to: r, from: payload)
                InspectionFinding.submitImmediateRectificationIfReady(r)
            }
        case .scheduled:
            if let r = f.startFirstRectificationRound(mode: .scheduled, plannedDueAt: payload.rectificationPlannedDueAt, context: context) {
                InspectionFinding.applyRectificationResponsibility(to: r, from: payload)
            }
        }

        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            return false
        }
    }

    /// 将识别页「立即整改」弹窗中的说明与照片写入首轮整改。
    fileprivate static func applyRectificationPrefill(to round: RectificationRound, from payload: HazardResultPayload) {
        let raw = payload.prefillRectificationActionNote.trimmingCharacters(in: .whitespacesAndNewlines)
        round.actionTaken = raw.isEmpty ? nil : raw
        applyRectificationResponsibility(to: round, from: payload)
        if let d = payload.prefillRectificationPhotoData, !d.isEmpty {
            round.evidencePhotoData = d
        }
    }

    fileprivate static func applyRectificationResponsibility(to round: RectificationRound, from payload: HazardResultPayload) {
        let person = payload.rectificationResponsiblePerson?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let unit = payload.rectificationResponsibleUnit?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let combined = [person, unit].filter { !$0.isEmpty }.joined(separator: " / ")
        if !combined.isEmpty {
            round.responsibleParty = combined
        }
    }

    private static func submitImmediateRectificationIfReady(_ round: RectificationRound) {
        let action = (round.actionTaken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPhoto = round.evidencePhotoData?.isEmpty == false
        guard !action.isEmpty, hasPhoto else { return }
        do {
            try round.submitForVerification()
        } catch {
            round.status = RectificationStatus.inProgress.rawValue
        }
    }
}

private extension NSManagedObjectContext {
    func performThrowing<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            perform {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

enum DaySummaryBuilder {
    static func summaries(
        from findings: [InspectionFinding],
        matching includeFinding: (InspectionFinding) -> Bool
    ) -> [DayInspectionSummary] {
        summaries(from: findings.filter(includeFinding))
    }

    static func summaries(from findings: [InspectionFinding]) -> [DayInspectionSummary] {
        let cal = Calendar.current
        let withDates = findings.filter { $0.effectiveArchiveDate != nil }
        let grouped = Dictionary(grouping: withDates) { f in
            cal.startOfDay(for: f.effectiveArchiveDate!)
        }

        return grouped.keys.sorted(by: >).map { day in
            let rows = grouped[day]!
            let locs = rows.compactMap { $0.location?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let unique = Array(Set(locs))
            let locText: String
            if unique.isEmpty {
                locText = "未填写地点"
            } else if unique.count == 1 {
                locText = unique[0]
            } else {
                locText = "多地（\(unique.prefix(2).joined(separator: "、"))等）"
            }
            return DayInspectionSummary(calendarDay: day, displayLocation: locText, hazardCount: rows.count)
        }
    }

    static func findings(on day: Date, from all: [InspectionFinding]) -> [InspectionFinding] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return all.filter { f in
            guard let t = f.effectiveArchiveDate else { return false }
            return t >= start && t < end
        }.sorted {
            let a0 = $0.effectiveArchiveDate ?? .distantPast
            let a1 = $1.effectiveArchiveDate ?? .distantPast
            if a0 != a1 { return a0 < a1 }
            return ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }
    }

    static func reportText(
        for findings: [InspectionFinding],
        kind: ShareableReportKind = .inspection
    ) -> String {
        let rows = sortedForReport(findings)
        let template = ReportTemplateSettings.current
        let dateLine = reportHeaderDateLine(for: rows)
        let reportCode = reportDocumentCode(
            kind: kind,
            projectName: rows.first?.recordProjectNameSnapshot
        )
        var lines: [String] = [
            "安全大师 · \(kind.coverTitle)",
            "文号：\(reportCode)",
            "项目名称：\(ReportProjectSettingsStore.coverProjectName(for: rows))",
            kind == .inspection
                ? "检查人：\(ReportProjectSettingsStore.coverInspectorName(for: rows))"
                : "回复人：\(ReportProjectSettingsStore.coverInspectorName(for: rows))",
            kind == .inspection ? "检查日期：\(dateLine)" : "回复日期：\(dateLine)",
            "共 \(rows.count) 条记录",
            String(repeating: "—", count: 24),
            ""
        ]
        appendCoverUnitLines(to: &lines, template: template)
        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "zh_CN")
        timeFmt.dateStyle = .medium
        timeFmt.timeStyle = .short
        for (i, f) in rows.enumerated() {
            appendFindingTextLines(to: &lines, finding: f, index: i + 1, kind: kind, timeFmt: timeFmt)
        }
        if template.includeSignoff {
            appendSignoffLines(to: &lines, template: template)
        }
        if template.includeLegalAppendix {
            appendLegalBasisAppendixLines(to: &lines, findings: rows)
        }
        return lines.joined(separator: "\n")
    }

    static func reportText(for findings: [InspectionFinding], day: Date) -> String {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let rows = sortedForReport(findings).filter { f in
            guard let t = f.effectiveArchiveDate else { return false }
            return cal.startOfDay(for: t) == start
        }
        if rows.isEmpty {
            return reportText(for: findings, kind: .inspection)
        }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateStyle = .long
        let title = fmt.string(from: day)
        let template = ReportTemplateSettings.current
        var lines: [String] = [
            "安全大师 · \(ShareableReportKind.inspection.coverTitle)",
            "文号：\(reportDocumentCode(kind: .inspection, baseDate: day, projectName: rows.first?.recordProjectNameSnapshot))",
            "项目名称：\(ReportProjectSettingsStore.coverProjectName(for: rows))",
            "检查人：\(ReportProjectSettingsStore.coverInspectorName(for: rows))",
            "检查日期：\(title)",
            "共 \(rows.count) 条记录",
            String(repeating: "—", count: 24),
            ""
        ]
        appendCoverUnitLines(to: &lines, template: template)
        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "zh_CN")
        timeFmt.dateStyle = .medium
        timeFmt.timeStyle = .short
        for (i, f) in rows.enumerated() {
            appendFindingTextLines(to: &lines, finding: f, index: i + 1, kind: .inspection, timeFmt: timeFmt)
        }
        if template.includeSignoff {
            appendSignoffLines(to: &lines, template: template)
        }
        if template.includeLegalAppendix {
            appendLegalBasisAppendixLines(to: &lines, findings: rows)
        }
        return lines.joined(separator: "\n")
    }

    private static func appendCoverUnitLines(to lines: inout [String], template: ReportTemplateSettings) {
        let units = [
            ("检查单位", template.inspectionUnit),
            ("施工单位", template.constructionUnit),
            ("监理单位", template.supervisionUnit)
        ]
        for (label, value) in units {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                lines.append("\(label)：\(trimmed)")
            }
        }
    }

    private static func appendFindingTextLines(
        to lines: inout [String],
        finding f: InspectionFinding,
        index: Int,
        kind: ShareableReportKind,
        timeFmt: DateFormatter
    ) {
        lines.append("【\(kind == .inspection ? "隐患整改通知单" : "隐患整改回复报告")】")
        lines.append("编号：\(itemDocumentCode(kind: kind, finding: f, index: index))")
        lines.append("部位：\(f.reportLocationPart)")
        lines.append("来源：\(f.sourceDisplayLabel)")
        if let external = f.externalNoticeSummary {
            lines.append(external)
        }
        lines.append("状态：\(f.reportRectificationStatusLabel)")
        let disc = f.discoveredAt ?? f.createdAt
        if let disc {
            lines.append("发现时间：\(timeFmt.string(from: disc))")
        }
        if kind == .rectification {
            appendRectificationComparisonTextLines(to: &lines, finding: f)
        } else {
            let template = ReportTemplateSettings.current
            if template.includeAccidentCategory, template.includeRiskLevel {
                lines.append("事故类别 / 风险等级：\(f.reportAccidentCategoryDisplay) / \(f.reportRiskLevelDisplay)")
            } else if template.includeAccidentCategory {
                lines.append("事故类别：\(f.reportAccidentCategoryDisplay)")
            } else if template.includeRiskLevel {
                lines.append("风险等级：\(f.reportRiskLevelDisplay)")
            }
            lines.append("存在问题：\(f.reportFormalIssueDescription())")
            lines.append("整改要求：\(f.reportFormalRectificationRequirement)")
            if template.includeLegalBasis {
                lines.append("整改依据：\(f.reportLegalBasisReferenceSummary())")
            }
            lines.append("整改责任人：\(f.reportResponsibleParty)")
            if template.includeDeadline {
                lines.append("限期：\(f.reportDeadlineLine)")
            }
        }
        lines.append("")
    }

    private static func appendRectificationComparisonTextLines(
        to lines: inout [String],
        finding f: InspectionFinding
    ) {
        let beforePhotoNote = f.sitePhotoDatasOrdered.isEmpty ? "（无整改前照片）" : "（整改前现场图见分享附件）"
        let afterPhotoNote: String
        if f.reportAfterRectificationPhotoData != nil {
            afterPhotoNote = "（整改后照片见分享附件）"
        } else {
            afterPhotoNote = "（无整改后照片）"
        }
        lines.append("整改前 | 整改后")
        lines.append("\(beforePhotoNote) | \(afterPhotoNote)")
        lines.append("检查情况：\(f.reportFormalInspectionSituation)")
        lines.append("存在问题：\(f.reportFormalIssueDescription(maxLength: 120))")
        let template = ReportTemplateSettings.current
        if template.includeLegalBasis {
            lines.append("整改依据：\(f.reportLegalBasisReferenceSummary())")
        }
        lines.append("整改要求：\(f.reportFormalRectificationRequirement)")
        if template.includeRiskLevel {
            lines.append("风险等级：\(f.reportRiskLevelDisplay)")
        }
        if template.includeDeadline {
            lines.append("限期：\(f.reportDeadlineLine)")
        }
        if template.includeAccidentCategory {
            lines.append("事故类别：\(f.reportAccidentCategoryDisplay)")
        }
        lines.append("整改情况：\(f.reportRectificationSituation)")
        lines.append("整改责任人：\(f.reportResponsibleParty)")
        lines.append("验收意见：\(f.reportRectificationAcceptanceOpinion)")
        lines.append("验收时间：\(f.reportRectificationAcceptanceTime)")
    }

    private static func appendSignoffLines(to lines: inout [String], template: ReportTemplateSettings) {
        lines.append(String(repeating: "—", count: 24))
        for label in template.normalized().signoffLabels {
            lines.append("\(label)（签字）：___________    日期：___________")
        }
    }

    private static func appendLegalBasisAppendixLines(to lines: inout [String], findings: [InspectionFinding]) {
        let appendix = findings.compactMap { finding -> (title: String, body: String)? in
            guard let body = finding.reportLegalBasisAppendixText else { return nil }
            return (title: finding.reportLocationPart, body: body)
        }
        guard !appendix.isEmpty else { return }
        lines.append("")
        lines.append("附录：整改依据原文")
        lines.append(String(repeating: "—", count: 24))
        for (idx, entry) in appendix.enumerated() {
            lines.append("[\(idx + 1)] \(entry.title)")
            lines.append(entry.body)
            lines.append("")
        }
    }

    static func reportDocumentCode(
        kind: ShareableReportKind,
        baseDate: Date = Date(),
        projectName: String? = nil
    ) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyyMMdd"
        return "\(projectAbbreviation(projectName))-\(kind.serialPrefix)-\(fmt.string(from: baseDate))"
    }

    static func itemDocumentCode(kind: ShareableReportKind, finding: InspectionFinding, index: Int) -> String {
        let base = finding.effectiveArchiveDate ?? finding.createdAt ?? Date()
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyyMMdd"
        return "\(projectAbbreviation(finding.recordProjectNameSnapshot))-\(kind.serialPrefix)-\(fmt.string(from: base))-\(String(format: "%03d", index))"
    }

    private static func projectAbbreviation(_ rawProjectName: String?) -> String {
        if let manual = ReportProjectSettingsStore.normalizedProjectAbbreviation(
            ReportProjectSettingsStore.projectAbbreviationRaw
        ) {
            return manual
        }
        let fallback = ReportProjectSettingsStore.projectNameRaw
        let source = (rawProjectName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? rawProjectName!
            : fallback
        if let auto = ReportProjectSettingsStore.normalizedProjectAbbreviation(source) {
            return String(auto.prefix(6))
        }
        return "XM"
    }

    static func sortedForReport(_ findings: [InspectionFinding]) -> [InspectionFinding] {
        findings.sorted {
            let a0 = $0.discoveredAt ?? $0.createdAt ?? .distantPast
            let a1 = $1.discoveredAt ?? $1.createdAt ?? .distantPast
            if a0 != a1 { return a0 < a1 }
            return ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }
    }

    static func reportHeaderDateLine(for findings: [InspectionFinding]) -> String {
        let cal = Calendar.current
        let days = Set(
            findings.compactMap { f -> Date? in
                guard let d = f.effectiveArchiveDate else { return nil }
                return cal.startOfDay(for: d)
            }
        ).sorted()
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateStyle = .long
        switch days.count {
        case 0:
            return fmt.string(from: Date())
        case 1:
            return fmt.string(from: days[0])
        default:
            return "\(fmt.string(from: days[0])) 至 \(fmt.string(from: days[days.count - 1]))"
        }
    }
}

#if os(iOS)
import UIKit

enum ShareableInspectionReportExporter {
    /// 优先用于 QuickLook 的文档 URL（docx，隐患排查可回退 pdf）。
    static func primaryPreviewURL(
        findings: [InspectionFinding],
        kind: ShareableReportKind = .inspection
    ) -> URL? {
        let list = DaySummaryBuilder.sortedForReport(findings)
        guard !list.isEmpty else { return nil }
        if let url = try? ShareableReportWordDocumentBuilder.buildTemporaryFileURL(findings: list, kind: kind) {
            return url
        }
        if kind == .inspection,
           let url = try? ShareableReportPDFBuilder.buildTemporaryFileURL(findings: list, kind: .inspection) {
            return url
        }
        return nil
    }

    static func activityItems(
        findings: [InspectionFinding],
        kind: ShareableReportKind = .inspection
    ) -> [Any] {
        let list = DaySummaryBuilder.sortedForReport(findings)
        guard !list.isEmpty else { return [] }

        if let url = try? ShareableReportWordDocumentBuilder.buildTemporaryFileURL(findings: list, kind: kind) {
            return [url]
        }
        if kind == .inspection,
           let url = try? ShareableReportPDFBuilder.buildTemporaryFileURL(findings: list, kind: .inspection) {
            return [url]
        }
        var items: [Any] = []
        let body = DaySummaryBuilder.reportText(for: list, kind: kind)
        let url = ReportExportFileNameBuilder.fileURL(
            findings: list,
            kind: kind,
            fileExtension: "txt"
        )
        if (try? body.write(to: url, atomically: true, encoding: .utf8)) != nil {
            items.append(url)
        } else {
            items.append(body)
        }
        for f in list {
            for d in f.sitePhotoDatasOrdered {
                guard !d.isEmpty, let ui = UIImage(data: d) else { continue }
                let s = ui.size
                guard s.width > 0, s.height > 0, s.width.isFinite, s.height.isFinite else { continue }
                items.append(ui)
            }
        }
        return items
    }
}
#endif
