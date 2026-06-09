//
//  ReportTemplateEditorView.swift
//  安全大师
//

import SwiftUI
import UniformTypeIdentifiers

struct ReportTemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let previewData: ReportTemplatePreviewData
    @State private var template = ReportTemplate.default
    @State private var editableFields: ReportTemplateEditableFields
    @State private var savedTemplates: [SavedReportTemplate]
    @State private var selectedTemplateID: SavedReportTemplate.ID
    @State private var selectedDocumentKind: ReportDocumentKind
    @State private var templateName = ReportTemplate.default.name
    @State private var templateDescription = ""
    @State private var pdfShareItem: PDFShareItem?
    @State private var exportErrorMessage: String?
    @State private var validationSheet: ReportValidationSheetState?
    @State private var exportConfirmation: ReportExportConfirmation?
    @State private var templateStatusMessage: String?
    @State private var didLoadInitialTemplate = false
    @State private var importedWordTemplates: [ImportedWordTemplate]
    @State private var showWordTemplateImporter = false
    @State private var wordTemplateReview: ImportedWordTemplate?
    @State private var wordTemplateMessage: String?

    init(previewData: ReportTemplatePreviewData = .sample) {
        let loadedTemplates = SavedReportTemplateStore.load()
        let firstTemplate = loadedTemplates.first
        self.previewData = previewData
        _template = State(initialValue: firstTemplate?.template ?? ReportTemplate.default)
        _editableFields = State(initialValue: firstTemplate?.editableFields ?? ReportTemplateEditableFields(previewData: previewData, reportTitle: firstTemplate?.documentKind.defaultReportTitle ?? ReportDocumentKind.rectificationReply.defaultReportTitle))
        _savedTemplates = State(initialValue: loadedTemplates)
        _selectedTemplateID = State(initialValue: firstTemplate?.id ?? ReportTemplate.default.id)
        _selectedDocumentKind = State(initialValue: firstTemplate?.documentKind ?? .rectificationReply)
        _templateName = State(initialValue: firstTemplate?.name ?? ReportDocumentKind.rectificationReply.displayName)
        _templateDescription = State(initialValue: firstTemplate?.description ?? "")
        _importedWordTemplates = State(initialValue: ImportedWordTemplateStore.load())
    }

    private var orderedModules: [ReportModule] {
        template.modules.sorted { $0.sortIndex < $1.sortIndex }
    }

    private var enabledModules: [ReportModule] {
        orderedModules.filter(\.isEnabled)
    }

    private var templatesForSelectedKind: [SavedReportTemplate] {
        savedTemplates.filter { $0.documentKind == selectedDocumentKind }
    }

    private var currentReportTitle: String {
        let title = editableFields.reportTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title == "默认模板" {
            return selectedDocumentKind.defaultReportTitle
        }
        return title
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("选择文书类型和模板，编辑字段后可检查并导出 PDF。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                templateSelectionSection
                importedWordTemplateSection
                a4Preview
                editableFieldsSection
                moduleManagement
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("文书生成")
        .inlineNavigationTitleMode()
        .onAppear(perform: loadInitialTemplate)
        .fileImporter(
            isPresented: $showWordTemplateImporter,
            allowedContentTypes: wordTemplateContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleWordTemplateImport(result)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") {
                    dismiss()
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("检查报告") {
                    checkReport()
                }

                Button("分享 PDF") {
                    requestPDFShare()
                }
                .disabled(enabledModules.isEmpty)
            }
        }
        .alert(exportConfirmation?.title ?? "", isPresented: Binding(
            get: { exportConfirmation != nil },
            set: { if !$0 { exportConfirmation = nil } }
        )) {
            Button("返回修改", role: .cancel) {
                if let issues = exportConfirmation?.issues {
                    validationSheet = ReportValidationSheetState(issues: issues)
                }
                exportConfirmation = nil
            }
            Button("仍然导出") {
                exportConfirmation = nil
                sharePDF()
            }
        } message: {
            Text(exportConfirmation?.message ?? "")
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
        .sheet(item: $validationSheet) { state in
            ReportValidationResultView(issues: state.issues)
        }
        .sheet(item: $pdfShareItem) { item in
            ActivityShareView(items: [item.url])
        }
        .sheet(item: $wordTemplateReview) { template in
            WordTemplateBindingReviewView(template: template) { updated in
                ImportedWordTemplateStore.upsert(updated)
                importedWordTemplates = ImportedWordTemplateStore.load()
                wordTemplateMessage = "已保存“\(updated.name)”的字段绑定。"
            }
        }
#endif
    }

    private var wordTemplateContentTypes: [UTType] {
        [UTType(filenameExtension: "docx")].compactMap { $0 }
    }

    private var templateSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("模板管理")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("文书类型")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("文书类型", selection: $selectedDocumentKind) {
                    ForEach(ReportDocumentKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedDocumentKind) { _, kind in
                    loadTemplateForDocumentKind(kind)
                }
            }

            Text(selectedDocumentKind.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("模板")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("模板", selection: $selectedTemplateID) {
                    ForEach(templatesForSelectedKind) { item in
                        Text(item.name).tag(item.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedTemplateID) { _, id in
                    loadTemplate(id: id)
                }

                TextField("模板名称", text: $templateName)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("模板描述（可选）", text: $templateDescription, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
            if !templateDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(templateDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

            HStack(spacing: 10) {
                Button("检查报告") {
                    checkReport()
                }
                .buttonStyle(.bordered)

                Button("分享 PDF") {
                    requestPDFShare()
                }
                .buttonStyle(.borderedProminent)
                .disabled(enabledModules.isEmpty)
            }

            if let templateStatusMessage {
                Text(templateStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("当前文书：\(selectedDocumentKind.displayName)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var importedWordTemplateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("单位 Word 模板")
                        .font(.headline)
                    Text("导入单位自己的 .docx 空白表，确认字段绑定后生成 Word 文书。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showWordTemplateImporter = true
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }

            if importedWordTemplates.isEmpty {
                Text("尚未导入单位模板。没有模板时，仍可继续使用下方系统模板。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(importedWordTemplates) { template in
                        importedWordTemplateRow(template)
                    }
                }
            }

            if let wordTemplateMessage {
                Text(wordTemplateMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func importedWordTemplateRow(_ template: ImportedWordTemplate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(template.originalFileName) · 已识别 \(template.placeholders.count) 个位置 · 已绑定 \(template.activeBindingCount) 个")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button("确认绑定") {
                    wordTemplateReview = template
                }
                .buttonStyle(.bordered)

                Button("生成测试文书") {
                    generateWordTemplateDocument(template)
                }
                .buttonStyle(.borderedProminent)
                .disabled(template.activeBindingCount == 0)

                Button("删除", role: .destructive) {
                    ImportedWordTemplateStore.delete(template)
                    importedWordTemplates = ImportedWordTemplateStore.load()
                    wordTemplateMessage = "已删除单位模板。"
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var a4Preview: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(currentReportTitle)
                    .font(.title3.weight(.bold))
                Text("模板：\(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedDocumentKind.displayName : templateName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("A4 文书预览")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Divider()

            if orderedModules.isEmpty {
                ContentUnavailableView("暂无模块", systemImage: "doc.text")
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(orderedModules.enumerated()), id: \.element.id) { index, module in
                        ReportModulePreviewView(
                            module: module,
                            previewData: previewData,
                            editableFields: editableFields,
                            documentKind: selectedDocumentKind,
                            isFirst: index == 0,
                            isLast: index == orderedModules.count - 1,
                            onToggleEnabled: { isEnabled in
                                setModuleEnabled(module.id, isEnabled: isEnabled)
                            },
                            onMoveUp: {
                                moveModule(at: index, by: -1)
                            },
                            onMoveDown: {
                                moveModule(at: index, by: 1)
                            }
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
                .formalTemplateInput()

                switch selectedDocumentKind {
                case .hazardNotice:
                    hazardNoticeFields
                case .rectificationReply:
                    rectificationReplyFields
                case .safetyEducationRecord:
                    safetyEducationFields
                case .monthlyReport:
                    monthlyReportFields
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

    private var hazardNoticeFields: some View {
        Group {
            TextField("通知编号", text: $editableFields.noticeNumber)
                .textFieldStyle(.roundedBorder)
                .formalTemplateInput()
            TextField("检查单位", text: $editableFields.inspectionUnit)
                .textFieldStyle(.roundedBorder)
                .formalTemplateInput()
            TextField("受检单位", text: $editableFields.inspectedUnit)
                .textFieldStyle(.roundedBorder)
                .formalTemplateInput()
            TextField("检查时间", text: $editableFields.inspectionDate)
                .textFieldStyle(.roundedBorder)
                .formalTemplateInput()
            TextField("整改期限", text: $editableFields.rectificationDeadline)
                .textFieldStyle(.roundedBorder)
                .formalTemplateInput()
            TextField("检查人", text: $editableFields.inspector)
                .textFieldStyle(.roundedBorder)
                .formalTemplateInput()
            TextField("接收人", text: $editableFields.receiver)
                .textFieldStyle(.roundedBorder)
                .formalTemplateInput()
            editableTextArea("正文说明", text: $editableFields.narrativeText, minHeight: 96)
            editableTextArea("补充说明", text: $editableFields.additionalNotes, minHeight: 72)
        }
    }

    private var rectificationReplyFields: some View {
        Group {
            TextField("项目名称", text: $editableFields.projectName)
                .textFieldStyle(.roundedBorder)
                .formalTemplateInput()
            TextField("受检单位", text: $editableFields.inspectedUnit)
                .textFieldStyle(.roundedBorder)
                .formalTemplateInput()
            TextField("检查时间", text: $editableFields.inspectionDate)
                .textFieldStyle(.roundedBorder)
                .formalTemplateInput()
            editableTextArea("正文说明", text: $editableFields.narrativeText, minHeight: 96)
            TextField("整改负责人", text: $editableFields.rectificationResponsiblePerson)
                .textFieldStyle(.roundedBorder)
                .formalTemplateInput()
            TextField("安全总监", text: $editableFields.safetyDirector)
                .textFieldStyle(.roundedBorder)
                .formalTemplateInput()
            TextField("项目负责人", text: $editableFields.projectManager)
                .textFieldStyle(.roundedBorder)
                .formalTemplateInput()
            TextField("复查人", text: $editableFields.reviewer)
                .textFieldStyle(.roundedBorder)
                .formalTemplateInput()
            TextField("日期", text: $editableFields.signatureDate)
                .textFieldStyle(.roundedBorder)
                .formalTemplateInput()
            editableTextArea("复查意见", text: $editableFields.reviewOpinion, minHeight: 72)
            editableTextArea("补充说明", text: $editableFields.additionalNotes, minHeight: 72)
        }
    }

    private var safetyEducationFields: some View {
        Group {
            TextField("教育主题", text: $editableFields.educationTopic)
                .textFieldStyle(.roundedBorder)
            TextField("教育时间", text: $editableFields.educationDate)
                .textFieldStyle(.roundedBorder)
            TextField("教育地点", text: $editableFields.educationLocation)
                .textFieldStyle(.roundedBorder)
            TextField("主讲人", text: $editableFields.lecturer)
                .textFieldStyle(.roundedBorder)
            TextField("参加人员", text: $editableFields.participants, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
            editableTextArea("教育内容", text: $editableFields.educationContent, minHeight: 96)
            editableTextArea("正文说明", text: $editableFields.narrativeText, minHeight: 72)
            TextField("日期", text: $editableFields.signatureDate)
                .textFieldStyle(.roundedBorder)
            editableTextArea("补充说明", text: $editableFields.additionalNotes, minHeight: 72)
        }
    }

    private var monthlyReportFields: some View {
        Group {
            TextField("月份", text: $editableFields.reportMonth)
                .textFieldStyle(.roundedBorder)
            TextField("本月检查次数", text: $editableFields.monthlyInspectionCount)
                .textFieldStyle(.roundedBorder)
            TextField("本月隐患数量", text: $editableFields.monthlyHazardCount)
                .textFieldStyle(.roundedBorder)
            TextField("已整改数量", text: $editableFields.monthlyRectifiedCount)
                .textFieldStyle(.roundedBorder)
            TextField("未整改数量", text: $editableFields.monthlyUnrectifiedCount)
                .textFieldStyle(.roundedBorder)
            TextField("教育培训次数", text: $editableFields.monthlyEducationCount)
                .textFieldStyle(.roundedBorder)
            editableTextArea("正文说明", text: $editableFields.narrativeText, minHeight: 96)
            editableTextArea("下月计划", text: $editableFields.nextMonthPlan, minHeight: 72)
            editableTextArea("补充说明", text: $editableFields.additionalNotes, minHeight: 72)
        }
    }

    private func editableTextArea(_ title: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .frame(minHeight: minHeight)
                .padding(6)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var moduleManagement: some View {
        DisclosureGroup {
            VStack(spacing: 10) {
                ForEach(Array(orderedModules.enumerated()), id: \.element.id) { index, module in
                    moduleManagementRow(module: module, index: index)
                }
            }
            .padding(.top, 8)
        } label: {
            Text("模块管理")
                .font(.headline)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    private func setModuleEnabled(_ moduleID: ReportModule.ID, isEnabled: Bool) {
        guard let index = template.modules.firstIndex(where: { $0.id == moduleID }) else { return }
        template.modules[index].isEnabled = isEnabled
        template.updatedAt = Date()
    }

    private func loadInitialTemplate() {
        guard !didLoadInitialTemplate else { return }
        didLoadInitialTemplate = true
        if savedTemplates.isEmpty {
            let defaultTemplate = ReportTemplatePresets.defaultTemplate(for: selectedDocumentKind)
            savedTemplates = [defaultTemplate]
            SavedReportTemplateStore.save(savedTemplates)
        }
        guard let first = savedTemplates.first else { return }
        selectedTemplateID = first.id
        apply(savedTemplate: first)
    }

    private func loadTemplate(id: SavedReportTemplate.ID) {
        guard let saved = savedTemplates.first(where: { $0.id == id }) else { return }
        apply(savedTemplate: saved)
    }

    private func loadTemplateForDocumentKind(_ kind: ReportDocumentKind) {
        if let first = savedTemplates.first(where: { $0.documentKind == kind }) {
            selectedTemplateID = first.id
            apply(savedTemplate: first)
            return
        }

        let saved = ReportTemplatePresets.defaultTemplate(for: kind)
        savedTemplates.insert(saved, at: 0)
        SavedReportTemplateStore.save(savedTemplates)
        selectedTemplateID = saved.id
        apply(savedTemplate: saved)
        templateStatusMessage = "已创建\(kind.displayName)默认模板"
    }

    private func apply(savedTemplate: SavedReportTemplate) {
        template = savedTemplate.template
        template.name = savedTemplate.name
        editableFields = resolvedEditableFields(for: savedTemplate)
        selectedDocumentKind = savedTemplate.documentKind
        selectedTemplateID = savedTemplate.id
        templateName = savedTemplate.name
        templateDescription = savedTemplate.description ?? ""
        templateStatusMessage = "已加载：\(savedTemplate.name) · \(savedTemplate.documentKind.displayName)"
    }

    private func resolvedEditableFields(for savedTemplate: SavedReportTemplate) -> ReportTemplateEditableFields {
        var fields = savedTemplate.editableFields ?? ReportTemplateEditableFields(previewData: previewData, reportTitle: savedTemplate.name)
        let defaults = ReportTemplateEditableFields(previewData: previewData, reportTitle: fields.reportTitle)
        if fields.reportTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || fields.reportTitle == "默认模板" {
            fields.reportTitle = savedTemplate.documentKind.defaultReportTitle
        }
        if fields.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || fields.projectName == "未填写" {
            fields.projectName = defaults.projectName
        }
        if fields.inspectionUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || fields.inspectionUnit == "未填写" {
            fields.inspectionUnit = defaults.inspectionUnit
        }
        if fields.inspectedUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || fields.inspectedUnit == "未填写" {
            fields.inspectedUnit = defaults.inspectedUnit
        }
        if fields.inspectionDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || fields.inspectionDate == "未填写" {
            fields.inspectionDate = defaults.inspectionDate
        }
        if fields.signatureDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || fields.signatureDate == "未填写" {
            fields.signatureDate = defaults.signatureDate
        }
        return fields
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
            documentKind: selectedDocumentKind,
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
            documentKind: selectedDocumentKind,
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
        if let first = savedTemplates.first(where: { $0.documentKind == selectedDocumentKind }) ?? savedTemplates.first {
            apply(savedTemplate: first)
        }
        templateStatusMessage = "模板已删除"
    }

    private func nextTemplateName() -> String {
        let base = "\(selectedDocumentKind.displayName)模板"
        var index = templatesForSelectedKind.count + 1
        var name = "\(base) \(index)"
        let existingNames = Set(savedTemplates.map(\.name))
        while existingNames.contains(name) {
            index += 1
            name = "\(base) \(index)"
        }
        return name
    }

    private func validateCurrentReport() -> [ReportTemplateValidationIssue] {
        ReportTemplateValidator.validate(
            template: template,
            previewData: previewData,
            editableFields: editableFields,
            documentKind: selectedDocumentKind
        )
    }

    private func checkReport() {
        validationSheet = ReportValidationSheetState(issues: validateCurrentReport())
    }

    private func requestPDFShare() {
        let issues = validateCurrentReport()
        guard !issues.isEmpty else {
            sharePDF()
            return
        }
        exportConfirmation = ReportExportConfirmation(issues: issues)
    }

    private func sharePDF() {
        do {
            let url = try ReportTemplatePDFExporter.buildTemporaryFileURL(
                template: template,
                previewData: previewData,
                editableFields: editableFields,
                documentKind: selectedDocumentKind
            )
            pdfShareItem = PDFShareItem(url: url)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func handleWordTemplateImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let template = try ImportedWordTemplateStore.importTemplate(from: url)
                importedWordTemplates = ImportedWordTemplateStore.load()
                wordTemplateReview = template
                wordTemplateMessage = "已导入“\(template.originalFileName)”，请确认字段绑定。"
            } catch {
                wordTemplateMessage = error.localizedDescription
            }
        case .failure(let error):
            wordTemplateMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    private func generateWordTemplateDocument(_ template: ImportedWordTemplate) {
        do {
            let url = try WordTemplateFiller.buildDocument(
                template: template,
                editableFields: editableFields,
                previewData: previewData,
                outputKind: selectedDocumentKind == .rectificationReply ? .rectification : .inspection
            )
            pdfShareItem = PDFShareItem(url: url)
            wordTemplateMessage = "已按单位模板生成 Word 文书。"
        } catch {
            wordTemplateMessage = error.localizedDescription
        }
    }
}

private struct PDFShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ReportValidationSheetState: Identifiable {
    let id = UUID()
    var issues: [ReportTemplateValidationIssue]
}

private struct ReportExportConfirmation: Identifiable {
    let id = UUID()
    var issues: [ReportTemplateValidationIssue]

    var hasErrors: Bool {
        issues.contains { $0.severity == .error }
    }

    var title: String {
        hasErrors ? "报告存在关键缺失项" : "报告存在建议补充项"
    }

    var message: String {
        if hasErrors {
            return "报告存在关键缺失项，建议补充后再导出。你也可以选择仍然导出。"
        }
        return "报告存在建议补充项，是否继续导出？"
    }
}

private struct ReportValidationResultView: View {
    @Environment(\.dismiss) private var dismiss
    let issues: [ReportTemplateValidationIssue]

    private var errorIssues: [ReportTemplateValidationIssue] {
        issues.filter { $0.severity == .error }
    }

    private var warningIssues: [ReportTemplateValidationIssue] {
        issues.filter { $0.severity == .warning }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if issues.isEmpty {
                        ContentUnavailableView(
                            "报告检查通过",
                            systemImage: "checkmark.seal",
                            description: Text("报告检查通过，可以导出。")
                        )
                        .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        validationGroup(
                            title: ReportTemplateValidationSeverity.error.title,
                            issues: errorIssues,
                            tint: .red,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        validationGroup(
                            title: ReportTemplateValidationSeverity.warning.title,
                            issues: warningIssues,
                            tint: .orange,
                            systemImage: "info.circle.fill"
                        )
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("报告检查结果")
            .inlineNavigationTitleMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func validationGroup(
        title: String,
        issues: [ReportTemplateValidationIssue],
        tint: Color,
        systemImage: String
    ) -> some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                Text(issues.first?.severity.explanation ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(issues) { issue in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(issue.moduleTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text(issue.severity.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(tint)
                        }
                        Text(issue.title)
                            .font(.subheadline.weight(.semibold))
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}

private struct FormalTemplateInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
#if os(iOS)
            .textInputAutocapitalization(.never)
#endif
            .autocorrectionDisabled(true)
    }
}

private extension View {
    func formalTemplateInput() -> some View {
        modifier(FormalTemplateInputModifier())
    }
}

#Preview {
    NavigationStack {
        ReportTemplateEditorView(previewData: .sample)
    }
}
