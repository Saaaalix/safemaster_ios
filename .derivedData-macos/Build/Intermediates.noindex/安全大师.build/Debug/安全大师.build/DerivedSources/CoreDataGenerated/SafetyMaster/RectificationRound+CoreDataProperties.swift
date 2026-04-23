//
//  RectificationRound+CoreDataProperties.swift
//  
//
//  Created by mu on 2026/5/13.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension RectificationRound {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<RectificationRound> {
        return NSFetchRequest<RectificationRound>(entityName: "RectificationRound")
    }

    @NSManaged public var actionTaken: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var evidencePhotoData: Data?
    @NSManaged public var mode: String?
    @NSManaged public var plannedDueAt: Date?
    @NSManaged public var responsibleParty: String?
    @NSManaged public var roundIndex: Int32
    @NSManaged public var status: String?
    @NSManaged public var verifiedAt: Date?
    @NSManaged public var verifierNote: String?
    @NSManaged public var finding: InspectionFinding?

}

extension RectificationRound : Identifiable {

}
