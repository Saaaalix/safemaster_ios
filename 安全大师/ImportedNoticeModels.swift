//
//  ImportedNoticeModels.swift
//  安全大师
//

import Foundation

enum ImportedNoticeProcessingStatus: String, Codable, CaseIterable, Hashable {
    case imported
    case pendingExtraction
    case extracting
    case extracted
    case extractionFailed
    case pendingAIParsing
    case parsing
    case draftReady
    case parsingFailed
    case reviewed
    case archivedOnly
}

enum ImportedNoticeFileType: String, Codable, CaseIterable, Hashable {
    case pdf
    case word
    case image
    case text
    case unknown

    static func infer(fromFileExtension ext: String) -> ImportedNoticeFileType {
        switch ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pdf":
            return .pdf
        case "doc", "docx", "rtf":
            return .word
        case "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp":
            return .image
        case "txt", "text", "csv", "json", "md":
            return .text
        default:
            return .unknown
        }
    }
}

enum ImportedNoticeDocumentType: String, Codable, CaseIterable, Hashable {
    case hazardNotice
    case rectificationReply
    case inspectionRecord
    case meetingMinutes
    case unknown
}

enum ImportedNoticeDraftField: String, Codable, CaseIterable, Hashable {
    case projectName
    case issuer
    case inspectedUnit
    case noticeNo
    case noticeDate
    case rectificationDeadline
    case legalBasis
}

extension ImportedNoticeDocumentType {
    var requiredDraftFields: Set<ImportedNoticeDraftField> {
        switch self {
        case .hazardNotice:
            return [.issuer, .inspectedUnit, .noticeNo, .noticeDate, .rectificationDeadline]
        case .rectificationReply:
            return [.inspectedUnit, .noticeDate]
        case .inspectionRecord:
            return [.inspectedUnit, .noticeDate]
        case .meetingMinutes, .unknown:
            return []
        }
    }

    func isRequired(_ field: ImportedNoticeDraftField) -> Bool {
        requiredDraftFields.contains(field)
    }
}

enum ImportedNoticeTextQuality: String, Codable, CaseIterable, Hashable {
    case high
    case medium
    case low
    case empty

    static func assess(_ text: String) -> ImportedNoticeTextQuality {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.count {
        case 0:
            return .empty
        case 1..<80:
            return .low
        case 80..<400:
            return .medium
        default:
            return .high
        }
    }
}

struct ImportedNoticeDocument: Identifiable, Codable, Hashable {
    var id: UUID
    var fileName: String
    var fileExtension: String
    var importedAt: Date
    var fileSizeBytes: Int64
    var storedFileName: String
    var extractedTextFileName: String
    var extractedTextLength: Int
    var extractedTextPreview: String
    var processingStatus: ImportedNoticeProcessingStatus

    init(
        id: UUID,
        fileName: String,
        fileExtension: String,
        importedAt: Date,
        fileSizeBytes: Int64,
        storedFileName: String,
        extractedTextFileName: String,
        extractedTextLength: Int,
        extractedTextPreview: String,
        processingStatus: ImportedNoticeProcessingStatus? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.importedAt = importedAt
        self.fileSizeBytes = fileSizeBytes
        self.storedFileName = storedFileName
        self.extractedTextFileName = extractedTextFileName
        self.extractedTextLength = extractedTextLength
        self.extractedTextPreview = extractedTextPreview
        self.processingStatus = processingStatus ?? (extractedTextLength > 0 ? .extracted : .pendingExtraction)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case fileName
        case fileExtension
        case importedAt
        case fileSizeBytes
        case storedFileName
        case extractedTextFileName
        case extractedTextLength
        case extractedTextPreview
        case processingStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let extractedTextLength = try container.decode(Int.self, forKey: .extractedTextLength)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            fileName: try container.decode(String.self, forKey: .fileName),
            fileExtension: try container.decode(String.self, forKey: .fileExtension),
            importedAt: try container.decode(Date.self, forKey: .importedAt),
            fileSizeBytes: try container.decode(Int64.self, forKey: .fileSizeBytes),
            storedFileName: try container.decode(String.self, forKey: .storedFileName),
            extractedTextFileName: try container.decode(String.self, forKey: .extractedTextFileName),
            extractedTextLength: extractedTextLength,
            extractedTextPreview: try container.decode(String.self, forKey: .extractedTextPreview),
            processingStatus: try container.decodeIfPresent(ImportedNoticeProcessingStatus.self, forKey: .processingStatus)
        )
    }
}

extension ImportedNoticeDocument {
    var fileType: ImportedNoticeFileType {
        ImportedNoticeFileType.infer(fromFileExtension: fileExtension)
    }

    var textQuality: ImportedNoticeTextQuality {
        if extractedTextLength <= 0 { return .empty }
        return ImportedNoticeTextQuality.assess(extractedTextPreview)
    }
}

struct ImportedNoticeExtraction: Identifiable, Codable, Hashable {
    var id: UUID
    var documentID: UUID?
    var rawText: String
    var sourceDescription: String
    var warnings: [String]
    var quality: ImportedNoticeTextQuality
    var extractedAt: Date

    init(
        id: UUID = UUID(),
        documentID: UUID? = nil,
        rawText: String,
        sourceDescription: String,
        warnings: [String] = [],
        quality: ImportedNoticeTextQuality? = nil,
        extractedAt: Date = Date()
    ) {
        self.id = id
        self.documentID = documentID
        self.rawText = rawText
        self.sourceDescription = sourceDescription
        self.warnings = warnings
        self.quality = quality ?? ImportedNoticeTextQuality.assess(rawText)
        self.extractedAt = extractedAt
    }

    init(documentID: UUID?, result: ImportedNoticeTextExtractionResult) {
        self.init(
            documentID: documentID,
            rawText: result.rawText,
            sourceDescription: result.sourceDescription,
            warnings: result.warnings
        )
    }
}

struct ImportedNoticeRecognizedField: Identifiable, Codable, Hashable {
    var id: UUID
    var value: String
    var confidence: Double
    var sourceSnippet: String?
    var needsReview: Bool

    init(
        id: UUID = UUID(),
        value: String = "",
        confidence: Double = 0,
        sourceSnippet: String? = nil,
        needsReview: Bool? = nil
    ) {
        self.id = id
        self.value = value
        self.confidence = confidence
        self.sourceSnippet = sourceSnippet
        self.needsReview = needsReview ?? value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || confidence < 0.85
    }

    static func empty() -> ImportedNoticeRecognizedField {
        ImportedNoticeRecognizedField()
    }
}

struct ImportedNoticeHazardDraft: Identifiable, Codable, Hashable {
    var id: UUID
    var location: ImportedNoticeRecognizedField
    var description: ImportedNoticeRecognizedField
    var requirement: ImportedNoticeRecognizedField
    var dueDate: ImportedNoticeRecognizedField
    var responsibleParty: ImportedNoticeRecognizedField

    init(
        id: UUID = UUID(),
        location: ImportedNoticeRecognizedField = .empty(),
        description: ImportedNoticeRecognizedField = .empty(),
        requirement: ImportedNoticeRecognizedField = .empty(),
        dueDate: ImportedNoticeRecognizedField = .empty(),
        responsibleParty: ImportedNoticeRecognizedField = .empty()
    ) {
        self.id = id
        self.location = location
        self.description = description
        self.requirement = requirement
        self.dueDate = dueDate
        self.responsibleParty = responsibleParty
    }
}

struct ImportedNoticeDraft: Identifiable, Codable, Hashable {
    var id: UUID
    var documentID: UUID

    var documentType: ImportedNoticeDocumentType
    var projectName: ImportedNoticeRecognizedField
    var issuer: ImportedNoticeRecognizedField
    var inspectedUnit: ImportedNoticeRecognizedField
    var noticeNo: ImportedNoticeRecognizedField
    var noticeDate: ImportedNoticeRecognizedField
    var rectificationDeadline: ImportedNoticeRecognizedField

    var hazards: [ImportedNoticeHazardDraft]
    var legalBasis: ImportedNoticeRecognizedField

    var summary: String
    var confidence: Double
    var warnings: [String]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        documentID: UUID,
        documentType: ImportedNoticeDocumentType = .unknown,
        projectName: ImportedNoticeRecognizedField = .empty(),
        issuer: ImportedNoticeRecognizedField = .empty(),
        inspectedUnit: ImportedNoticeRecognizedField = .empty(),
        noticeNo: ImportedNoticeRecognizedField = .empty(),
        noticeDate: ImportedNoticeRecognizedField = .empty(),
        rectificationDeadline: ImportedNoticeRecognizedField = .empty(),
        hazards: [ImportedNoticeHazardDraft] = [],
        legalBasis: ImportedNoticeRecognizedField = .empty(),
        summary: String = "",
        confidence: Double = 0,
        warnings: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.documentID = documentID
        self.documentType = documentType
        self.projectName = projectName
        self.issuer = issuer
        self.inspectedUnit = inspectedUnit
        self.noticeNo = noticeNo
        self.noticeDate = noticeDate
        self.rectificationDeadline = rectificationDeadline
        self.hazards = hazards
        self.legalBasis = legalBasis
        self.summary = summary
        self.confidence = confidence
        self.warnings = warnings
        self.createdAt = createdAt
    }
}

extension ImportedNoticeDraft {
    var requiredFields: Set<ImportedNoticeDraftField> {
        documentType.requiredDraftFields
    }

    func isRequired(_ field: ImportedNoticeDraftField) -> Bool {
        documentType.isRequired(field)
    }

    func needsAttention(_ field: ImportedNoticeDraftField) -> Bool {
        guard isRequired(field) else { return false }
        let recognizedField: ImportedNoticeRecognizedField
        switch field {
        case .projectName:
            recognizedField = projectName
        case .issuer:
            recognizedField = issuer
        case .inspectedUnit:
            recognizedField = inspectedUnit
        case .noticeNo:
            recognizedField = noticeNo
        case .noticeDate:
            recognizedField = noticeDate
        case .rectificationDeadline:
            recognizedField = rectificationDeadline
        case .legalBasis:
            recognizedField = legalBasis
        }
        return recognizedField.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || recognizedField.needsReview
    }

    init(documentID: UUID, recognitionDraft draft: ExternalNoticeRecognitionDraft) {
        let hazards = ImportedNoticeDraft.hazardDrafts(from: draft)
        self.init(
            documentID: documentID,
            documentType: draft.rectificationSituation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? .rectificationReply : .hazardNotice,
            projectName: ImportedNoticeDraft.field(draft.projectName, confidence: draft.confidence[.projectName]),
            issuer: ImportedNoticeDraft.field(draft.issuer, confidence: draft.confidence[.issuer]),
            inspectedUnit: ImportedNoticeDraft.field(draft.inspectedUnit, confidence: draft.confidence[.inspectedUnit]),
            noticeNo: ImportedNoticeDraft.field(draft.noticeNo, confidence: draft.confidence[.noticeNo]),
            noticeDate: ImportedNoticeDraft.field(ImportedNoticeDraft.string(from: draft.noticeDate), confidence: draft.confidence[.noticeDate]),
            rectificationDeadline: ImportedNoticeDraft.field(ImportedNoticeDraft.string(from: draft.dueDate), confidence: draft.confidence[.dueDate]),
            hazards: hazards,
            legalBasis: ImportedNoticeDraft.field(draft.legalBasis, confidence: draft.confidence[.legalBasis]),
            summary: ImportedNoticeDraft.summary(from: draft, hazards: hazards),
            confidence: ImportedNoticeDraft.averageConfidence(from: draft),
            warnings: draft.warnings
        )
    }

    private static func hazardDrafts(from draft: ExternalNoticeRecognitionDraft) -> [ImportedNoticeHazardDraft] {
        let itemHazards = draft.issueItems.map { item in
            ImportedNoticeHazardDraft(
                location: field(item.location, confidence: draft.confidence[.location]),
                description: field(item.hazardDescription, confidence: draft.confidence[.hazardDescription]),
                requirement: field(item.rectificationMeasures, confidence: draft.confidence[.rectificationMeasures]),
                dueDate: field(string(from: draft.dueDate), confidence: draft.confidence[.dueDate]),
                responsibleParty: field(draft.responsibleParty, confidence: draft.confidence[.responsibleParty])
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
                location: field(draft.location, confidence: draft.confidence[.location]),
                description: field(draft.hazardDescription, confidence: draft.confidence[.hazardDescription]),
                requirement: field(draft.rectificationMeasures, confidence: draft.confidence[.rectificationMeasures]),
                dueDate: field(string(from: draft.dueDate), confidence: draft.confidence[.dueDate]),
                responsibleParty: field(draft.responsibleParty, confidence: draft.confidence[.responsibleParty])
            )
        ]
    }

    private static func field(_ value: String?, confidence: Double?) -> ImportedNoticeRecognizedField {
        ImportedNoticeRecognizedField(value: value ?? "", confidence: confidence ?? 0)
    }

    private static func string(from date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func averageConfidence(from draft: ExternalNoticeRecognitionDraft) -> Double {
        guard !draft.confidence.isEmpty else { return 0 }
        let total = draft.confidence.values.reduce(0, +)
        return total / Double(draft.confidence.count)
    }

    private static func summary(from draft: ExternalNoticeRecognitionDraft, hazards: [ImportedNoticeHazardDraft]) -> String {
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
}
