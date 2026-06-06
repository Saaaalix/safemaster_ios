//
//  ReportTemplateEditorView.swift
//  安全大师
//

import SwiftUI

struct ReportTemplateEditorView: View {
    let previewData: ReportTemplatePreviewData
    @State private var template = ReportTemplate.default

    init(previewData: ReportTemplatePreviewData = .sample) {
        self.previewData = previewData
    }

    private var orderedModules: [ReportModule] {
        template.modules.sorted { $0.sortIndex < $1.sortIndex }
    }

    private var enabledModules: [ReportModule] {
        orderedModules.filter(\.isEnabled)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("选择报告中需要展示的模块，并调整顺序")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                a4Preview
                moduleManagement
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("报告模板编辑")
        .inlineNavigationTitleMode()
    }

    private var a4Preview: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.title3.weight(.bold))
                Text("A4 报告预览")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Divider()

            if enabledModules.isEmpty {
                ContentUnavailableView("暂无显示模块", systemImage: "doc.text")
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                VStack(spacing: 12) {
                    ForEach(enabledModules) { module in
                        ReportModulePreviewView(module: module, previewData: previewData)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .aspectRatio(1 / 1.414, contentMode: .fit)
        .frame(minHeight: 520, alignment: .top)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 4)
    }

    private var moduleManagement: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("模块管理")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(Array(orderedModules.enumerated()), id: \.element.id) { index, module in
                    moduleManagementRow(module: module, index: index)
                }
            }
        }
    }

    private func moduleManagementRow(module: ReportModule, index: Int) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: binding(for: module.id, keyPath: \.isEnabled)) {
                Text(module.title)
                    .font(.subheadline.weight(.semibold))
            }
            .toggleStyle(.switch)

            Spacer(minLength: 4)

            Button {
                moveModule(at: index, by: -1)
            } label: {
                Image(systemName: "arrow.up")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .disabled(index == 0)
            .accessibilityLabel("上移\(module.title)")

            Button {
                moveModule(at: index, by: 1)
            } label: {
                Image(systemName: "arrow.down")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .disabled(index == orderedModules.count - 1)
            .accessibilityLabel("下移\(module.title)")
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func binding<Value>(for moduleID: ReportModule.ID, keyPath: WritableKeyPath<ReportModule, Value>) -> Binding<Value> {
        Binding {
            guard let index = template.modules.firstIndex(where: { $0.id == moduleID }) else {
                return ReportTemplate.defaultModules[0][keyPath: keyPath]
            }
            return template.modules[index][keyPath: keyPath]
        } set: { newValue in
            guard let index = template.modules.firstIndex(where: { $0.id == moduleID }) else { return }
            template.modules[index][keyPath: keyPath] = newValue
        }
    }

    private func moveModule(at index: Int, by offset: Int) {
        var modules = orderedModules
        let destination = index + offset
        guard modules.indices.contains(index), modules.indices.contains(destination) else { return }

        modules.swapAt(index, destination)
        for moduleIndex in modules.indices {
            modules[moduleIndex].sortIndex = moduleIndex
        }
        template.modules = modules
        template.updatedAt = Date()
    }
}

#Preview {
    NavigationStack {
        ReportTemplateEditorView(previewData: .sample)
    }
}
