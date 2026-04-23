//
//  InspectionRecordsListView.swift
//  安全大师
//

import CoreData
import SwiftUI

struct InspectionRecordsListView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InspectionFinding.createdAt, ascending: false)],
        animation: .default
    )
    private var findings: FetchedResults<InspectionFinding>

    private var summaries: [DayInspectionSummary] {
        DaySummaryBuilder.summaries(from: Array(findings))
    }

    var body: some View {
        Group {
            if summaries.isEmpty {
                ContentUnavailableView("暂无排查记录", systemImage: "doc.text.magnifyingglass", description: Text("在排查结果页点击「记录」即可保存。"))
            } else {
                List(summaries) { s in
                    NavigationLink {
                        RecordDetailView(day: s.calendarDay)
                    } label: {
                        summaryRow(s)
                    }
                }
            }
        }
        .navigationTitle("排查记录")
        .inlineNavigationTitleMode()
    }

    private func summaryRow(_ s: DayInspectionSummary) -> some View {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy年M月d日"
        let dateStr = fmt.string(from: s.calendarDay)
        return Text("\(dateStr)，于\(s.displayLocation)共排查出\(s.hazardCount)条安全隐患。")
            .font(.body)
    }
}

#Preview {
    NavigationStack {
        InspectionRecordsListView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
