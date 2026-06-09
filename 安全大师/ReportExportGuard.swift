//
//  ReportExportGuard.swift
//  安全大师
//

import CoreData
import Foundation

enum ReportExportIssueLevel: String, CaseIterable, Hashable {
    case required
    case suggested

    var title: String {
        switch self {
        case .required:
            return "必须补充"
        case .suggested:
            return "建议补充"
        }
    }

    var explanation: String {
        switch self {
        case .required:
            return "影响正式报告生成"
        case .suggested:
            return "不影响生成，但建议完善"
        }
    }
}

struct ReportExportIssue: Identifiable, Hashable {
    let id = UUID()
    var level: ReportExportIssueLevel
    var title: String
    var recordLabel: String?
    var findingObjectID: NSManagedObjectID?
}

struct ReportExportGuardResult {
    var issues: [ReportExportIssue]

    var requiredIssues: [ReportExportIssue] {
        issues.filter { $0.level == .required }
    }

    var suggestedIssues: [ReportExportIssue] {
        issues.filter { $0.level == .suggested }
    }

    var hasBlockingIssues: Bool {
        !requiredIssues.isEmpty
    }

    var suggestedCount: Int {
        suggestedIssues.count
    }
}

enum ReportExportGuard {
    static func validate(findings: [InspectionFinding], kind: ShareableReportKind) -> ReportExportGuardResult {
        let rows = DaySummaryBuilder.sortedForReport(findings)
        var issues: [ReportExportIssue] = []

        if rows.isEmpty {
            issues.append(ReportExportIssue(level: .required, title: "缺少隐患记录", recordLabel: nil, findingObjectID: nil))
            return ReportExportGuardResult(issues: issues)
        }

        if ReportProjectSettingsStore.coverProjectName(for: rows).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || ReportProjectSettingsStore.coverProjectName(for: rows) == "未填写项目" {
            issues.append(ReportExportIssue(level: .required, title: "项目名称未填写", recordLabel: nil, findingObjectID: rows.first?.objectID))
        }

        let inspector = ReportProjectSettingsStore.coverInspectorName(for: rows)
        if inspector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || inspector == "未填写检查人" {
            issues.append(ReportExportIssue(level: .suggested, title: "检查人未填写", recordLabel: nil, findingObjectID: rows.first?.objectID))
        }

        for (index, finding) in rows.enumerated() {
            let label = recordLabel(for: finding, index: index + 1)
            appendIfMissing(finding.location, level: .required, title: "第 \(index + 1) 条部位/地点缺失", label: label, findingObjectID: finding.objectID, issues: &issues)
            appendIfMissing(finding.reportFormalIssueDescription(), level: .required, title: "第 \(index + 1) 条存在问题缺失", label: label, findingObjectID: finding.objectID, issues: &issues)
            appendIfMissing(finding.reportFormalRectificationRequirement, level: .required, title: "第 \(index + 1) 条整改要求缺失", label: label, findingObjectID: finding.objectID, issues: &issues)
            if finding.reportResponsibleParty.trimmingCharacters(in: .whitespacesAndNewlines) == "—" {
                issues.append(ReportExportIssue(level: .required, title: "第 \(index + 1) 条责任人缺失", recordLabel: label, findingObjectID: finding.objectID))
            }
            if finding.latestRectificationRound?.plannedDueAt == nil && finding.latestRectificationRound?.modeEnum != .immediate {
                issues.append(ReportExportIssue(level: .required, title: "第 \(index + 1) 条整改期限未填写", recordLabel: label, findingObjectID: finding.objectID))
            }
            if finding.reportLegalBasisReferenceSummary().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || finding.reportLegalBasisReferenceSummary() == "—" {
                issues.append(ReportExportIssue(level: .suggested, title: "第 \(index + 1) 条整改依据未填写", recordLabel: label, findingObjectID: finding.objectID))
            }
            if kind == .rectification {
                if finding.reportAfterRectificationPhotoData == nil {
                    issues.append(ReportExportIssue(level: .suggested, title: "第 \(index + 1) 条整改照片未上传", recordLabel: label, findingObjectID: finding.objectID))
                }
                if finding.reportRectificationAcceptanceOpinion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || finding.reportRectificationAcceptanceOpinion == "—" {
                    issues.append(ReportExportIssue(level: .suggested, title: "第 \(index + 1) 条复查意见未填写", recordLabel: label, findingObjectID: finding.objectID))
                }
            }
        }

        if kind == .inspection {
            issues.append(ReportExportIssue(level: .suggested, title: "接收人未填写", recordLabel: nil, findingObjectID: rows.first?.objectID))
        } else {
            issues.append(ReportExportIssue(level: .suggested, title: "复查人未填写", recordLabel: nil, findingObjectID: rows.first?.objectID))
        }

        return ReportExportGuardResult(issues: issues)
    }

    private static func appendIfMissing(
        _ value: String?,
        level: ReportExportIssueLevel,
        title: String,
        label: String,
        findingObjectID: NSManagedObjectID?,
        issues: inout [ReportExportIssue]
    ) {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty || text == "—" || text == "未填写" {
            issues.append(ReportExportIssue(level: level, title: title, recordLabel: label, findingObjectID: findingObjectID))
        }
    }

    private static func recordLabel(for finding: InspectionFinding, index: Int) -> String {
        let location = finding.reportLocationPart.trimmingCharacters(in: .whitespacesAndNewlines)
        let issue = finding.recordListHazardSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let locationText = location.isEmpty || location == "—" ? "未填写部位" : location
        let issueText = issue.isEmpty ? "未填写隐患摘要" : issue
        return "第 \(index) 条：\(locationText) · \(issueText)"
    }
}

enum ReportExportFileNameBuilder {
    private static let maxBaseLength = 72

    static func fileURL(
        findings: [InspectionFinding],
        kind: ShareableReportKind,
        fileExtension: String,
        directory: URL = FileManager.default.temporaryDirectory,
        date: Date = Date()
    ) -> URL {
        let project = normalizedProjectName(from: findings)
        let typeName: String
        switch kind {
        case .inspection:
            typeName = "隐患整改通知单"
        case .rectification:
            typeName = "隐患整改回复报告"
        }
        let dateText = dateFormatter.string(from: date)
        let rawBase = project.isEmpty
            ? "安全隐患整改通知单_\(dateText)"
            : "\(project)_\(typeName)_\(dateText)"
        let base = String(sanitized(rawBase).prefix(maxBaseLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return uniqueURL(directory: directory, baseName: base.isEmpty ? "安全隐患整改通知单_\(dateText)" : base, fileExtension: fileExtension)
    }

    static func fileURL(
        projectName: String,
        documentName: String,
        fileExtension: String,
        directory: URL = FileManager.default.temporaryDirectory,
        date: Date = Date()
    ) -> URL {
        let project = sanitized(projectName)
        let dateText = dateFormatter.string(from: date)
        let rawBase = project.isEmpty || project == "未填写"
            ? "安全隐患整改通知单_\(dateText)"
            : "\(project)_\(documentName)_\(dateText)"
        let base = String(sanitized(rawBase).prefix(maxBaseLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return uniqueURL(directory: directory, baseName: base.isEmpty ? "安全隐患整改通知单_\(dateText)" : base, fileExtension: fileExtension)
    }

    private static func normalizedProjectName(from findings: [InspectionFinding]) -> String {
        let project = ReportProjectSettingsStore.coverProjectName(for: findings)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if project.isEmpty || project == "未填写项目" { return "" }
        return sanitized(project)
    }

    private static func sanitized(_ raw: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\r\t")
        return raw
            .components(separatedBy: illegal)
            .joined(separator: "")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func uniqueURL(directory: URL, baseName: String, fileExtension: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(fileExtension)
        var index = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)_\(index)").appendingPathExtension(fileExtension)
            index += 1
        }
        return candidate
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
