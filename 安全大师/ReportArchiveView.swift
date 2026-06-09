//
//  ReportArchiveView.swift
//  安全大师
//

#if os(iOS)
import QuickLook
import SwiftUI

struct ReportArchiveView: View {
    @State private var reports: [ArchivedReport] = []
    @State private var previewReport: ArchivedReport?
    @State private var shareReport: ArchivedReport?

    var body: some View {
        List {
            if reports.isEmpty {
                ContentUnavailableView(
                    "暂无存档报告",
                    systemImage: "archivebox",
                    description: Text("生成报告后可在预览页点「存档报告」，以后就能在这里查看和分享。")
                )
                .listRowBackground(Color.clear)
            } else {
                Section("已存档报告") {
                    ForEach(reports) { report in
                        Button {
                            previewReport = report
                        } label: {
                            ArchivedReportRow(report: report)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                ReportArchiveStore.delete(report)
                                reload()
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                shareReport = report
                            } label: {
                                Label("分享", systemImage: "square.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("报告存档")
        .inlineNavigationTitleMode()
        .task {
            reload()
        }
        .refreshable {
            reload()
        }
        .sheet(item: $shareReport) { report in
            ActivityShareView(items: [ReportArchiveStore.fileURL(for: report)])
        }
        .fullScreenCover(item: $previewReport) { report in
            NavigationStack {
                QuickLookPreview(url: ReportArchiveStore.fileURL(for: report))
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("文档预览")
                    .inlineNavigationTitleMode()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("完成") { previewReport = nil }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                shareReport = report
                            } label: {
                                Label("分享", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
            }
        }
    }

    private func reload() {
        reports = ReportArchiveStore.allReports()
    }
}

private struct ArchivedReportRow: View {
    let report: ArchivedReport

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(report.fileName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("\(report.kindTitle) · \(report.projectName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(report.recordCount) 条隐患 · \(Self.dateFormatter.string(from: report.archivedAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch report.fileExtension {
        case "pdf":
            return "doc.richtext"
        case "docx":
            return "doc.text"
        default:
            return "doc"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

#Preview {
    NavigationStack {
        ReportArchiveView()
    }
}
#endif
