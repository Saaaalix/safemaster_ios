//
//  ReportExportEventStore.swift
//  安全大师
//

import Foundation

enum ReportExportEventStore {
    private static let prefix = "safemaster.reportExport.generatedAt."

    static func recordGenerated(findings: [InspectionFinding], at date: Date = Date()) {
        for finding in findings {
            guard let key = storageKey(for: finding) else { continue }
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: key)
        }
    }

    static func generatedAt(for finding: InspectionFinding) -> Date? {
        guard let key = storageKey(for: finding) else { return nil }
        let raw = UserDefaults.standard.double(forKey: key)
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    private static func storageKey(for finding: InspectionFinding) -> String? {
        if let trackingID = finding.reportTrackingID?.trimmingCharacters(in: .whitespacesAndNewlines), !trackingID.isEmpty {
            return prefix + trackingID
        }
        let uri = finding.objectID.uriRepresentation().absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        return uri.isEmpty ? nil : prefix + uri
    }
}

