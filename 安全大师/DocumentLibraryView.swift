//
//  DocumentLibraryView.swift
//  安全大师
//

import SwiftUI

struct DocumentLibraryView: View {
    private let localFolderNote = "/Users/mu/Desktop/仙/建筑工程施工安全技术规范27份（Word版）"

    private let placeholderTitles: [String] = [
        "建筑施工高处作业安全技术规范 JGJ 80",
        "建筑施工安全检查标准 JGJ 59",
        "建筑施工扣件式钢管脚手架安全技术规范",
        "（其余 Word 文档由服务端或后续版本接入检索）"
    ]

    var body: some View {
        List {
            Section {
                Text("法规与规范原文用于 AI 整改依据引用。iOS 应用无法直接读取您 Mac 上的文件夹，正式产品中通常将文档在服务端解析、切片并建立检索库（RAG），或由配套桌面工具同步。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("您本地的资料位置（开发参考）") {
                Text(localFolderNote)
                    .font(.caption)
                    .textSelection(.enabled)
            }

            Section("资料库条目（演示）") {
                ForEach(placeholderTitles, id: \.self) { t in
                    Text(t)
                }
            }
        }
        .navigationTitle("资料库")
        .inlineNavigationTitleMode()
    }
}

#Preview {
    NavigationStack {
        DocumentLibraryView()
    }
}
