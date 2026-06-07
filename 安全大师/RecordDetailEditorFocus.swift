//
//  RecordDetailEditorFocus.swift
//  安全大师
//

import CoreData
import SwiftUI

/// 记录详情内多行输入共用焦点：用于键盘工具栏「完成」与滚动收起键盘。
enum RecordDetailEditorFocus: Hashable {
    case location(NSManagedObjectID)
    case supplementary(NSManagedObjectID)
    case rectificationResponsible(finding: NSManagedObjectID, round: NSManagedObjectID)
    case rectificationActionTaken(finding: NSManagedObjectID, round: NSManagedObjectID)
}
