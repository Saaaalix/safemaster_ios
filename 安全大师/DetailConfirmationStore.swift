//
//  DetailConfirmationStore.swift
//  安全大师
//

import Foundation

enum DetailConfirmationStore {
    private static let keyPrefix = "safemasterDetailConfirmed."

    static func isConfirmed(for finding: InspectionFinding) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: finding))
    }

    static func setConfirmed(_ confirmed: Bool, for finding: InspectionFinding) {
        UserDefaults.standard.set(confirmed, forKey: key(for: finding))
    }

    static func removeConfirmation(for finding: InspectionFinding) {
        UserDefaults.standard.removeObject(forKey: key(for: finding))
    }

    private static func key(for finding: InspectionFinding) -> String {
        if let id = finding.findingId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            return keyPrefix + id
        }
        return keyPrefix + finding.objectID.uriRepresentation().absoluteString
    }
}
