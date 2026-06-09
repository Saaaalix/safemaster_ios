//
//  DocumentCenterView.swift
//  安全大师
//

import SwiftUI

struct DocumentCenterView: View {
    @Binding var path: [SafetyNavigationRoute]

    private static let productivityAccent = Color(red: 0.95, green: 0.65, blue: 0.3)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                documentCenterCard(
                    title: "导入箱",
                    subtitle: "先导入文件，再决定是否识别建档",
                    systemImage: "tray.full.fill"
                ) {
                    path.append(.importedNoticeInbox)
                }

                documentCenterCard(
                    title: "报告模板",
                    subtitle: "设置标题、字段、照片布局与签字栏",
                    systemImage: "doc.text.magnifyingglass"
                ) {
                    path.append(.reportTemplate)
                }

                documentCenterCard(
                    title: "报告存档",
                    subtitle: "查看、预览和分享已生成报告",
                    systemImage: "archivebox.fill"
                ) {
                    path.append(.reportArchive)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("文书中心")
        .inlineNavigationTitleMode()
    }

    private func documentCenterCard(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Self.productivityAccent)
                    .frame(width: 52, height: 52)
                    .background(Self.productivityAccent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(18)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        DocumentCenterView(path: .constant([]))
    }
}
