//
//  InspectionFinding+Deletion.swift
//  安全大师
//

import CoreData

extension NSManagedObjectContext {
    /// 永久删除隐患记录（整改轮次随关系级联；现场照片为实体 Binary 属性，一并移除）。
    func deleteInspectionFindings(_ findings: [InspectionFinding]) throws {
        for finding in findings {
            delete(finding)
        }
        guard hasChanges else { return }
        try save()
    }
}

enum InspectionFindingDeletionCopy {
    static let singleRecordTitle = "确定永久删除？"
    static let singleRecordMessage =
        "此操作将永久删除该条排查记录，包含隐患内容、整改记录与现场照片，且无法恢复。"

    static func batchTitle(count: Int) -> String {
        "确定删除 \(count) 条记录？"
    }

    static func batchMessage(count: Int) -> String {
        "将永久删除所选的 \(count) 条排查记录，包含隐患内容、整改记录与现场照片，且无法恢复。"
    }

    static func dayPageTitle(count: Int) -> String {
        count == 1 ? singleRecordTitle : "确定删除本页 \(count) 条记录？"
    }

    static func dayPageMessage(count: Int) -> String {
        if count == 1 { return singleRecordMessage }
        return "将永久删除本页 \(count) 条排查记录，包含隐患内容、整改记录与现场照片，且无法恢复。"
    }
}
