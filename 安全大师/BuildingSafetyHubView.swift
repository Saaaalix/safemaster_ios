//
//  BuildingSafetyHubView.swift
//  安全大师
//

import SwiftUI

struct BuildingSafetyHubView: View {
    @State private var path: [SafetyNavigationRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Spacer(minLength: 24)

                Button {
                    path.append(.hazardInspection)
                } label: {
                    Text("隐患识别")
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.accentColor.opacity(0.2))
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                Spacer()

                Button {
                    path.append(.profile)
                } label: {
                    Text("我的")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle("建筑施工安全")
            .inlineNavigationTitleMode()
            .navigationDestination(for: SafetyNavigationRoute.self) { route in
                switch route {
                case .hazardInspection:
                    HazardInspectionView(path: $path)
                case .profile:
                    UserProfileView()
                case .hazardResult(_, let payload):
                    InspectionResultView(payload: payload, onDone: dismissTopHazardResult)
                case .hazardRecords:
                    InspectionRecordsListView()
                case .hazardLibrary:
                    DocumentLibraryView()
                }
            }
        }
    }

    private func dismissTopHazardResult() {
        guard let last = path.last, case .hazardResult = last else { return }
        var t = Transaction()
        t.disablesAnimations = true
        _ = withTransaction(t) {
            path.removeLast()
        }
    }
}

#Preview {
    BuildingSafetyHubView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
