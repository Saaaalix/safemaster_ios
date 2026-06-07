//
//  ImportedNoticeAIParser.swift
//  安全大师
//

import Foundation

enum ImportedNoticeAIParserError: LocalizedError {
    case emptyText
    case unsupportedExtractedText

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "未提取到可识别的文本。"
        case .unsupportedExtractedText:
            return "提取结果不是可识别正文，请重新提取或换用可复制文本的 PDF。"
        }
    }
}

private let importedNoticeParserTextLimit = 40_000

protocol ImportedNoticeAIParsing {
    func parse(extraction: ImportedNoticeExtraction, fileName: String?) async throws -> ImportedNoticeDraft
}

struct ImportedNoticeAIParser: ImportedNoticeAIParsing {
    private let ruleBasedParser: ImportedNoticeRuleBasedParser

    init(ruleBasedParser: ImportedNoticeRuleBasedParser = ImportedNoticeRuleBasedParser()) {
        self.ruleBasedParser = ruleBasedParser
    }

    func parse(extraction: ImportedNoticeExtraction, fileName: String? = nil) async throws -> ImportedNoticeDraft {
        guard let accessToken = KeychainStore.safemasterAccessToken() else {
            return try await ruleBasedParser.parse(extraction: extraction)
        }

        do {
            return try await SafeMasterAPIClient(baseURL: SafeMasterAPIConfiguration.baseURL)
                .parseImportedNoticeDraft(
                    accessToken: accessToken,
                    extraction: extraction,
                    fileName: fileName ?? ""
                )
        } catch {
            var fallback = try await ruleBasedParser.parse(extraction: extraction)
            fallback.warnings.append("云端 AI 识别未完成，已使用本地规则草稿：\(error.localizedDescription)")
            return fallback
        }
    }

    static func parse(extraction: ImportedNoticeExtraction, fileName: String? = nil) async throws -> ImportedNoticeDraft {
        try await ImportedNoticeAIParser().parse(extraction: extraction, fileName: fileName)
    }
}

struct ImportedNoticeRuleBasedParser: ImportedNoticeAIParsing {
    func parse(extraction: ImportedNoticeExtraction, fileName: String? = nil) async throws -> ImportedNoticeDraft {
        let fullCleanedText = extraction.cleanedText
        let didTruncate = fullCleanedText.count > importedNoticeParserTextLimit
        let cleanedText = didTruncate ? String(fullCleanedText.prefix(importedNoticeParserTextLimit)) : fullCleanedText
        guard !cleanedText.isEmpty else {
            throw ImportedNoticeAIParserError.emptyText
        }
        guard !looksLikeEmbeddedFileStructure(cleanedText) else {
            throw ImportedNoticeAIParserError.unsupportedExtractedText
        }

        let externalDraft = ExternalNoticeRecognizer.recognize(from: cleanedText)
        let warnings = didTruncate
            ? externalDraft.warnings + ["原文较长，已截取前 \(importedNoticeParserTextLimit) 字生成草稿，请重点核对。"]
            : externalDraft.warnings
        let documentID = extraction.documentID ?? UUID()
        let type = documentType(from: externalDraft, text: cleanedText)
        let hazards = hazardDrafts(from: externalDraft, in: cleanedText, documentType: type)
        return ImportedNoticeDraft(
            documentID: documentID,
            documentType: type,
            projectName: recognizedField(
                externalDraft.projectName,
                confidence: externalDraft.confidence[.projectName],
                in: cleanedText,
                labels: ["项目名称", "工程名称", "项目", "工程项目"],
                isRequired: type.isRequired(.projectName)
            ),
            issuer: recognizedField(
                externalDraft.issuer,
                confidence: externalDraft.confidence[.issuer],
                in: cleanedText,
                labels: ["发文单位", "检查单位", "通知单位", "下发单位", "签发单位"],
                isRequired: type.isRequired(.issuer)
            ),
            inspectedUnit: recognizedField(
                externalDraft.inspectedUnit,
                confidence: externalDraft.confidence[.inspectedUnit],
                in: cleanedText,
                labels: ["受检单位", "被检单位", "受查单位", "项目部", "回复单位", "受检单位（项目）"],
                isRequired: type.isRequired(.inspectedUnit)
            ),
            noticeNo: recognizedField(
                externalDraft.noticeNo,
                confidence: externalDraft.confidence[.noticeNo],
                in: cleanedText,
                labels: ["通知单编号", "文号", "编号", "通知编号"],
                isRequired: type.isRequired(.noticeNo)
            ),
            noticeDate: recognizedField(
                string(from: externalDraft.noticeDate),
                confidence: externalDraft.confidence[.noticeDate],
                in: cleanedText,
                labels: ["来文日期", "下发日期", "通知日期", "检查日期", "检查时间", "回复日期", "落款日期"],
                isRequired: type.isRequired(.noticeDate)
            ),
            rectificationDeadline: recognizedField(
                string(from: externalDraft.dueDate),
                confidence: externalDraft.confidence[.dueDate],
                in: cleanedText,
                labels: ["整改期限", "整改完成期限", "限期整改", "完成时限", "整改截止日期"],
                isRequired: type.isRequired(.rectificationDeadline)
            ),
            hazards: hazards,
            legalBasis: recognizedField(
                externalDraft.legalBasis,
                confidence: externalDraft.confidence[.legalBasis],
                in: cleanedText,
                labels: ["整改依据", "法律依据", "依据条款", "参考依据"],
                isRequired: type.isRequired(.legalBasis)
            ),
            summary: summary(from: externalDraft, hazards: hazards),
            confidence: averageConfidence(from: externalDraft, hazards: hazards),
            warnings: warnings
        )
    }

    private func hazardDrafts(
        from draft: ExternalNoticeRecognitionDraft,
        in text: String,
        documentType: ImportedNoticeDocumentType
    ) -> [ImportedNoticeHazardDraft] {
        if documentType == .rectificationReply {
            let replyItems = rectificationReplyHazards(in: text)
            if !replyItems.isEmpty {
                return replyItems
            }
        }

        let itemHazards = draft.issueItems.map { item in
            ImportedNoticeHazardDraft(
                location: recognizedField(
                    item.location,
                    confidence: draft.confidence[.location],
                    in: text,
                    labels: ["隐患部位", "隐患地点", "整改部位", "部位", "地点"],
                    isRequired: false
                ),
                description: recognizedField(
                    item.hazardDescription,
                    confidence: draft.confidence[.hazardDescription],
                    in: text,
                    labels: ["隐患描述", "存在问题", "整改问题", "限期整改问题", "问题描述"],
                    isRequired: true
                ),
                requirement: recognizedField(
                    item.rectificationMeasures,
                    confidence: draft.confidence[.rectificationMeasures],
                    in: text,
                    labels: ["整改要求", "整改措施", "整改意见", "处理措施", "整改情况"],
                    isRequired: true
                ),
                dueDate: recognizedField(
                    string(from: draft.dueDate),
                    confidence: draft.confidence[.dueDate],
                    in: text,
                    labels: ["整改期限", "整改完成期限", "限期整改", "完成时限", "整改截止日期"],
                    isRequired: false
                ),
                responsibleParty: recognizedField(
                    draft.responsibleParty,
                    confidence: draft.confidence[.responsibleParty],
                    in: text,
                    labels: ["整改责任人", "责任人", "责任单位", "整改负责人", "整改责任单位"],
                    isRequired: false
                )
            )
        }
        if !itemHazards.isEmpty {
            return itemHazards
        }

        let hasSingleHazard = [
            draft.location,
            draft.hazardDescription,
            draft.rectificationMeasures,
            draft.responsibleParty,
            string(from: draft.dueDate)
        ].contains { $0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        guard hasSingleHazard else { return [] }

        return [
            ImportedNoticeHazardDraft(
                location: recognizedField(
                    draft.location,
                    confidence: draft.confidence[.location],
                    in: text,
                    labels: ["隐患部位", "隐患地点", "整改部位", "部位", "地点"],
                    isRequired: false
                ),
                description: recognizedField(
                    draft.hazardDescription,
                    confidence: draft.confidence[.hazardDescription],
                    in: text,
                    labels: ["隐患描述", "存在问题", "整改问题", "限期整改问题", "问题描述"],
                    isRequired: true
                ),
                requirement: recognizedField(
                    draft.rectificationMeasures,
                    confidence: draft.confidence[.rectificationMeasures],
                    in: text,
                    labels: ["整改要求", "整改措施", "整改意见", "处理措施", "整改情况"],
                    isRequired: true
                ),
                dueDate: recognizedField(
                    string(from: draft.dueDate),
                    confidence: draft.confidence[.dueDate],
                    in: text,
                    labels: ["整改期限", "整改完成期限", "限期整改", "完成时限", "整改截止日期"],
                    isRequired: false
                ),
                responsibleParty: recognizedField(
                    draft.responsibleParty,
                    confidence: draft.confidence[.responsibleParty],
                    in: text,
                    labels: ["整改责任人", "责任人", "责任单位", "整改负责人", "整改责任单位"],
                    isRequired: false
                )
            )
        ]
    }

    private func recognizedField(
        _ value: String?,
        confidence: Double?,
        in text: String,
        labels: [String],
        isRequired: Bool = true
    ) -> ImportedNoticeRecognizedField {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let score = confidence ?? 0
        return ImportedNoticeRecognizedField(
            value: trimmed,
            confidence: score,
            sourceSnippet: sourceSnippet(for: trimmed, in: text, labels: labels),
            needsReview: isRequired && (trimmed.isEmpty || score < 0.85)
        )
    }

    private func sourceSnippet(for value: String, in text: String, labels: [String]) -> String? {
        if !value.isEmpty, let range = text.range(of: value) {
            return snippet(around: range, in: text)
        }
        for label in labels {
            if let range = text.range(of: label) {
                return snippet(around: range, in: text)
            }
        }
        return nil
    }

    private func snippet(around range: Range<String.Index>, in text: String) -> String {
        let lower = text.index(range.lowerBound, offsetBy: -60, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: 80, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[lower..<upper])
            .replacingOccurrences(of: "\n\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func documentType(
        from draft: ExternalNoticeRecognitionDraft,
        text: String
    ) -> ImportedNoticeDocumentType {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let replyKeywords = ["整改反馈", "整改回复", "整改情况", "反馈单", "回复报告", "审签", "已根据", "已按要求", "已组织", "已整改"]
        let noticeKeywords = ["整改通知书", "限期整改通知", "责令整改", "请于", "整改期限", "逾期未整改"]
        let replyScore = replyKeywords.filter { normalized.contains($0) }.count
        let noticeScore = noticeKeywords.filter { normalized.contains($0) }.count
        let hasReplyPair = normalized.contains("问题描述") && normalized.contains("整改情况")
        if draft.rectificationSituation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || replyScore >= 2
            || hasReplyPair
            || normalized.contains("整改回复")
            || normalized.contains("回复报告")
            || normalized.contains("整改反馈") {
            return .rectificationReply
        }
        if normalized.contains("会议纪要") || normalized.contains("会议记录") {
            return .meetingMinutes
        }
        if normalized.contains("检查记录") || normalized.contains("检查表") {
            return .inspectionRecord
        }
        if noticeScore > replyScore
            || normalized.contains("整改通知")
            || normalized.contains("隐患通知")
            || normalized.contains("限期整改")
            || !draft.issueItems.isEmpty {
            return .hazardNotice
        }
        return .unknown
    }

    private func string(from date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func averageConfidence(
        from draft: ExternalNoticeRecognitionDraft,
        hazards: [ImportedNoticeHazardDraft]
    ) -> Double {
        var scores = Array(draft.confidence.values)
        scores.append(contentsOf: hazards.flatMap {
            [
                $0.location.confidence,
                $0.description.confidence,
                $0.requirement.confidence,
                $0.dueDate.confidence,
                $0.responsibleParty.confidence
            ]
        }.filter { $0 > 0 })
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private func summary(
        from draft: ExternalNoticeRecognitionDraft,
        hazards: [ImportedNoticeHazardDraft]
    ) -> String {
        let candidates = [
            draft.projectName,
            draft.noticeNo,
            hazards.first?.description.value,
            draft.hazardDescription
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    private func rectificationReplyHazards(in text: String) -> [ImportedNoticeHazardDraft] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let pattern = #"(?s)(?:^|\n|\s)(?:[0-9０-９一二三四五六七八九十]+[、.．]\s*)?问题描述\s*[:：]\s*(.*?)(?:\n|\s)*整改情况\s*[:：]\s*(.*?)(?=(?:\n|\s)(?:[0-9０-９一二三四五六七八九十]+[、.．]\s*)?问题描述\s*[:：]|(?:\n|\s)[一二三四五六七八九十]+[、.．]\s*[^：:\n]{0,24}情况|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let matches = regex.matches(in: normalized, range: nsRange)

        return matches.compactMap { match -> ImportedNoticeHazardDraft? in
            guard match.numberOfRanges >= 3,
                  let descriptionRange = Range(match.range(at: 1), in: normalized),
                  let resultRange = Range(match.range(at: 2), in: normalized) else {
                return nil
            }
            let description = cleanReplyItemText(String(normalized[descriptionRange]))
            let result = cleanReplyItemText(String(normalized[resultRange]))
            guard !description.isEmpty || !result.isEmpty else { return nil }
            let sourceRange = Range(match.range(at: 0), in: normalized)
            let sourceSnippet = sourceRange.map { snippet(around: $0, in: normalized) }
            return ImportedNoticeHazardDraft(
                location: ImportedNoticeRecognizedField(value: "", confidence: 0, sourceSnippet: sourceSnippet, needsReview: false),
                description: ImportedNoticeRecognizedField(value: description, confidence: description.isEmpty ? 0 : 0.9, sourceSnippet: sourceSnippet, needsReview: description.isEmpty),
                requirement: ImportedNoticeRecognizedField(value: result, confidence: result.isEmpty ? 0 : 0.9, sourceSnippet: sourceSnippet, needsReview: result.isEmpty),
                dueDate: ImportedNoticeRecognizedField(value: "", confidence: 0, sourceSnippet: sourceSnippet, needsReview: false),
                responsibleParty: ImportedNoticeRecognizedField(value: "", confidence: 0, sourceSnippet: sourceSnippet, needsReview: false)
            )
        }
    }

    private func cleanReplyItemText(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: #"附件\s*[0-9０-９一二三四五六七八九十]+"#, with: "附件", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stopPatterns = [
            #"^[；;，,。]+"#,
            #"(?:\s+)?[一二三四五六七八九十]+[、.．]\s*$"#
        ]
        for pattern in stopPatterns {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func looksLikeEmbeddedFileStructure(_ text: String) -> Bool {
        let head = String(text.prefix(512)).trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("%PDF-") || head.hasPrefix("PK\u{03}\u{04}") || head.hasPrefix("bplist00") {
            return true
        }
        let pdfMarkers = [" obj", "endobj", "xref", "trailer", "%%EOF"]
        return pdfMarkers.filter { head.contains($0) }.count >= 3
    }
}

extension ImportedNoticeExtraction {
    var cleanedText: String {
        rawText
            .replacingOccurrences(of: "\u{0000}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
