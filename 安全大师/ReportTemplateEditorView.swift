//
//  ReportTemplateEditorView.swift
//  安全大师
//

import SwiftUI

struct ReportTemplateEditorView: View {
    let previewData: ReportTemplatePreviewData
    @State private var template = ReportTemplate.default
    @State private var editableFields: ReportTemplateEditableFields
    @State private var savedTemplates: [SavedReportTemplate]
    @State private var selectedTemplateID: SavedReportTemplate.ID
    @State private var templateName = ReportTemplate.default.name
    @State private var templateDescription = ""
    @State private var pdfShareItem: PDFShareItem?
    @State private var exportErrorMessage: String?
    @State private var templateStatusMessage: String?
    @State private var didLoadInitialTemplate = false

    init(previewData: ReportTemplatePreviewData = .sample) {
        let loadedTemplates = SavedReportTemplateStore.load()
        self.previewData = previewData
        _editableFields = State(initialValue: ReportTemplateEditableFields(previewData: previewData))
        _savedTemplates = State(initialValue: loadedTemplates)
        _selectedTemplateID = State(initialValue: loadedTemplates.first?.id ?? ReportTemplate.default.id)
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

                templateSelectionSection
                a4Preview
                editableFieldsSection
                moduleManagement
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("报告模板编辑")
        .inlineNavigationTitleMode()
        .onAppear(perform: loadInitialTemplate)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("分享 PDF") {
                    sharePDF()
                }
                .disabled(enabledModules.isEmpty)
            }
        }
        .alert("PDF 生成失败", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("好的", role: .cancel) { exportErrorMessage = nil }
        } message: {
            Text(exportErrorMessage ?? "")
        }
#if os(iOS)
        .sheet(item: $pdfShareItem) { item in
            ActivityShareView(items: [item.url])
        }
#endif
    }

    private var templateSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("模板管理")
                .font(.headline)

            TextField("模板名称", text: $templateName)
                .textFieldStyle(.roundedBorder)

            TextField("模板描述（可选）", text: $templateDescription, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)

            Picker("选择模板", selection: $selectedTemplateID) {
                ForEach(savedTemplates) { item in
                    Text(item.name).tag(item.id)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedTemplateID) { _, id in
                loadTemplate(id: id)
            }

            HStack(spacing: 10) {
                Button("新建模板") {
                    createTemplate()
                }
                .buttonStyle(.bordered)

                Button("保存模板") {
                    saveCurrentTemplate()
                }
                .buttonStyle(.borderedProminent)

                Button("删除模板", role: .destructive) {
                    deleteCurrentTemplate()
                }
                .buttonStyle(.bordered)
                .disabled(savedTemplates.count <= 1)
            }

            if let templateStatusMessage {
                Text(templateStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var a4Preview: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(editableFields.displayValue(\.reportTitle, fallback: template.name))
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
                        ReportModulePreviewView(
                            module: module,
                            previewData: previewData,
                            editableFields: editableFields
                        )
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

    private var editableFieldsSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                TextField("报告标题", text: $editableFields.reportTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("项目名称", text: $editableFields.projectName)
                    .textFieldStyle(.roundedBorder)
                TextField("检查单位", text: $editableFields.inspectionUnit)
                    .textFieldStyle(.roundedBorder)
                TextField("受检单位", text: $editableFields.inspectedUnit)
                    .textFieldStyle(.roundedBorder)
                TextField("检查时间", text: $editableFields.inspectionDate)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 6) {
                    Text("正文说明")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $editableFields.narrativeText)
                        .frame(minHeight: 96)
                        .padding(6)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                TextField("整改负责人", text: $editableFields.rectificationResponsiblePerson)
                    .textFieldStyle(.roundedBorder)
                TextField("安全总监", text: $editableFields.safetyDirector)
                    .textFieldStyle(.roundedBorder)
                TextField("项目负责人", text: $editableFields.projectManager)
                    .textFieldStyle(.roundedBorder)
                TextField("复查人", text: $editableFields.reviewer)
                    .textFieldStyle(.roundedBorder)
                TextField("日期", text: $editableFields.signatureDate)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 6) {
                    Text("复查意见")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $editableFields.reviewOpinion)
                        .frame(minHeight: 72)
                        .padding(6)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("补充说明")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $editableFields.additionalNotes)
                        .frame(minHeight: 72)
                        .padding(6)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.top, 8)
        } label: {
            Text("报告字段编辑")
                .font(.headline)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    private func loadInitialTemplate() {
        guard !didLoadInitialTemplate else { return }
        didLoadInitialTemplate = true
        guard let first = savedTemplates.first else { return }
        selectedTemplateID = first.id
        apply(savedTemplate: first)
    }

    private func loadTemplate(id: SavedReportTemplate.ID) {
        guard let saved = savedTemplates.first(where: { $0.id == id }) else { return }
        apply(savedTemplate: saved)
    }

    private func apply(savedTemplate: SavedReportTemplate) {
        template = savedTemplate.template
        template.name = savedTemplate.name
        editableFields = savedTemplate.editableFields ?? ReportTemplateEditableFields(previewData: previewData, reportTitle: savedTemplate.name)
        selectedTemplateID = savedTemplate.id
        templateName = savedTemplate.name
        templateDescription = savedTemplate.description ?? ""
        templateStatusMessage = "已加载：\(savedTemplate.name)"
    }

    private func createTemplate() {
        var newTemplate = template
        newTemplate.id = UUID()
        newTemplate.name = nextTemplateName()
        newTemplate.createdAt = Date()
        newTemplate.updatedAt = Date()
        let saved = SavedReportTemplate(
            id: newTemplate.id,
            name: newTemplate.name,
            description: templateDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : templateDescription,
            template: newTemplate,
            editableFields: editableFields
        )
        savedTemplates.insert(saved, at: 0)
        SavedReportTemplateStore.save(savedTemplates)
        apply(savedTemplate: saved)
        templateStatusMessage = "已新建模板"
    }

    private func saveCurrentTemplate() {
        let name = templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名模板" : templateName
        let description = templateDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        template.name = name
        template.updatedAt = Date()
        let saved = SavedReportTemplate(
            id: selectedTemplateID,
            name: name,
            description: description.isEmpty ? nil : description,
            template: template,
            editableFields: editableFields,
            updatedAt: Date()
        )
        if let index = savedTemplates.firstIndex(where: { $0.id == selectedTemplateID }) {
            savedTemplates[index] = saved
        } else {
            savedTemplates.insert(saved, at: 0)
        }
        SavedReportTemplateStore.save(savedTemplates)
        savedTemplates = SavedReportTemplateStore.load()
        selectedTemplateID = saved.id
        templateStatusMessage = "模板已保存"
    }

    private func deleteCurrentTemplate() {
        guard savedTemplates.count > 1 else { return }
        savedTemplates.removeAll { $0.id == selectedTemplateID }
        SavedReportTemplateStore.save(savedTemplates)
        savedTemplates = SavedReportTemplateStore.load()
        if let first = savedTemplates.first {
            apply(savedTemplate: first)
        }
        templateStatusMessage = "模板已删除"
    }

    private func nextTemplateName() -> String {
        let base = "新模板"
        var index = savedTemplates.count + 1
        var name = "\(base) \(index)"
        let existingNames = Set(savedTemplates.map(\.name))
        while existingNames.contains(name) {
            index += 1
            name = "\(base) \(index)"
        }
        return name
    }

    private func sharePDF() {
        do {
            let url = try ReportTemplatePDFExporter.buildTemporaryFileURL(
                template: template,
                previewData: previewData,
                editableFields: editableFields
            )
            pdfShareItem = PDFShareItem(url: url)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }
}

private struct PDFShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

#Preview {
    NavigationStack {
        ReportTemplateEditorView(previewData: .sample)
    }
}
