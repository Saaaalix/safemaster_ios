//
//  ReportModulePreviewView.swift
//  安全大师
//

import SwiftUI

struct ReportModulePreviewView: View {
    let module: ReportModule
    let previewData: ReportTemplatePreviewData
    let editableFields: ReportTemplateEditableFields

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(module.title)
                .font(.headline)
                .foregroundStyle(.primary)

            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch module.type {
        case .basicInfo:
            VStack(alignment: .leading, spacing: 6) {
                previewRow("报告标题", editableFields.displayValue(\.reportTitle))
                previewRow("项目名称", editableFields.displayValue(\.projectName))
                previewRow("检查单位", editableFields.displayValue(\.inspectionUnit))
                previewRow("受检单位", editableFields.displayValue(\.inspectedUnit))
                previewRow("检查时间", editableFields.displayValue(\.inspectionDate))
                previewRow("记录数量", "\(previewData.basicInfo.recordCount) 项")
            }
        case .narrative:
            Text(editableFields.displayValue(\.narrativeText))
                .font(.subheadline)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case .rectificationList:
            rectificationTable
        case .photoComparison:
            VStack(alignment: .leading, spacing: 8) {
                if previewData.photoComparisons.isEmpty {
                    photoPlaceholder("暂无照片")
                } else {
                    ForEach(previewData.photoComparisons.prefix(3)) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("隐患 \(item.index)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                photoView(data: item.beforePhotoData, placeholder: "整改前照片未添加")
                                photoView(data: item.afterPhotoData, placeholder: "整改后照片未添加")
                            }
                            previewRow("问题说明", item.issueDescription)
                            previewRow("整改说明", item.rectificationDescription)
                        }
                    }
                }
            }
        case .signature:
            VStack(alignment: .leading, spacing: 8) {
                signatureLine("整改负责人", editableFields.displayValue(\.rectificationResponsiblePerson))
                signatureLine("安全总监", editableFields.displayValue(\.safetyDirector))
                signatureLine("项目负责人", editableFields.displayValue(\.projectManager))
                signatureLine("复查人", editableFields.displayValue(\.reviewer))
                signatureLine("日期", editableFields.displayValue(\.signatureDate))
            }
        case .notes:
            VStack(alignment: .leading, spacing: 6) {
                previewRow("复查意见", editableFields.displayValue(\.reviewOpinion, fallback: "暂无备注"))
                previewRow("补充说明", editableFields.displayValue(\.additionalNotes, fallback: "暂无备注"))
            }
        }
    }

    private var rectificationTable: some View {
        VStack(spacing: 0) {
            tableRow(["序号", "隐患描述", "整改情况", "风险", "责任人"], isHeader: true)
            ForEach(previewData.rectificationItems.prefix(5)) { item in
                tableRow([
                    "\(item.index)",
                    item.issueDescription,
                    item.rectificationStatus,
                    item.riskLevel,
                    item.responsibleParty
                ])
            }
            if previewData.rectificationItems.count > 5 {
                Text("其余内容将在导出报告中完整展示")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(7)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    private func tableRow(_ values: [String], isHeader: Bool = false) -> some View {
        HStack(spacing: 0) {
            ForEach(values.indices, id: \.self) { index in
                Text(values[index])
                    .font(isHeader ? .caption.weight(.semibold) : .caption)
                    .foregroundStyle(isHeader ? .primary : .secondary)
                    .lineLimit(3)
                    .frame(maxWidth: index == 0 ? 34 : .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 7)
                    .background(isHeader ? Color(.tertiarySystemBackground) : Color.clear)
                if index < values.count - 1 {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 0.5)
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5)
        }
    }

    private func previewRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(title)：")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func photoPlaceholder(_ title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "photo")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 88)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(.separator), style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
        )
    }

    private func photoView(data: Data?, placeholder: String) -> some View {
        Group {
            if let image = Image.fromStoredData(data) {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 88)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                photoPlaceholder(placeholder)
            }
        }
    }

    private func signatureLine(_ title: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text("\(title)：")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(Color(.separator))
                .frame(width: 42, height: 0.7)
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(ReportTemplate.default.enabledModules) { module in
                ReportModulePreviewView(
                    module: module,
                    previewData: .sample,
                    editableFields: ReportTemplateEditableFields(previewData: .sample)
                )
            }
        }
        .padding()
    }
}
