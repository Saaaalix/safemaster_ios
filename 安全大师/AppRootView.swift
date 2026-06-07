//
//  AppRootView.swift
//  安全大师
//

import SwiftUI

struct AppRootView: View {
    @AppStorage("selectedSafetyDomain") private var selectedDomain: String = ""
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var importedNoticeText: String?
    @State private var showSharedImportIntake = false
    @State private var showImportedNoticeInbox = false
    @State private var importBannerMessage: String?

    var body: some View {
        Group {
            if selectedDomain.isEmpty {
                DomainSelectionView {
                    selectedDomain = "building"
                }
            } else {
                BuildingSafetyHubView()
            }
        }
        .overlay(alignment: .top) {
            if let importBannerMessage {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.subheadline.weight(.semibold))
                    Text(importBannerMessage)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(Color.green.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            self.importBannerMessage = nil
                        }
                    }
                }
            }
        }
        .onAppear {
            checkPendingSharedImport()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                checkPendingSharedImport()
            }
        }
        .sheet(isPresented: $showSharedImportIntake) {
            if let importedNoticeText {
                ExternalNoticeIntakeView(
                    prefilledRawText: importedNoticeText,
                    autoRecognizeOnAppear: true
                )
            } else {
                ExternalNoticeIntakeView()
            }
        }
        .sheet(isPresented: $showImportedNoticeInbox) {
            NavigationStack {
                ImportedNoticeInboxView()
                    .environment(\.managedObjectContext, viewContext)
            }
        }
        .onOpenURL { url in
            handleOpenURL(url)
        }
    }

    private func checkPendingSharedImport() {
        guard !showSharedImportIntake else { return }
        Task {
            guard let pending = await SharedNoticeImportBridge.consumePendingImport() else { return }
            await MainActor.run {
                handlePendingSharedImport(pending)
            }
        }
    }

    private func handlePendingSharedImport(_ pending: SharedNoticeImportBridge.PendingImport) {
        switch pending {
        case .text(let text):
            presentImportedText(text, banner: "已收到分享内容，正在打开识别页…")
        case .fileStored(let fileName):
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                importBannerMessage = "已接收文件“\(fileName)”，正在打开导入箱…"
            }
            showImportedNoticeInbox = true
        }
    }

    private func presentImportedText(_ text: String, banner: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        importedNoticeText = trimmed
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            importBannerMessage = banner
        }
        showSharedImportIntake = true
    }

    private func handleOpenURL(_ url: URL) {
        Task {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard let text = await ImportedNoticeTextExtractor.extractText(from: url) else { return }
            await MainActor.run {
                guard !showSharedImportIntake else { return }
                presentImportedText(text, banner: "已从外部文件导入，正在打开识别页…")
            }
        }
    }
}

#Preview {
    AppRootView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
