//
//  ExternalNoticePersistenceService.swift
//  安全大师
//

import CoreData
import Foundation

enum ExternalNoticePersistenceDestination {
    case hazardNotice
    case rectificationReply
}

struct ExternalNoticePersistenceInput {
    var documentID: UUID?
    var draftID: UUID?
    var issuerLabel: String
    var issuer: String
    var inspectedUnit: String
    var noticeNo: String
    var noticeDate: Date
    var projectName: String
    var inspectorName: String
    var hazardCountText: String
    var location: String
    var hazardDescription: String
    var rectificationMeasures: String
    var legalBasis: String
    var rectificationSituation: String
    var plannedDueAt: Date
    var responsibleParty: String
    var destination: ExternalNoticePersistenceDestination
}

struct ExternalNoticePersistenceResult {
    enum Status {
        case saved
        case updated
    }

    var status: Status
    var findingObjectID: NSManagedObjectID
    var errorLog: [String] = []
    var conflictNotes: [String] = []
}

enum ExternalNoticePersistenceService {
    @discardableResult
    static func save(
        input: ExternalNoticePersistenceInput,
        context: NSManagedObjectContext
    ) throws -> ExternalNoticePersistenceResult {
        let existing = try existingFinding(for: input, context: context)
        let finding = existing ?? InspectionFinding(context: context)
        let isNew = existing == nil

        apply(input: input, to: finding, context: context, isNew: isNew)
        try deleteDuplicateImportedFindings(for: input, keeping: finding, context: context)

        do {
            try context.save()
            return ExternalNoticePersistenceResult(status: isNew ? .saved : .updated, findingObjectID: finding.objectID)
        } catch {
            context.rollback()
            throw error
        }
    }

    @discardableResult
    static func save(
        importedNoticeDraft draft: ImportedNoticeDraft,
        context: NSManagedObjectContext
    ) throws -> ExternalNoticePersistenceResult {
        try save(input: ExternalNoticePersistenceInput(importedNoticeDraft: draft), context: context)
    }

    @discardableResult
    static func deleteImportedNoticeFindings(
        documentID: UUID,
        draft: ImportedNoticeDraft?,
        context: NSManagedObjectContext
    ) throws -> Int {
        let input = draft.map(ExternalNoticePersistenceInput.init(importedNoticeDraft:))
        let request = NSFetchRequest<InspectionFinding>(entityName: "InspectionFinding")
        request.predicate = NSPredicate(format: "sourceType == %@", "external")
        let findings = try context.fetch(request)
        let targets = findings.filter { finding in
            if finding.findingId == importedFindingID(documentID: documentID) {
                return true
            }
            guard let input else { return false }
            return probablyMatchesImportedNotice(finding, input: input)
        }
        targets.forEach(context.delete)
        if !targets.isEmpty {
            try context.save()
        }
        return targets.count
    }

    private static func apply(
        input: ExternalNoticePersistenceInput,
        to finding: InspectionFinding,
        context: NSManagedObjectContext,
        isNew: Bool
    ) {
        if isNew {
            finding.findingId = input.documentID.map(importedFindingID(documentID:)) ?? UUID().uuidString
            finding.createdAt = Date()
        } else if let documentID = input.documentID,
                  finding.findingId?.hasPrefix("imported-notice:") != true {
            finding.findingId = importedFindingID(documentID: documentID)
        }

        finding.discoveredAt = input.noticeDate
        finding.location = trimmedOrNil(input.location)
        finding.supplementaryText = externalSupplementarySummary(from: input)
        finding.hazardDescription = trimmedOrNil(input.hazardDescription) ?? "外部通知单归档（未提取隐患条目）"
        finding.rectificationMeasures = trimmedOrNil(input.rectificationMeasures) ?? "请在详情页补录具体隐患条目与整改要求。"
        finding.legalBasis = trimmedOrNil(input.legalBasis)
        finding.riskLevel = HazardRiskLevel.normalizedForStorage(finding.riskLevel ?? "一般风险")
        finding.reportProjectName = trimmedOrNil(input.projectName) ?? trimmedOrNil(input.inspectedUnit) ?? "外部检查归档"
        finding.reportInspectorName = trimmedOrNil(
            input.inspectorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "外部检查" : input.inspectorName
        )
        finding.sourceType = "external"
        finding.externalIssuer = trimmedOrNil(input.issuer)
        finding.externalNoticeNo = trimmedOrNil(input.noticeNo)
        finding.externalNoticeDate = input.noticeDate

        applyRectification(input: input, to: finding, context: context)
    }

    private static func applyRectification(
        input: ExternalNoticePersistenceInput,
        to finding: InspectionFinding,
        context: NSManagedObjectContext
    ) {
        let round: RectificationRound?
        if let existing = finding.latestRectificationRound {
            round = existing
        } else {
            switch input.destination {
            case .hazardNotice:
                round = finding.startFirstRectificationRound(mode: .scheduled, plannedDueAt: input.plannedDueAt, context: context)
            case .rectificationReply:
                round = finding.startFirstRectificationRound(mode: .immediate, plannedDueAt: nil, context: context)
            }
        }

        guard let round else { return }
        round.responsibleParty = trimmedOrNil(input.responsibleParty)
        switch input.destination {
        case .hazardNotice:
            round.mode = RectificationMode.scheduled.rawValue
            round.plannedDueAt = input.plannedDueAt
            if round.statusEnum == .passed {
                break
            }
            if round.statusEnum == .failed {
                break
            }
            round.status = RectificationStatus.inProgress.rawValue
        case .rectificationReply:
            round.mode = RectificationMode.immediate.rawValue
            round.plannedDueAt = nil
            let note = trimmedOrNil(input.rectificationSituation)
                ?? trimmedOrNil(input.rectificationMeasures)
                ?? "外部整改回复已归档，详情待补录。"
            round.actionTaken = note
            round.status = RectificationStatus.passed.rawValue
            round.verifiedAt = Date()
            round.verifierNote = "外部通知单导入：按整改回复归档"
        }
    }

    private static func existingFinding(
        for input: ExternalNoticePersistenceInput,
        context: NSManagedObjectContext
    ) throws -> InspectionFinding? {
        if let documentID = input.documentID {
            let request = NSFetchRequest<InspectionFinding>(entityName: "InspectionFinding")
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "findingId == %@", importedFindingID(documentID: documentID))
            if let existing = try context.fetch(request).first {
                return existing
            }
        }

        let request = NSFetchRequest<InspectionFinding>(entityName: "InspectionFinding")
        request.predicate = NSPredicate(format: "sourceType == %@", "external")
        return try context.fetch(request).first { probablyMatchesImportedNotice($0, input: input) }
    }

    private static func deleteDuplicateImportedFindings(
        for input: ExternalNoticePersistenceInput,
        keeping keptFinding: InspectionFinding,
        context: NSManagedObjectContext
    ) throws {
        let request = NSFetchRequest<InspectionFinding>(entityName: "InspectionFinding")
        request.predicate = NSPredicate(format: "sourceType == %@", "external")
        let targets = try context.fetch(request).filter { finding in
            guard finding !== keptFinding else { return false }
            if let documentID = input.documentID,
               finding.findingId == importedFindingID(documentID: documentID) {
                return true
            }
            return probablyMatchesImportedNotice(finding, input: input)
        }
        targets.forEach(context.delete)
    }

    private static func importedFindingID(documentID: UUID) -> String {
        "imported-notice:\(documentID.uuidString)"
    }

    private static func probablyMatchesImportedNotice(
        _ finding: InspectionFinding,
        input: ExternalNoticePersistenceInput
    ) -> Bool {
        guard finding.sourceTypeNormalized == "external" else { return false }

        let inputNo = trimmedOrNil(input.noticeNo)
        let findingNo = trimmedOrNil(finding.externalNoticeNo ?? "")
        if let inputNo, let findingNo, inputNo == findingNo {
            return true
        }

        let sameDate = finding.externalNoticeDate.map {
            Calendar.current.isDate($0, inSameDayAs: input.noticeDate)
        } ?? false
        guard sameDate else { return false }

        let inputIssuer = trimmedOrNil(input.issuer)
        let findingIssuer = trimmedOrNil(finding.externalIssuer ?? "")
        if let inputIssuer, let findingIssuer, inputIssuer == findingIssuer {
            return true
        }

        let inputIssue = trimmedOrNil(input.hazardDescription)
        let findingIssue = trimmedOrNil(finding.hazardDescription ?? "")
        if let inputIssue, let findingIssue {
            return inputIssue.prefix(80) == findingIssue.prefix(80)
        }

        return false
    }

    private static func externalSupplementarySummary(from input: ExternalNoticePersistenceInput) -> String? {
        var lines: [String] = ["来源：外部通知单"]
        if let unit = trimmedOrNil(input.issuer) {
            lines.append("\(input.issuerLabel)：\(unit)")
        }
        if let inspected = trimmedOrNil(input.inspectedUnit) { lines.append("受检单位：\(inspected)") }
        if let no = trimmedOrNil(input.noticeNo) { lines.append("来文编号：\(no)") }
        if let inspector = trimmedOrNil(input.inspectorName) { lines.append("检查人：\(inspector)") }
        if let count = trimmedOrNil(input.hazardCountText) { lines.append("隐患条数：\(count)") }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .medium
        f.timeStyle = .none
        lines.append("来文日期：\(f.string(from: input.noticeDate))")
        return lines.joined(separator: "；")
    }

    private static func trimmedOrNil(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

extension ExternalNoticePersistenceInput {
    private static let maxJoinedHazardFieldCharacters = 3_000
    private static let maxSingleHazardFieldCharacters = 800

    init(importedNoticeDraft draft: ImportedNoticeDraft) {
        let hazards = draft.hazards
        let firstHazard = hazards.first
        self.init(
            documentID: draft.documentID,
            draftID: draft.id,
            issuerLabel: "发文单位",
            issuer: draft.issuer.value,
            inspectedUnit: draft.inspectedUnit.value,
            noticeNo: draft.noticeNo.value,
            noticeDate: Self.parsedDate(from: draft.noticeDate.value) ?? Date(),
            projectName: draft.projectName.value,
            inspectorName: "外部检查",
            hazardCountText: hazards.isEmpty ? "" : "\(hazards.count)",
            location: Self.joinHazardFields(hazards, keyPath: \.location) ?? firstHazard?.location.value ?? "",
            hazardDescription: Self.joinHazardFields(hazards, keyPath: \.description) ?? firstHazard?.description.value ?? "",
            rectificationMeasures: Self.joinHazardFields(hazards, keyPath: \.requirement) ?? firstHazard?.requirement.value ?? "",
            legalBasis: draft.legalBasis.value,
            rectificationSituation: "",
            plannedDueAt: Self.parsedDate(from: draft.rectificationDeadline.value)
                ?? Self.parsedDate(from: firstHazard?.dueDate.value)
                ?? Calendar.current.date(byAdding: .day, value: 3, to: Date())
                ?? Date(),
            responsibleParty: Self.joinHazardFields(hazards, keyPath: \.responsibleParty) ?? firstHazard?.responsibleParty.value ?? "",
            destination: draft.documentType == .rectificationReply ? .rectificationReply : .hazardNotice
        )
    }

    private static func joinHazardFields(
        _ hazards: [ImportedNoticeHazardDraft],
        keyPath: KeyPath<ImportedNoticeHazardDraft, ImportedNoticeRecognizedField>
    ) -> String? {
        var total = 0
        var values: [String] = []
        for (index, hazard) in hazards.enumerated() {
            let value = hazard[keyPath: keyPath].value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let limited = limit(value, maxCharacters: maxSingleHazardFieldCharacters)
            let line = hazards.count > 1 ? "\(index + 1). \(limited)" : limited
            let nextTotal = total + line.count + (values.isEmpty ? 0 : 1)
            if nextTotal > maxJoinedHazardFieldCharacters {
                values.append("……其余内容请在原文件中核对。")
                break
            }
            values.append(line)
            total = nextTotal
        }
        guard !values.isEmpty else { return nil }
        return values.joined(separator: "\n")
    }

    private static func limit(_ raw: String, maxCharacters: Int) -> String {
        guard raw.count > maxCharacters else { return raw }
        return String(raw.prefix(maxCharacters)) + "……"
    }

    private static func parsedDate(from raw: String?) -> Date? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        for format in ["yyyy-MM-dd", "yyyy/M/d", "yyyy.M.d", "yyyy年M月d日"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}
