//
//  InspectionFinding+CoreDataProperties.swift
//  
//
//  Created by mu on 2026/5/13.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension InspectionFinding {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<InspectionFinding> {
        return NSFetchRequest<InspectionFinding>(entityName: "InspectionFinding")
    }

    @NSManaged public var accidentCategoryMajor: String?
    @NSManaged public var accidentCategoryMinor: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var discoveredAt: Date?
    @NSManaged public var hazardDescription: String?
    @NSManaged public var findingId: String?
    @NSManaged public var legalBasis: String?
    @NSManaged public var location: String?
    @NSManaged public var photoData: Data?
    @NSManaged public var secondaryPhotoData: Data?
    @NSManaged public var rectificationMeasures: String?
    @NSManaged public var riskLevel: String?
    @NSManaged public var supplementaryText: String?
    @NSManaged public var rectificationRounds: NSOrderedSet?

}

// MARK: Generated accessors for rectificationRounds
extension InspectionFinding {

    @objc(insertObject:inRectificationRoundsAtIndex:)
    @NSManaged public func insertIntoRectificationRounds(_ value: RectificationRound, at idx: Int)

    @objc(removeObjectFromRectificationRoundsAtIndex:)
    @NSManaged public func removeFromRectificationRounds(at idx: Int)

    @objc(insertRectificationRounds:atIndexes:)
    @NSManaged public func insertIntoRectificationRounds(_ values: [RectificationRound], at indexes: NSIndexSet)

    @objc(removeRectificationRoundsAtIndexes:)
    @NSManaged public func removeFromRectificationRounds(at indexes: NSIndexSet)

    @objc(replaceObjectInRectificationRoundsAtIndex:withObject:)
    @NSManaged public func replaceRectificationRounds(at idx: Int, with value: RectificationRound)

    @objc(replaceRectificationRoundsAtIndexes:withRectificationRounds:)
    @NSManaged public func replaceRectificationRounds(at indexes: NSIndexSet, with values: [RectificationRound])

    @objc(addRectificationRoundsObject:)
    @NSManaged public func addToRectificationRounds(_ value: RectificationRound)

    @objc(removeRectificationRoundsObject:)
    @NSManaged public func removeFromRectificationRounds(_ value: RectificationRound)

    @objc(addRectificationRounds:)
    @NSManaged public func addToRectificationRounds(_ values: NSOrderedSet)

    @objc(removeRectificationRounds:)
    @NSManaged public func removeFromRectificationRounds(_ values: NSOrderedSet)

}

extension InspectionFinding : Identifiable {

}
