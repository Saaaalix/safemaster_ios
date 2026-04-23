//
//  AppRootView.swift
//  安全大师
//

import SwiftUI

struct AppRootView: View {
    @AppStorage("selectedSafetyDomain") private var selectedDomain: String = ""

    var body: some View {
        Group {
            if selectedDomain.isEmpty {
                DomainSelectionView {
                    selectedDomain = "building"
                }
            } else {
                BuildingSafetyHubView()
            }
        }
    }
}

#Preview {
    AppRootView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
