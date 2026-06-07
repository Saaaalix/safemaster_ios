//
//  ReportTemplateSettings.swift
//  安全大师
//

import Foundation
import SwiftUI

enum ReportPhotoLayout: String, CaseIterable, Identifiable, Codable {
    case compact = "紧凑小图"
    case standard = "标准图文"
    case large = "大图优先"

    var id: String { rawValue }

    var wordMaxWidthInch: Double {
        switch self {
        case .compact: return 2.4
        case .standard: return 3.0
        case .large: return 4.2
        }
    }

    var wordMaxHeightInch: Double {
        switch self {
        case .compact: return 1.7
        case .standard: return 2.2
        case .large: return 3.0
        }
    }

    var pdfWidthFraction: CGFloat {
        switch self {
        case .compact: return 0.32
        case .standard: return 0.38
        case .large: return 0.62
        }
    }

    var pdfMaxHeight: CGFloat {
        switch self {
        case .compact: return 120
        case .standard: return 150
        case .large: return 220
        }
    }
}

struct ReportTemplateSettings: Codable, Equatable {
    static let storageKey = "safemasterReportTemplateSettings.v1"
    static let defaultInspectionTitle = "隐患整改通知单"
    static let defaultRectificationTitle = "隐患整改回复报告"

    var templateName = "默认模板"
    var inspectionTitle = Self.defaultInspectionTitle
    var rectificationTitle = Self.defaultRectificationTitle
    var inspectionUnit = ""
    var constructionUnit = ""
    var supervisionUnit = ""
    var includeRiskLevel = true
    var includeAccidentCategory = true
    var includeLegalBasis = true
    var includeDeadline = true
    var includeSignoff = true
    var includeLegalAppendix = true
    var photoLayout: ReportPhotoLayout = .standard
    var signoffLabels = ["检查人", "签收人", "复查人"]

    static var current: ReportTemplateSettings {
        load()
    }

    static func load() -> ReportTemplateSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(ReportTemplateSettings.self, from: data)
        else {
            return ReportTemplateSettings()
        }
        return value.normalized()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(normalized()) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    func title(for kind: ShareableReportKind) -> String {
        let raw = kind == .inspection ? inspectionTitle : rectificationTitle
        let fallback = kind == .inspection ? Self.defaultInspectionTitle : Self.defaultRectificationTitle
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    var displayTemplateName: String {
        let trimmed = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名模板" : trimmed
    }

    var enabledDetailFieldLabels: [String] {
        var labels = ["照片", "地点", "存在问题", "整改要求"]
        if includeRiskLevel { labels.append("风险等级") }
        if includeAccidentCategory { labels.append("事故类别") }
        if includeLegalBasis { labels.append("整改依据") }
        if includeDeadline { labels.append("整改期限") }
        if includeSignoff { labels.append("签字栏") }
        if includeLegalAppendix { labels.append("法规附录") }
        return labels
    }

    var exportSignature: String {
        [
            displayTemplateName,
            inspectionTitle,
            rectificationTitle,
            includeRiskLevel.description,
            includeAccidentCategory.description,
            includeLegalBasis.description,
            includeDeadline.description,
            includeSignoff.description,
            includeLegalAppendix.description,
            photoLayout.rawValue
        ].joined(separator: "|")
    }

    func normalized() -> ReportTemplateSettings {
        var copy = self
        copy.templateName = copy.templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.inspectionTitle = copy.inspectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.rectificationTitle = copy.rectificationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.inspectionUnit = copy.inspectionUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.constructionUnit = copy.constructionUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.supervisionUnit = copy.supervisionUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.signoffLabels = copy.signoffLabels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if copy.templateName.isEmpty { copy.templateName = "默认模板" }
        if copy.inspectionTitle.isEmpty { copy.inspectionTitle = Self.defaultInspectionTitle }
        if copy.rectificationTitle.isEmpty { copy.rectificationTitle = Self.defaultRectificationTitle }
        if copy.signoffLabels.isEmpty {
            copy.signoffLabels = ["检查人", "签收人", "复查人"]
        }
        return copy
    }
}

struct ReportTemplateSettingsView: View {
    @State private var settings = ReportTemplateSettings.load()
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section {
                TextField("模板名称", text: $settings.templateName)
                TextField("通知单标题", text: $settings.inspectionTitle)
                TextField("回复报告标题", text: $settings.rectificationTitle)
            } header: {
                Text("模板名称与标题")
            }

            Section {
                TextField("检查单位", text: $settings.inspectionUnit)
                TextField("施工单位", text: $settings.constructionUnit)
                TextField("监理单位", text: $settings.supervisionUnit)
            } header: {
                Text("封面字段")
            } footer: {
                Text("留空的单位不会出现在导出的报告中。")
            }

            Section("正文内容") {
                Toggle("显示风险等级", isOn: $settings.includeRiskLevel)
                Toggle("显示事故类别", isOn: $settings.includeAccidentCategory)
                Toggle("显示整改依据", isOn: $settings.includeLegalBasis)
                Toggle("显示整改期限", isOn: $settings.includeDeadline)
                Toggle("显示签字栏", isOn: $settings.includeSignoff)
                Toggle("显示法规依据附录", isOn: $settings.includeLegalAppendix)
            }

            Section("照片布局") {
                Picker("报告照片", selection: $settings.photoLayout) {
                    ForEach(ReportPhotoLayout.allCases) { layout in
                        Text(layout.rawValue).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                ForEach(settings.signoffLabels.indices, id: \.self) { index in
                    TextField("签字栏", text: $settings.signoffLabels[index])
                }
                .onDelete { offsets in
                    settings.signoffLabels.remove(atOffsets: offsets)
                }
                Button {
                    settings.signoffLabels.append("签字人")
                } label: {
                    Label("新增签字栏", systemImage: "plus.circle")
                }
            } header: {
                Text("签字栏")
            } footer: {
                Text("导出报告时会自动补上日期空格。")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(settings.displayTemplateName, systemImage: "doc.text.magnifyingglass")
                        .font(.headline)
                    Text(settings.enabledDetailFieldLabels.joined(separator: "、"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("恢复默认模板", role: .destructive) {
                    showResetConfirmation = true
                }
            } header: {
                Text("预览摘要")
            }
        }
        .navigationTitle("报告模板")
        .inlineNavigationTitleMode()
        .onChange(of: settings) { _, newValue in
            newValue.save()
        }
        .confirmationDialog("恢复默认模板？", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("恢复默认", role: .destructive) {
                ReportTemplateSettings.reset()
                settings = ReportTemplateSettings.load()
            }
            Button("取消", role: .cancel) {}
        }
    }
}

#Preview {
    NavigationStack {
        ReportTemplateSettingsView()
    }
}
