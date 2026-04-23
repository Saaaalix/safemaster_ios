//
//  InspectionResultView.swift
//  安全大师
//

import SwiftUI

struct InspectionResultView: View {
    @Environment(\.managedObjectContext) private var viewContext

    let payload: HazardResultPayload
    var onDone: () -> Void

    /// 防止连点「记录」写入多条相同 Core Data（导航未及时返回时用户会多次点击）。
    @State private var didSaveToCoreData = false
    @State private var isSavingToCoreData = false
    @State private var saveToCoreDataError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !payload.sitePhotoDatasOrdered.isEmpty {
                    ForEach(Array(payload.sitePhotoDatasOrdered.enumerated()), id: \.offset) { index, data in
                        if let img = Image.fromStoredData(data) {
                            Text(payload.sitePhotoDatasOrdered.count > 1 ? "照片 \(index + 1)" : "照片")
                                .font(.subheadline.weight(.semibold))
                            img
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 240)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                sectionTitle("隐患描述")
                Text(payload.analysis.hazardDescription)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                sectionTitle("整改措施")
                Text(payload.analysis.rectificationMeasures)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                sectionTitle("风险等级")
                Text(payload.analysis.riskLevel)
                    .font(.headline)

                sectionTitle("事故类别")
                Text(accidentCategoryBody(payload.analysis))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                sectionTitle("整改依据")
                Text(payload.analysis.legalBasis)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                sectionTitle("整改安排")
                Text(rectificationIntentSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .navigationTitle("排查结果")
        .inlineNavigationTitleMode()
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button("删除") {
                    onDone()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("记录") {
                    commitSaveIfNeeded()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(isSavingToCoreData)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .alert("无法保存", isPresented: Binding(
            get: { saveToCoreDataError != nil },
            set: { if !$0 { saveToCoreDataError = nil } }
        )) {
            Button("好的", role: .cancel) { saveToCoreDataError = nil }
        } message: {
            Text(saveToCoreDataError ?? "")
        }
    }

    private func commitSaveIfNeeded() {
        if didSaveToCoreData {
            onDone()
            return
        }
        guard !isSavingToCoreData else { return }
        isSavingToCoreData = true
        let ok = InspectionFinding.savePayload(payload, context: viewContext)
        isSavingToCoreData = false
        if ok {
            didSaveToCoreData = true
            if payload.rectificationIntent == .scheduled, payload.addDeadlineToDeviceCalendar {
                let loc = payload.location.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = loc.isEmpty ? "安全大师·隐患整改截止" : "安全大师·整改截止（\(loc)）"
                let snippet = String(payload.analysis.hazardDescription.prefix(200))
                let notes = "地点：\(loc.isEmpty ? "（未填）" : loc)\n\n\(snippet)"
                let due = payload.rectificationPlannedDueAt ?? Date()
                Task {
                    _ = await RectificationCalendarExporter.tryAddDeadlineReminder(
                        title: title,
                        notes: notes,
                        deadlineDay: due,
                        location: loc.isEmpty ? nil : loc
                    )
                }
            }
            onDone()
        } else {
            saveToCoreDataError = "无法写入本地记录，请检查存储空间或稍后重试。"
        }
    }

    private var rectificationIntentSummary: String {
        switch payload.rectificationIntent {
        case .immediate:
            let hasNote = !payload.prefillRectificationActionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasPhoto = payload.prefillRectificationPhotoData != nil && !(payload.prefillRectificationPhotoData?.isEmpty ?? true)
            let extra: String
            if hasNote || hasPhoto {
                extra = "（识别页已填写现场说明\(hasPhoto ? "与照片" : "")，将写入第 1 轮。）"
            } else {
                extra = "（可在记录详情补充现场说明与照片后再提交验收。）"
            }
            return "立即整改：保存后自动建立第 1 轮整改。\(extra)"
        case .scheduled:
            let d = payload.rectificationPlannedDueAt ?? Date()
            let cal = payload.addDeadlineToDeviceCalendar ? "保存后将尝试写入系统日历。" : "未选择写入系统日历。"
            return "限期整改：计划完成日 \(Self.dueOnlyFormatter.string(from: d))。\(cal)"
        }
    }

    private static let dueOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func accidentCategoryBody(_ r: HazardAnalysisResult) -> String {
        let maj = r.accidentCategoryMajor.trimmingCharacters(in: .whitespacesAndNewlines)
        let mino = r.accidentCategoryMinor.trimmingCharacters(in: .whitespacesAndNewlines)
        if maj.isEmpty, mino.isEmpty {
            return "（未判定）"
        }
        if mino.isEmpty {
            return "大类：\(maj)"
        }
        if maj.isEmpty {
            return "细类：\(mino)"
        }
        return "大类：\(maj)\n细类：\(mino)"
    }
}

#Preview {
    NavigationStack {
        InspectionResultView(
            payload: HazardResultPayload(
                photoData: nil,
                location: "示例工地",
                supplementaryText: "",
                analysis: HazardAnalysisResult(
                    hazardDescription: "示例",
                    rectificationMeasures: "示例",
                    riskLevel: "一般",
                    accidentCategoryMajor: "高处与建筑施工类",
                    accidentCategoryMinor: "高处坠落",
                    legalBasis: "示例法规摘录"
                )
            ),
            onDone: {}
        )
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
