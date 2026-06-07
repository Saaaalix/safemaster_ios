//
//  BuildingSafetyHubView.swift
//  安全大师
//

import CoreData
import PhotosUI
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct BuildingSafetyHubView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InspectionFinding.createdAt, ascending: false)],
        animation: .default
    )
    private var findings: FetchedResults<InspectionFinding>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SafetyEducationRecord.educationDate, ascending: false)],
        animation: .default
    )
    private var educationRecords: FetchedResults<SafetyEducationRecord>

    @State private var path: [SafetyNavigationRoute] = []
    @State private var rectificationRefreshToken = 0

    private static let productivityAccent = Color(red: 0.95, green: 0.65, blue: 0.3)
    fileprivate static let dashboardDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private var dashboardFindings: [InspectionFinding] {
        let _ = rectificationRefreshToken
        return Array(findings)
    }

    private var dashboardSummary: DashboardSummary {
        DashboardSummary(findings: dashboardFindings, educationRecords: Array(educationRecords))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    dashboardCard(summary: dashboardSummary)

                    hubActionTile(
                        title: "隐患识别",
                        subtitle: "拍照/文字描述，AI 辅助诊断",
                        systemImage: "viewfinder.circle.fill"
                    ) {
                        path.append(.hazardInspection)
                    }

                    hubActionTile(
                        title: "隐患整改",
                        subtitle: rectificationSubtitle(for: dashboardSummary),
                        systemImage: "checklist.checked"
                    ) {
                        path.append(.hazardRecords)
                    }

                    hubActionTile(
                        title: "导入箱",
                        subtitle: "先导入文件，再决定是否识别建档",
                        systemImage: "tray.full.fill"
                    ) {
                        path.append(.importedNoticeInbox)
                    }

                    hubActionTile(
                        title: "报告模板",
                        subtitle: "设置标题、字段、照片布局与签字栏",
                        systemImage: "doc.text.magnifyingglass"
                    ) {
                        path.append(.reportTemplate)
                    }

                    hubActionTile(
                        title: "安全教育",
                        subtitle: educationSubtitle(for: dashboardSummary),
                        systemImage: "person.3.sequence.fill"
                    ) {
                        path.append(.safetyEducation)
                    }

                    hubActionTile(
                        title: "月度总结",
                        subtitle: "汇总排查、整改与安全教育台账",
                        systemImage: "chart.bar.doc.horizontal.fill"
                    ) {
                        path.append(.monthlySummary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("建筑施工安全")
            .inlineNavigationTitleMode()
            .onRectificationStoreRefresh(in: viewContext, token: $rectificationRefreshToken)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    hubProfileEntry {
                        path.append(.profile)
                    }
                }
            }
            .navigationDestination(for: SafetyNavigationRoute.self) { route in
                switch route {
                case .hazardInspection:
                    HazardInspectionView(path: $path)
                case .profile:
                    UserProfileView()
                case .hazardResult(_, let payload):
                    InspectionResultView(payload: payload, onDone: dismissTopHazardResult)
                case .hazardRecords:
                    InspectionRecordsListView()
                case .hazardRecordsCategory(let category):
                    InspectionRecordsCategoryListView(category: category)
                case .highRiskFindings:
                    HighRiskFindingsQuickView()
                case .todayActivities:
                    TodayActivitiesQuickView()
                case .inspectionRecordFlatList:
                    InspectionRecordFlatListView()
                case .safetyEducation:
                    SafetyEducationView()
                case .monthlySummary:
                    MonthlyWorkSummaryView()
                case .reportTemplate:
                    ReportTemplateEditorView()
                case .hazardLibrary:
                    DocumentLibraryView()
                case .importedNoticeInbox:
                    ImportedNoticeInboxView()
                }
            }
        }
    }

    private func dashboardCard(summary: DashboardSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("工作台")
                        .font(.title3.weight(.bold))
                    Text("今日概览与整改闭环进度")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Text(summary.totalCount == 0 ? "未开始" : "共 \(summary.totalCount) 条")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Self.productivityAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Self.productivityAccent.opacity(0.14), in: Capsule())
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                dashboardMetric(
                    title: "待整改",
                    value: "\(summary.pendingCount)",
                    caption: summary.pendingCount == 0 ? "暂无需跟进" : "需跟进闭环",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: Self.productivityAccent,
                    action: {
                        path.append(.hazardRecordsCategory(.pendingRectification))
                    }
                )
                dashboardMetric(
                    title: "高风险",
                    value: "\(summary.highRiskCount)",
                    caption: summary.highRiskCount == 0 ? "当前风险平稳" : "重大/较大",
                    systemImage: "flame.fill",
                    tint: .red,
                    action: {
                        path.append(.highRiskFindings)
                    }
                )
                dashboardMetric(
                    title: "已闭环",
                    value: "\(summary.closedCount)",
                    caption: summary.closedCount == 0 ? "暂无闭环记录" : "验收通过",
                    systemImage: "checkmark.seal.fill",
                    tint: .green,
                    action: {
                        path.append(.hazardRecordsCategory(.completedRectification))
                    }
                )
                dashboardMetric(
                    title: "今日新增",
                    value: "\(summary.todayCount)",
                    caption: summary.todayCount == 0 ? "今日暂无新增" : "排查/教育",
                    systemImage: "calendar.badge.plus",
                    tint: .blue,
                    action: {
                        path.append(.todayActivities)
                    }
                )
            }

            recentActivity(summary: summary)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 5)
    }

    private func dashboardMetric(
        title: String,
        value: String,
        caption: String,
        systemImage: String,
        tint: Color,
        action: (() -> Void)? = nil
    ) -> some View {
        Group {
            if let action {
                Button(action: action) {
                    dashboardMetricContent(
                        title: title,
                        value: value,
                        caption: caption,
                        systemImage: systemImage,
                        tint: tint,
                        tappable: true
                    )
                }
                .buttonStyle(.plain)
                .buttonStyle(DashboardMetricButtonStyle())
            } else {
                dashboardMetricContent(
                    title: title,
                    value: value,
                    caption: caption,
                    systemImage: systemImage,
                    tint: tint,
                    tappable: false
                )
            }
        }
    }

    private func dashboardMetricContent(
        title: String,
        value: String,
        caption: String,
        systemImage: String,
        tint: Color,
        tappable: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
            if tappable {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGroupedBackground).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func recentActivity(summary: DashboardSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Self.productivityAccent)
                .frame(width: 36, height: 36)
                .background(Self.productivityAccent.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.recentTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(summary.recentSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Self.productivityAccent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func hubActionTile(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Self.productivityAccent)
                    .frame(width: 52, height: 52)
                    .background(Self.productivityAccent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(18)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func hubProfileEntry(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Self.productivityAccent)
                .frame(width: 36, height: 36)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("我的")
    }

    private func rectificationSubtitle(for summary: DashboardSummary) -> String {
        if summary.pendingCount > 0 {
            return "待整改 \(summary.pendingCount) 项，查看闭环进度"
        }
        if summary.closedCount > 0 {
            return "暂无待整改，查看已闭环记录"
        }
        return "查看记录并跟进整改进度"
    }

    private func educationSubtitle(for summary: DashboardSummary) -> String {
        if summary.monthEducationCount > 0 {
            return "本月 \(summary.monthEducationCount) 次教育，\(summary.monthParticipantCount) 人次"
        }
        return "拍照留痕，生成教育记录"
    }

    private func dismissTopHazardResult() {
        guard let last = path.last, case .hazardResult = last else { return }
        var t = Transaction()
        t.disablesAnimations = true
        _ = withTransaction(t) {
            path.removeLast()
        }
    }
}

private struct DashboardMetricButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct HighRiskFindingsQuickView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InspectionFinding.createdAt, ascending: false)],
        animation: .default
    )
    private var findings: FetchedResults<InspectionFinding>

    private var highRiskFindings: [InspectionFinding] {
        Array(findings).filter { finding in
            let normalized = HazardRiskLevel.normalizedForStorage(finding.riskLevel)
            return normalized == "重大风险" || normalized == "较大风险"
        }
    }

    var body: some View {
        Group {
            if highRiskFindings.isEmpty {
                ContentUnavailableView("暂无高风险隐患", systemImage: "flame")
            } else {
                List(highRiskFindings, id: \.objectID) { finding in
                    NavigationLink {
                        RecordDetailView(findingObjectID: finding.objectID)
                    } label: {
                        InspectionRecordSummaryRow(
                            finding: finding,
                            status: .workflow(for: finding)
                        )
                    }
                }
            }
        }
        .navigationTitle("高风险隐患")
        .inlineNavigationTitleMode()
    }
}

private struct TodayActivitiesQuickView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InspectionFinding.createdAt, ascending: false)],
        animation: .default
    )
    private var findings: FetchedResults<InspectionFinding>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SafetyEducationRecord.educationDate, ascending: false)],
        animation: .default
    )
    private var educationRecords: FetchedResults<SafetyEducationRecord>

    private var todayFindings: [InspectionFinding] {
        Array(findings).filter { finding in
            guard let date = finding.effectiveArchiveDate else { return false }
            return Calendar.current.isDateInToday(date)
        }
    }

    private var todayEducation: [SafetyEducationRecord] {
        Array(educationRecords).filter { record in
            guard let date = record.educationDate ?? record.createdAt else { return false }
            return Calendar.current.isDateInToday(date)
        }
    }

    var body: some View {
        List {
            if todayFindings.isEmpty, todayEducation.isEmpty {
                ContentUnavailableView("今日暂无新增", systemImage: "calendar")
            } else {
                if !todayFindings.isEmpty {
                    Section("今日排查") {
                        ForEach(todayFindings, id: \.objectID) { finding in
                            NavigationLink {
                                RecordDetailView(findingObjectID: finding.objectID)
                            } label: {
                                InspectionRecordSummaryRow(
                                    finding: finding,
                                    status: .workflow(for: finding)
                                )
                            }
                        }
                    }
                }
                if !todayEducation.isEmpty {
                    Section("今日教育") {
                        ForEach(todayEducation, id: \.objectID) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.topic?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? (record.topic ?? "") : "未命名教育记录")
                                    .font(.subheadline.weight(.semibold))
                                Text(record.projectName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? (record.projectName ?? "") : "未填写项目")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle("今日新增")
        .inlineNavigationTitleMode()
    }
}

private struct DashboardSummary {
    let totalCount: Int
    let pendingCount: Int
    let highRiskCount: Int
    let closedCount: Int
    let todayCount: Int
    let monthEducationCount: Int
    let monthParticipantCount: Int
    let recentTitle: String
    let recentSubtitle: String

    init(findings: [InspectionFinding], educationRecords: [SafetyEducationRecord]) {
        let calendar = Calendar.current
        totalCount = findings.count
        pendingCount = findings.filter(\.shouldAppearInRectificationWorkflow).count
        closedCount = findings.filter(\.isRectificationClosed).count
        highRiskCount = findings.filter { finding in
            let normalized = HazardRiskLevel.normalizedForStorage(finding.riskLevel)
            return normalized == "重大风险" || normalized == "较大风险"
        }.count
        todayCount = findings.filter { finding in
            guard let date = finding.effectiveArchiveDate else { return false }
            return calendar.isDateInToday(date)
        }.count + educationRecords.filter { record in
            guard let date = record.educationDate ?? record.createdAt else { return false }
            return calendar.isDateInToday(date)
        }.count

        let monthInterval = calendar.dateInterval(of: .month, for: Date())
        let monthEducationRecords = educationRecords.filter { record in
            guard let interval = monthInterval,
                  let date = record.educationDate ?? record.createdAt
            else { return false }
            return interval.contains(date)
        }
        monthEducationCount = monthEducationRecords.count
        monthParticipantCount = monthEducationRecords.reduce(0) { $0 + Int($1.participantCount) }

        if let recent = findings.max(by: { lhs, rhs in
            Self.latestActivityDate(for: lhs) < Self.latestActivityDate(for: rhs)
        }) {
            let title = Self.displayTitle(for: recent)
            let dateText = Self.format(Self.latestActivityDate(for: recent))
            recentTitle = "最近记录：\(title)"
            recentSubtitle = "\(recent.rectificationClosureSummary.badgeText) · \(dateText)"
        } else {
            recentTitle = "暂无排查记录"
            recentSubtitle = "开始一次隐患识别后，这里会显示最新进度"
        }
    }

    private static func latestActivityDate(for finding: InspectionFinding) -> Date {
        let roundDates = finding.rectificationRoundsArray.flatMap { round in
            [round.verifiedAt, round.createdAt].compactMap { $0 }
        }
        return ([finding.createdAt, finding.discoveredAt].compactMap { $0 } + roundDates).max() ?? .distantPast
    }

    private static func displayTitle(for finding: InspectionFinding) -> String {
        let candidates = [
            finding.location,
            finding.hazardDescription,
            finding.reportProjectName
        ]

        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }

        return "未填写地点"
    }

    private static func format(_ date: Date) -> String {
        guard date > .distantPast else { return "暂无时间" }
        return BuildingSafetyHubView.dashboardDateFormatter.string(from: date)
    }
}

enum SafetyEducationType: String, CaseIterable, Identifiable {
    case daily = "日常安全教育"
    case threeLevel = "三级安全教育"
    case preShift = "班前教育"
    case special = "专项安全教育"
    case holiday = "节假日前教育"
    case warning = "事故警示教育"
    case onboarding = "新工人入场教育"

    var id: String { rawValue }
}

extension SafetyEducationRecord {
    var displayDate: Date {
        educationDate ?? createdAt ?? Date()
    }

    var displayType: String {
        let text = educationType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? SafetyEducationType.daily.rawValue : text
    }

    var displayTopic: String {
        let text = topic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? displayType : text
    }

    var displayProject: String {
        let text = projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "未填写项目" : text
    }

    var displayParticipants: String {
        let text = participants?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty { return text }
        return participantCount > 0 ? "\(participantCount) 人" : "未填写"
    }

    static func draftText(
        type: String,
        project: String,
        topic: String,
        location: String,
        instructor: String,
        participants: String,
        participantCount: String,
        notes: String
    ) -> String {
        let cleanType = type.isEmpty ? SafetyEducationType.daily.rawValue : type
        let cleanTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = cleanTopic.isEmpty ? cleanType : cleanTopic
        let people = participants.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = participantCount.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let teacher = instructor.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        if !project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("项目：\(project.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        lines.append("教育类型：\(cleanType)")
        lines.append("教育主题：\(title)")
        if !place.isEmpty { lines.append("教育地点：\(place)") }
        if !teacher.isEmpty { lines.append("教育人：\(teacher)") }
        if !people.isEmpty {
            lines.append("参加人员：\(people)")
        } else if !count.isEmpty {
            lines.append("参加人数：\(count) 人")
        }
        lines.append("教育内容：围绕\(title)开展安全教育，结合现场作业特点，对相关安全风险、操作要求和注意事项进行了讲解。")
        if !note.isEmpty {
            lines.append("现场补充：\(note)")
        }
        lines.append("教育要求：参加人员已了解本次教育要点，后续作业中应按交底要求落实安全防护、规范操作并接受现场管理人员检查。")
        return lines.joined(separator: "\n")
    }
}

private struct SafetyEducationView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SafetyEducationRecord.educationDate, ascending: false)],
        animation: .default
    )
    private var records: FetchedResults<SafetyEducationRecord>

    @State private var educationDate = Date()
    @State private var selectedType: SafetyEducationType = .daily
    @State private var projectName = ""
    @State private var topic = ""
    @State private var location = ""
    @State private var instructorName = ""
    @State private var participants = ""
    @State private var participantCount = ""
    @State private var notes = ""
    @State private var generatedText = ""
    @State private var photoData: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var saveMessage: String?

    private static let productivityAccent = Color(red: 0.95, green: 0.65, blue: 0.3)
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private var latestRecord: SafetyEducationRecord? {
        records.first
    }

    private var recentProjectOptions: [String] {
        recentOptions { $0.projectName }
    }

    private var recentLocationOptions: [String] {
        recentOptions { $0.location }
    }

    private var recentInstructorOptions: [String] {
        recentOptions { $0.instructorName }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                educationEditor
                recentEducationList
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("安全教育")
        .inlineNavigationTitleMode()
        .onChange(of: pickerItem) { _, new in
            guard let new else { return }
            Task {
                if let data = try? await new.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        let optimized = Data.optimizedPhotoStorageData(from: data) ?? data
                        photoData = optimized
                        SitePhotoLibrarySaver.saveToPhotoLibraryIfPermitted(optimized, source: "安全教育照片")
                        pickerItem = nil
                    }
                }
            }
        }
    }

    private var educationEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("新增教育记录", systemImage: "person.3.sequence.fill")
                    .font(.headline)
                Spacer()
                if latestRecord != nil {
                    Button("套用最近一条") {
                        applyLatestRecordTemplate()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                }
            }

            if let image = Image.fromStoredData(photoData) {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(photoData == nil ? "添加教育照片" : "更换教育照片", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            DatePicker("教育日期", selection: $educationDate, displayedComponents: [.date])
                .environment(\.locale, Locale(identifier: "zh_CN"))

            Picker("教育类型", selection: $selectedType) {
                ForEach(SafetyEducationType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }

            educationTextField("项目名称", text: $projectName, placeholder: "例如：润城第二大道")
            quickValueChips(options: recentProjectOptions, text: $projectName)
            educationTextField("教育主题", text: $topic, placeholder: "例如：高处作业安全注意事项")
            educationTextField("教育地点", text: $location, placeholder: "例如：项目会议室 / 施工现场")
            quickValueChips(options: recentLocationOptions, text: $location)
            educationTextField("教育人", text: $instructorName, placeholder: "例如：张三")
            quickValueChips(options: recentInstructorOptions, text: $instructorName)
            educationTextField("参加人员/班组", text: $participants, placeholder: "例如：架子工班组、木工班组")
            participantCountEditor

            VStack(alignment: .leading, spacing: 6) {
                Text("现场补充")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                TextField("补充本次教育重点、照片内容或签到情况", text: $notes, axis: .vertical)
                    .lineLimit(3...8)
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button {
                generatedText = SafetyEducationRecord.draftText(
                    type: selectedType.rawValue,
                    project: projectName,
                    topic: topic,
                    location: location,
                    instructor: instructorName,
                    participants: participants,
                    participantCount: participantCount,
                    notes: notes
                )
            } label: {
                Label("生成教育记录草稿", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Self.productivityAccent)

            if !generatedText.isEmpty {
                TextField("教育记录草稿", text: $generatedText, axis: .vertical)
                    .lineLimit(6...14)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Button {
                saveRecord()
            } label: {
                Label("保存教育记录", systemImage: "tray.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let saveMessage {
                Text(saveMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var recentEducationList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("最近教育记录", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            if records.isEmpty {
                Text("暂无安全教育记录。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(records.prefix(8)), id: \.objectID) { record in
                    HStack(alignment: .top, spacing: 10) {
                        if let image = Image.fromStoredData(record.photoData) {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 58, height: 58)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            Image(systemName: "person.3.fill")
                                .foregroundStyle(Self.productivityAccent)
                                .frame(width: 58, height: 58)
                                .background(Self.productivityAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.displayTopic)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("\(record.displayType) · \(Self.dateFormatter.string(from: record.displayDate))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(record.displayParticipants)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func educationTextField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
            TextField(placeholder, text: text)
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var participantCountEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("参加人数")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
            HStack(spacing: 8) {
                Button {
                    adjustParticipantCount(by: -1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)

                TextField("例如：18", text: $participantCount)
                    .keyboardType(.numberPad)
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    adjustParticipantCount(by: 1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func quickValueChips(options: [String], text: Binding<String>) -> some View {
        if !options.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        Button(option) {
                            text.wrappedValue = option
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                    }
                }
            }
        }
    }

    private func saveRecord() {
        if generatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            generatedText = SafetyEducationRecord.draftText(
                type: selectedType.rawValue,
                project: projectName,
                topic: topic,
                location: location,
                instructor: instructorName,
                participants: participants,
                participantCount: participantCount,
                notes: notes
            )
        }

        let record = SafetyEducationRecord(context: viewContext)
        record.educationId = UUID().uuidString
        record.createdAt = Date()
        record.educationDate = educationDate
        record.educationType = selectedType.rawValue
        record.projectName = projectName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        record.topic = topic.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        record.location = location.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        record.instructorName = instructorName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        record.participants = participants.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        record.participantCount = Int32(Int(participantCount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
        record.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        record.generatedRecordText = generatedText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        record.photoData = photoData

        do {
            try viewContext.save()
            saveMessage = "已保存安全教育记录。"
            resetForm()
        } catch {
            viewContext.rollback()
            saveMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func resetForm() {
        educationDate = Date()
        selectedType = .daily
        projectName = ""
        topic = ""
        location = ""
        instructorName = ""
        participants = ""
        participantCount = ""
        notes = ""
        generatedText = ""
        photoData = nil
    }

    private func adjustParticipantCount(by delta: Int) {
        let current = Int(participantCount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let next = max(0, current + delta)
        participantCount = next == 0 ? "" : String(next)
    }

    private func recentOptions(_ getter: (SafetyEducationRecord) -> String?) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for record in records {
            let value = getter(record)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { continue }
            if seen.insert(value).inserted {
                ordered.append(value)
            }
            if ordered.count >= 5 { break }
        }
        return ordered
    }

    private func applyLatestRecordTemplate() {
        guard let record = latestRecord else { return }
        projectName = record.projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        topic = record.topic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        location = record.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        instructorName = record.instructorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        participants = record.participants?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        participantCount = record.participantCount > 0 ? String(record.participantCount) : ""
        notes = record.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        selectedType = SafetyEducationType(rawValue: record.educationType ?? "") ?? .daily
        generatedText = ""
        saveMessage = "已套用最近一条，可按需修改后保存。"
    }
}

private struct MonthlyWorkSummaryView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InspectionFinding.discoveredAt, ascending: false)],
        animation: .default
    )
    private var findings: FetchedResults<InspectionFinding>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SafetyEducationRecord.educationDate, ascending: false)],
        animation: .default
    )
    private var educationRecords: FetchedResults<SafetyEducationRecord>

    @State private var selectedMonth = Date()
    @State private var draftText = ""
    @State private var copyHint: String?
    @State private var optimizeHint: String?

    private static let productivityAccent = Color(red: 0.95, green: 0.65, blue: 0.3)
    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()

    private var stats: MonthlyWorkStats {
        MonthlyWorkStats(
            month: selectedMonth,
            findings: Array(findings),
            educationRecords: Array(educationRecords)
        )
    }

    private var previousMonthStats: MonthlyWorkStats {
        let previous = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        return MonthlyWorkStats(
            month: previous,
            findings: Array(findings),
            educationRecords: Array(educationRecords)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                monthPickerCard
                statisticsCard
                riskFocusCard
                draftCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("月度总结")
        .inlineNavigationTitleMode()
        .onAppear {
            draftText = stats.defaultDraft
        }
        .onChange(of: selectedMonth) { _, _ in
            draftText = stats.defaultDraft
        }
    }

    private var monthPickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("统计月份", systemImage: "calendar")
                .font(.headline)
            DatePicker("选择月份", selection: $selectedMonth, displayedComponents: [.date])
                .environment(\.locale, Locale(identifier: "zh_CN"))
            Text("当前汇总：\(Self.monthFormatter.string(from: selectedMonth))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statisticsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("数据统计", systemImage: "tablecells")
                .font(.headline)

            if stats.pendingFindings > 0 {
                Label("本月仍有 \(stats.pendingFindings) 项待整改，建议优先跟进闭环。", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statTile(
                    "排查隐患",
                    "\(stats.totalFindings)",
                    trendCaption(current: stats.totalFindings, previous: previousMonthStats.totalFindings, positiveIsGood: false, zeroText: "与上月持平"),
                    .orange
                )
                statTile(
                    "已闭环",
                    "\(stats.closedFindings)",
                    "闭环率 \(stats.closureRateText) · \(trendCaption(current: stats.closedFindings, previous: previousMonthStats.closedFindings, positiveIsGood: true, zeroText: "与上月持平"))",
                    .green
                )
                statTile(
                    "待整改",
                    "\(stats.pendingFindings)",
                    trendCaption(current: stats.pendingFindings, previous: previousMonthStats.pendingFindings, positiveIsGood: true, zeroText: "与上月持平"),
                    .red
                )
                statTile(
                    "安全教育",
                    "\(stats.educationCount)",
                    "\(stats.participantCount) 人次 · \(trendCaption(current: stats.educationCount, previous: previousMonthStats.educationCount, positiveIsGood: true, zeroText: "与上月持平"))",
                    .blue
                )
            }

            VStack(spacing: 8) {
                statLine("高风险隐患", "\(stats.highRiskFindings) 项")
                statLine("逾期/未闭环", "\(stats.pendingFindings) 项")
                statLine("主要隐患类别", stats.topAccidentCategory)
                statLine("主要教育类型", stats.topEducationType)
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var riskFocusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("本月重点隐患（前3）", systemImage: "list.bullet.clipboard")
                .font(.headline)
            if stats.topFindings.isEmpty {
                Text("本月暂无隐患记录。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(stats.topFindings.enumerated()), id: \.element.objectID) { index, finding in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(finding.reportLocationPart)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(finding.reportFormalIssueDescription(maxLength: 42))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(finding.rectificationClosureSummary.compactBadgeText)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(finding.isRectificationClosed ? .green : .orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var draftCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("月报草稿", systemImage: "doc.text")
                    .font(.headline)
                Spacer()
                Button {
                    draftText = stats.defaultDraft
                    optimizeHint = nil
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("重新生成月报草稿")
                Button {
                    optimizeMonthlyDraft()
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("智能优化月报草稿")
#if os(iOS)
                Button {
                    UIPasteboard.general.string = draftText
                    copyHint = "已复制到剪贴板"
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("复制月报草稿")
#endif
                ShareLink(
                    item: draftText,
                    subject: Text("\(Self.monthFormatter.string(from: selectedMonth))月度总结"),
                    message: Text("来自安全大师的月度总结草稿")
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextField("月报草稿", text: $draftText, axis: .vertical)
                .lineLimit(12...24)
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let copyHint {
                Text(copyHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let optimizeHint {
                Text(optimizeHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("这份草稿先基于本机台账生成，保留现场资料口吻，后续可再接入服务端 AI 做润色。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statTile(_ title: String, _ value: String, _ caption: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text(title)
                .font(.caption.weight(.semibold))
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }

    private func trendCaption(
        current: Int,
        previous: Int,
        positiveIsGood: Bool,
        zeroText: String
    ) -> String {
        let diff = current - previous
        if diff == 0 { return zeroText }
        let absValue = abs(diff)
        let up = diff > 0
        let symbol = up ? "↑" : "↓"
        let positiveDirection = positiveIsGood ? !up : up
        return "\(symbol)\(absValue) (\(positiveDirection ? "趋势向好" : "需关注"))"
    }

    private func optimizeMonthlyDraft() {
        let raw = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        draftText = stats.optimizedDraft(from: raw.isEmpty ? stats.defaultDraft : raw)
        optimizeHint = "已完成智能优化，可继续手动调整。"
    }
}

private struct MonthlyWorkStats {
    let month: Date
    let monthFindings: [InspectionFinding]
    let monthEducationRecords: [SafetyEducationRecord]

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()

    init(month: Date, findings: [InspectionFinding], educationRecords: [SafetyEducationRecord]) {
        self.month = month
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: month)
        monthFindings = findings.filter { finding in
            guard let interval, let date = finding.effectiveArchiveDate else { return false }
            return interval.contains(date)
        }
        monthEducationRecords = educationRecords.filter { record in
            guard let interval else { return false }
            return interval.contains(record.displayDate)
        }
    }

    var totalFindings: Int { monthFindings.count }
    var closedFindings: Int { monthFindings.filter(\.isRectificationClosed).count }
    var pendingFindings: Int { monthFindings.filter(\.shouldAppearInRectificationWorkflow).count }
    var highRiskFindings: Int {
        monthFindings.filter {
            let normalized = HazardRiskLevel.normalizedForStorage($0.riskLevel)
            return normalized == "重大风险" || normalized == "较大风险"
        }.count
    }
    var educationCount: Int { monthEducationRecords.count }
    var participantCount: Int {
        monthEducationRecords.reduce(0) { $0 + Int($1.participantCount) }
    }
    var closureRateText: String {
        guard totalFindings > 0 else { return "—" }
        let value = Double(closedFindings) / Double(totalFindings) * 100
        return "\(Int(value.rounded()))%"
    }

    var topAccidentCategory: String {
        topValue(monthFindings.compactMap { $0.accidentCategoryMinor ?? $0.accidentCategoryMajor }) ?? "暂无"
    }

    var topEducationType: String {
        topValue(monthEducationRecords.map(\.displayType)) ?? "暂无"
    }

    var topFindings: [InspectionFinding] {
        monthFindings
            .sorted { lhs, rhs in
                let lhsPending = lhs.shouldAppearInRectificationWorkflow ? 1 : 0
                let rhsPending = rhs.shouldAppearInRectificationWorkflow ? 1 : 0
                if lhsPending != rhsPending { return lhsPending > rhsPending }
                let lhsRisk = riskPriority(lhs)
                let rhsRisk = riskPriority(rhs)
                if lhsRisk != rhsRisk { return lhsRisk > rhsRisk }
                return (lhs.effectiveArchiveDate ?? lhs.createdAt ?? .distantPast) > (rhs.effectiveArchiveDate ?? rhs.createdAt ?? .distantPast)
            }
            .prefix(3)
            .map { $0 }
    }

    var defaultDraft: String {
        let monthText = Self.monthFormatter.string(from: month)
        var lines: [String] = []
        lines.append("【一、本月概况】")
        lines.append("\(monthText)共记录隐患排查 \(totalFindings) 项，已闭环 \(closedFindings) 项，待整改 \(pendingFindings) 项，闭环率 \(closureRateText)。")
        lines.append("")
        lines.append("【二、风险与问题】")
        lines.append("重大/较大风险隐患 \(highRiskFindings) 项，主要隐患类别为\(topAccidentCategory)。")
        lines.append("")
        lines.append("【三、整改闭环进展】")
        lines.append("本月重点跟进未闭环事项，整改过程已覆盖照片留痕、整改说明与验收结论记录。")
        lines.append("")
        lines.append("【四、下月计划】")
        if pendingFindings > 0 {
            lines.append("继续跟进未闭环隐患，重点核查整改后照片、实际整改说明和验收结论，避免记录停留在排查阶段。")
        } else {
            lines.append("保持现场巡查和教育留痕，重点关注高风险作业、临边洞口、临时用电和班前教育落实情况。")
        }
        lines.append("本月开展安全教育 \(educationCount) 次，累计参加 \(participantCount) 人次，主要教育类型为\(topEducationType)。")
        return lines.joined(separator: "\n")
    }

    func optimizedDraft(from _: String) -> String {
        let monthText = Self.monthFormatter.string(from: month)
        let focusText: String
        if let first = topFindings.first {
            focusText = "重点隐患主要集中在\(first.reportLocationPart)等部位。"
        } else {
            focusText = "本月未形成重点隐患聚集点。"
        }

        var lines: [String] = []
        lines.append("【一、本月概况】")
        lines.append("\(monthText)累计排查隐患 \(totalFindings) 项，已闭环 \(closedFindings) 项，待整改 \(pendingFindings) 项，闭环率 \(closureRateText)。")
        lines.append("")
        lines.append("【二、风险与问题】")
        lines.append("重大/较大风险隐患 \(highRiskFindings) 项，主要隐患类别为\(topAccidentCategory)。\(focusText)")
        lines.append("")
        lines.append("【三、整改闭环进展】")
        if pendingFindings > 0 {
            lines.append("目前仍有未闭环事项，已纳入持续跟进，重点核查整改后照片、实际整改说明与验收结论，确保问题销项闭环。")
        } else {
            lines.append("本月隐患整改闭环总体稳定，相关记录已形成“排查-整改-验收”完整留痕。")
        }
        lines.append("")
        lines.append("【四、下月计划】")
        lines.append("继续围绕高风险作业、临边洞口、临时用电和班前教育开展专项检查，并保持教育留痕常态化。")
        lines.append("本月安全教育 \(educationCount) 次，累计 \(participantCount) 人次，主要教育类型为\(topEducationType)。")
        return lines.joined(separator: "\n")
    }

    private func topValue(_ values: [String]) -> String? {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "—" }
        guard !cleaned.isEmpty else { return nil }
        let grouped = Dictionary(grouping: cleaned, by: { $0 })
        return grouped.max { lhs, rhs in
            lhs.value.count < rhs.value.count
        }?.key
    }

    private func riskPriority(_ finding: InspectionFinding) -> Int {
        switch HazardRiskLevel.normalizedForStorage(finding.riskLevel) {
        case "重大风险": return 3
        case "较大风险": return 2
        case "一般风险": return 1
        default: return 0
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension View {
    /// 整改轮次写入同一 `viewContext` 后，驱动首页概览重新计算。
    func onRectificationStoreRefresh(
        in context: NSManagedObjectContext,
        token: Binding<Int>
    ) -> some View {
        onReceive(
            NotificationCenter.default.publisher(
                for: .NSManagedObjectContextDidSave,
                object: context
            )
        ) { note in
            guard shouldRefreshHubSummary(from: note) else { return }
            context.processPendingChanges()
            token.wrappedValue &+= 1
        }
        .onAppear {
            context.processPendingChanges()
            token.wrappedValue &+= 1
        }
    }
}

private func shouldRefreshHubSummary(from note: Notification) -> Bool {
    let keys = [
        NSInsertedObjectsKey,
        NSUpdatedObjectsKey,
        NSDeletedObjectsKey
    ]
    for key in keys {
        guard let objects = note.userInfo?[key] as? Set<NSManagedObject> else { continue }
        if objects.contains(where: { $0 is RectificationRound || $0 is InspectionFinding || $0 is SafetyEducationRecord }) {
            return true
        }
    }
    return false
}

#Preview {
    BuildingSafetyHubView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
