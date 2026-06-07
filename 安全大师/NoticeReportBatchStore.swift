//
//  NoticeReportBatchStore.swift
//  安全大师
//

import Foundation

private struct NoticeReportBatchItem: Codable {
    let trackingID: String
    let label: String
}

private struct NoticeReportBatch: Codable {
    let id: String
    let createdAt: Date
    let projectName: String
    let itemCount: Int
    let items: [NoticeReportBatchItem]
}

enum NoticeReportBatchStore {
    private static let batchesKey = "safemasterNoticeReportBatches.v1"

    struct LedgerRow: Identifiable {
        let id: String
        let createdAt: Date
        let projectName: String
        let totalCount: Int
        let respondedCount: Int
        let pendingCount: Int
        let itemLabels: [String]
        let trackingIDs: [String]

        var statusText: String {
            if pendingCount == 0 { return "已全部回复" }
            if respondedCount == 0 { return "未回复" }
            return "部分回复"
        }
    }

    static func recordInspectionBatch(for findings: [InspectionFinding]) {
        let tracked = findings.compactMap { finding -> NoticeReportBatchItem? in
            guard let trackingID = finding.reportTrackingID else { return nil }
            let issue = finding.recordListHazardSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            let brief = issue.isEmpty ? "未填写隐患摘要" : issue
            return NoticeReportBatchItem(
                trackingID: trackingID,
                label: "\(finding.reportLocationPart)：\(brief)"
            )
        }
        guard !tracked.isEmpty else { return }

        var batches = loadBatches()
        let batch = NoticeReportBatch(
            id: UUID().uuidString,
            createdAt: Date(),
            projectName: findings.first?.recordProjectNameSnapshot ?? "未填写项目",
            itemCount: tracked.count,
            items: tracked
        )
        batches.append(batch)
        if batches.count > 300 {
            batches = Array(batches.suffix(300))
        }
        saveBatches(batches)
    }

    static func rectificationBatchGuardError(for findings: [InspectionFinding]) -> String? {
        let selectedItems: [NoticeReportBatchItem] = findings.compactMap { finding in
            guard let trackingID = finding.reportTrackingID else { return nil }
            let issue = finding.recordListHazardSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            let brief = issue.isEmpty ? "未填写隐患摘要" : issue
            return NoticeReportBatchItem(
                trackingID: trackingID,
                label: "\(finding.reportLocationPart)：\(brief)"
            )
        }
        guard !selectedItems.isEmpty else { return nil }

        let selectedIDs = Set(selectedItems.map(\.trackingID))
        let latestMap = latestBatchIDByFindingID()
        let selectedBatchIDs = Set(selectedIDs.compactMap { latestMap[$0] })
        guard !selectedBatchIDs.isEmpty else { return nil }

        if selectedBatchIDs.count > 1 {
            return "当前勾选记录来自多份《隐患整改通知单》批次，请按批次分别生成整改回复报告。"
        }
        guard let batchID = selectedBatchIDs.first,
              let batch = latestBatch(by: batchID)
        else { return nil }

        let batchIDs = Set(batch.items.map(\.trackingID))
        if selectedIDs == batchIDs { return nil }

        let missing = batch.items.filter { !selectedIDs.contains($0.trackingID) }
        let missingPreview = missing.prefix(3).map(\.label).joined(separator: "\n")
        let more = missing.count > 3 ? "\n…另有 \(missing.count - 3) 条" : ""
        return """
        当前整改回复与通知单批次不一致：
        通知单批次共 \(batch.itemCount) 条，本次仅勾选 \(selectedIDs.count) 条。
        请按同一批次完整导出，或先在整改列表补齐剩余条目。
        未包含条目：
        \(missingPreview)\(more)
        """
    }

    static func ledgerRows(from findings: [InspectionFinding]) -> [LedgerRow] {
        let findingMap: [String: InspectionFinding] = Dictionary(
            uniqueKeysWithValues: findings.compactMap { finding -> (String, InspectionFinding)? in
                guard let key = finding.reportTrackingID else { return nil }
                return (key, finding)
            }
        )

        let latestPerBatch = latestBatchesByID()
        return latestPerBatch.values
            .map { batch in
                let responded = batch.items.reduce(0) { partial, item in
                    guard let finding = findingMap[item.trackingID] else { return partial }
                    return partial + (finding.isReadyForRectificationReplyExport ? 1 : 0)
                }
                return LedgerRow(
                    id: batch.id,
                    createdAt: batch.createdAt,
                    projectName: batch.projectName,
                    totalCount: batch.itemCount,
                    respondedCount: responded,
                    pendingCount: max(0, batch.itemCount - responded),
                    itemLabels: batch.items.map(\.label),
                    trackingIDs: batch.items.map(\.trackingID)
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private static func latestBatchIDByFindingID() -> [String: String] {
        let batches = loadBatches().sorted { $0.createdAt < $1.createdAt }
        var mapping: [String: String] = [:]
        for batch in batches {
            for item in batch.items {
                mapping[item.trackingID] = batch.id
            }
        }
        return mapping
    }

    private static func latestBatch(by batchID: String) -> NoticeReportBatch? {
        loadBatches()
            .filter { $0.id == batchID }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    private static func latestBatchesByID() -> [String: NoticeReportBatch] {
        let sorted = loadBatches().sorted { $0.createdAt < $1.createdAt }
        var map: [String: NoticeReportBatch] = [:]
        for batch in sorted {
            map[batch.id] = batch
        }
        return map
    }

    private static func loadBatches() -> [NoticeReportBatch] {
        guard let data = UserDefaults.standard.data(forKey: batchesKey) else { return [] }
        return (try? JSONDecoder().decode([NoticeReportBatch].self, from: data)) ?? []
    }

    private static func saveBatches(_ batches: [NoticeReportBatch]) {
        guard let data = try? JSONEncoder().encode(batches) else { return }
        UserDefaults.standard.set(data, forKey: batchesKey)
    }
}
