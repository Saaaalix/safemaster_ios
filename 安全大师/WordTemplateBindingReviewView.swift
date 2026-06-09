//
//  WordTemplateBindingReviewView.swift
//  安全大师
//

import SwiftUI

struct WordTemplateBindingReviewView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var template: ImportedWordTemplate
    var onSave: (ImportedWordTemplate) -> Void

    init(template: ImportedWordTemplate, onSave: @escaping (ImportedWordTemplate) -> Void) {
        _template = State(initialValue: template)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("模板名称", text: $template.name)
                    LabeledContent("原文件", value: template.originalFileName)
                    LabeledContent("识别位置", value: "\(template.placeholders.count) 个")
                    LabeledContent("已绑定", value: "\(template.activeBindingCount) 个")
                } header: {
                    Text("模板信息")
                } footer: {
                    Text("第一阶段只识别常见空白：下划线、括号、冒号后空白和表格空单元格。保存前请人工确认。")
                }

                if template.placeholders.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "未识别到可填写位置",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("可以换一个包含下划线、括号或空表格单元格的 .docx 模板。")
                        )
                    }
                } else {
                    Section("字段绑定") {
                        ForEach($template.placeholders) { $placeholder in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(placeholder.context)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(3)
                                if !placeholder.style.summary.isEmpty {
                                    Text("格式：\(placeholder.style.summary)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                HStack {
                                    Text("建议：\(placeholder.suggestedKind.displayName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Picker("绑定字段", selection: $placeholder.boundKind) {
                                        ForEach(WordTemplateFieldKind.allCases) { kind in
                                            Text(kind.displayName).tag(kind)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("模板识别确认")
            .inlineNavigationTitleMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        template.updatedAt = Date()
                        onSave(template)
                        dismiss()
                    }
                }
            }
        }
    }
}
