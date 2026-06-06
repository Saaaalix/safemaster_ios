//
//  ReportModulePreviewView.swift
//  安全大师
//

import SwiftUI

struct ReportModulePreviewView: View {
    let module: ReportModule

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年MM月dd日"
        return formatter
    }()

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
                previewRow("项目名称", "示例项目")
                previewRow("检查单位", "安全生产检查组")
                previewRow("受检单位", "示例受检项目部")
                previewRow("检查时间", Self.dateFormatter.string(from: Date()))
            }
        case .narrative:
            Text("根据安全生产检查要求，检查组对项目现场安全生产、文明施工、临时用电等情况进行了检查，现将检查及整改情况报告如下。")
                .font(.subheadline)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case .rectificationList:
            rectificationTable
        case .photoComparison:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    photoPlaceholder("整改前照片")
                    photoPlaceholder("整改后照片")
                }
                Text("问题说明：现场临边防护不到位，已按要求完成整改并复查确认。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .signature:
            VStack(alignment: .leading, spacing: 8) {
                signatureLine("整改负责人")
                signatureLine("安全总监")
                signatureLine("项目负责人")
                signatureLine("日期")
            }
        case .notes:
            Text("备注：这里显示补充说明或复查意见。")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rectificationTable: some View {
        VStack(spacing: 0) {
            tableRow(["序号", "问题描述", "整改情况"], isHeader: true)
            tableRow(["1", "临边防护缺失", "已补设防护栏杆"])
            tableRow(["2", "材料堆放不整齐", "已完成分类码放"])
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
                    .frame(maxWidth: index == 0 ? 36 : .infinity, alignment: .leading)
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

    private func signatureLine(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text("\(title)：")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.7)
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(ReportTemplate.default.enabledModules) { module in
                ReportModulePreviewView(module: module)
            }
        }
        .padding()
    }
}
