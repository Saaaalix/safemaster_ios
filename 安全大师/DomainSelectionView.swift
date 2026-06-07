//
//  DomainSelectionView.swift
//  安全大师
//

import SwiftUI

struct DomainSelectionView: View {
    var onSelectBuilding: () -> Void

    private static let productivityAccent = Color(red: 0.95, green: 0.65, blue: 0.3)

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("选择领域")
                    .font(.title2.weight(.semibold))
                    .padding(.top, 32)

                Text("请选择您主要使用的安全业务场景")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))

                Spacer()

                Button(action: onSelectBuilding) {
                    HStack(spacing: 14) {
                        Image(systemName: "building.2.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.95))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("建筑施工安全")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("隐患排查与整改闭环")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.88))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(Self.productivityAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
                }
                .buttonStyle(.plain)

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .inlineNavigationTitleMode()
        }
    }
}

#Preview {
    DomainSelectionView(onSelectBuilding: {})
}
