//
//  ____App.swift
//  安全大师
//

import SwiftUI
import StoreKit

@MainActor
final class StoreKitTransactionObserver: ObservableObject {
    private var updatesTask: Task<Void, Never>?

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task(priority: .background) { [weak self] in
            guard self != nil else { return }
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    NotificationCenter.default.post(name: .safemasterAccessTokenDidChange, object: nil)
                    await transaction.finish()
                case .unverified:
                    // 不吞掉错误；这里只保证持续监听，具体错误由购买流程展示给用户。
                    continue
                }
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }
}

@main
struct SafetyMasterApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var transactionObserver = StoreKitTransactionObserver()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .task {
                    transactionObserver.start()
                }
        }
    }
}
