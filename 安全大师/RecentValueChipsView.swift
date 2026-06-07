//
//  RecentValueChipsView.swift
//  安全大师
//

import SwiftUI

/// 报告封面 / 整改责任人等字段的「最近使用」快捷填充行。
typealias RecentFieldChipsRow = RecentValueChipsView

struct RecentValueChipsView: View {
    let kind: RecentFieldKind
    @Binding var text: String
    var showTitle: Bool = true

    private static let productivityAccent = Color(red: 0.95, green: 0.65, blue: 0.3)

    private var recentValues: [String] {
        RecentFieldValuesStore.recent(for: kind)
    }

    var body: some View {
        if !recentValues.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if showTitle {
                    Text("最近使用")
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recentValues, id: \.self) { value in
                            Button {
                                text = value
                            } label: {
                                Text(value)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Self.productivityAccent.opacity(0.14))
                                    .foregroundStyle(.primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
