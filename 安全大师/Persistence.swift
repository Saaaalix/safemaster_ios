//
//  Persistence.swift
//  安全大师
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let ctx = result.container.viewContext
        let cal = Calendar.current
        let day = cal.startOfDay(for: Date())
        for i in 0..<3 {
            let f = InspectionFinding(context: ctx)
            f.findingId = UUID().uuidString
            if let t = cal.date(byAdding: .hour, value: i, to: day) {
                f.createdAt = t
                f.discoveredAt = t
            }
            f.location = i == 0 ? "一号楼脚手架区" : "基坑东侧"
            f.reportProjectName = "示例工程项目"
            f.reportInspectorName = "张三"
            f.hazardDescription = "示例：临边防护栏杆缺失或高度不足。"
            f.rectificationMeasures = "立即搭设符合规范的临边防护，验收合格后方可作业。"
            f.riskLevel = "较大风险"
            f.accidentCategoryMajor = "高处与建筑施工类"
            f.accidentCategoryMinor = "高处坠落"
            f.legalBasis = "《建筑施工高处作业安全技术规范》JGJ 80-2016 第4.1.1条：临边作业的防护栏杆应由横杆、立杆及挡脚板组成，防护栏杆应符合下列规定…（示例原文摘录）"
            f.supplementaryText = ""
        }
        let education = SafetyEducationRecord(context: ctx)
        education.educationId = UUID().uuidString
        education.createdAt = Date()
        education.educationDate = Date()
        education.educationType = "日常安全教育"
        education.projectName = "示例工程项目"
        education.topic = "临边洞口与高处作业安全教育"
        education.instructorName = "张三"
        education.participants = "架子工班组"
        education.participantCount = 12
        education.generatedRecordText = "围绕临边洞口防护、高处作业安全带使用和作业前检查要求开展教育。"
        do {
            try ctx.save()
        } catch {
            let ns = error as NSError
            fatalError("Unresolved error \(ns), \(ns.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "SafetyMaster")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        if let desc = container.persistentStoreDescriptions.first {
            desc.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            desc.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// 统一封装后台 Core Data 任务，避免在主线程执行重写入。
    func performBackgroundTask<T>(
        _ work: @escaping (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            container.performBackgroundTask { context in
                context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                do {
                    let result = try work(context)
                    continuation.resume(returning: result)
                } catch {
                    context.rollback()
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
