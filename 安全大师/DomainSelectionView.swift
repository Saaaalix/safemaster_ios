//
//  DomainSelectionView.swift
//  安全大师
//

import SwiftUI

struct DomainSelectionView: View {
    var onSelectBuilding: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("选择领域")
                    .font(.title2.weight(.semibold))
                    .padding(.top, 32)

                Spacer()

                Button(action: onSelectBuilding) {
                    Text("建筑施工安全")
                        .font(.title3.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.accentColor.opacity(0.15)))
                }
                .buttonStyle(.plain)

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 24)
            .inlineNavigationTitleMode()
        }
    }
}

#Preview {
    DomainSelectionView(onSelectBuilding: {})
}
