//
//  UserProfileView.swift
//  安全大师
//

import AuthenticationServices
import Combine
import StoreKit
import SwiftUI

struct UserProfileView: View {
    private static let monthlyProductID = "com.safeMaster.aqds.monthly"
    private static let appleLoginEnabled = false

    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("profileRealName") private var realName: String = ""
    @AppStorage("profileDisplayName") private var displayName: String = "安全员"
    @AppStorage("profileUserId") private var storedUserId: String = ""

    @State private var appleSignInErrorMessage: String?
    @State private var serverCredits: Int?
    @State private var serverSubscription: CloudSubscriptionSnapshot?
    @State private var serverSyncMessage: String?
    @State private var isSyncingServer = false
    @State private var showAppleLoginDetail = false
    @State private var signedInAppleUserID: String? = KeychainStore.appleUserIdentifier()
    @State private var authSessionRevision = UUID()

    private var isSignedInWithApple: Bool {
        signedInAppleUserID != nil
    }

    private var hasCloudAccessToken: Bool {
        KeychainStore.safemasterAccessToken() != nil
    }

    var body: some View {
        List {
            Section {
                Text("账号与 AI 额度由安全大师官方云端服务提供，无需也不支持在 App 内填写服务器地址。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("安全大师云端")
            }

            Section("身份信息") {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.2))
                            .frame(width: 72, height: 72)
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("姓名（用于水印与导出）", text: $realName)
                            .font(.headline.weight(.semibold))
                        TextField("昵称（App 显示）", text: $displayName)
                            .font(.subheadline)
                        Text("ID：\(profileIdentifierText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    if !Self.appleLoginEnabled {
                        Label("当前为本地使用模式，登录与会员功能暂未启用。", systemImage: "person.crop.circle.badge.xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("隐患记录、导入核对、报告模板和月度总结可继续本地使用。后续需要云端额度或订阅时，再打开 Apple 登录入口。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if isSignedInWithApple {
                        Label("已通过 Apple 登录，可正常使用云端能力。", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                        if isSyncingServer {
                            HStack {
                                ProgressView()
                                Text("正在连接云端…")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button(showAppleLoginDetail ? "收起登录说明" : "查看登录说明") {
                            showAppleLoginDetail.toggle()
                        }
                        .font(.caption.weight(.semibold))
                        if showAppleLoginDetail {
                            Text("登录成功后，系统会把 Apple 的 identityToken 发送到官方服务器，换取 accessToken 并保存在本机钥匙串，用于查询云端额度与会员状态。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Button("退出 Apple 登录", role: .destructive) {
                            signOutAppleSession()
                        }
                    } else {
                        Text("请先完成 Apple 登录，才能同步会员状态与 AI 额度。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            handleAppleAuthorization(result)
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    if let appleSignInErrorMessage {
                        Text(appleSignInErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if let serverSyncMessage {
                        Text(serverSyncMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("登录")
            }

            Section("账户") {
                accountSummaryRows
                if Self.appleLoginEnabled {
                    accountSecondaryRows
                    Button {
                        Task { await refreshServerCreditsOnly() }
                    } label: {
                        Label("刷新会员与额度", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasCloudAccessToken || isSyncingServer)

                    Button {
                        Task { await purchaseMonthlyPlan() }
                    } label: {
                        Label("购买月会员", systemImage: "creditcard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasCloudAccessToken || isSyncingServer)
#if DEBUG
                    Button("模拟续费30天（开发联调）") {
                        Task { await mockRenewMonthlyPlan(days: 30) }
                    }
                    .disabled(!hasCloudAccessToken || isSyncingServer)
#endif
                } else {
                    Text("登录与订阅入口已临时关闭，避免 Apple 沙盒账号流程影响日常功能测试。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("当前阶段先完成规则联调：月费48元、每日 AI 点数额度、报告生成不限次。正式版本将接入 Apple 订阅与验票。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("我的")
        .inlineNavigationTitleMode()
        .onAppear {
            migrateProfileNameIfNeeded()
            syncAppleProfileDisplay()
            if Self.appleLoginEnabled {
                Task { await refreshServerCreditsOnly() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .safemasterCreditsDidChange)) { note in
            if Self.appleLoginEnabled, hasCloudAccessToken, isSignedInWithApple, let c = note.userInfo?["credits"] as? Int {
                serverCredits = c
            }
        }
    }

    private var profileIdentifierText: String {
        if !Self.appleLoginEnabled {
            return "本地模式"
        }
        return storedUserId.isEmpty ? "请使用下方 Apple 登录" : storedUserId
    }

    @ViewBuilder
    private var accountSummaryRows: some View {
        if !Self.appleLoginEnabled {
            LabeledContent("会员状态", value: "暂未启用")
            LabeledContent("AI 额度", value: "本地模式")
        } else {
            LabeledContent("会员状态", value: serverSubscription?.active == true ? "月会员有效" : "未开通/已过期")
            if let exp = serverSubscription?.expiresAt, !exp.isEmpty {
                LabeledContent("到期时间", value: Self.formatIsoDate(exp))
            }
            if let c = serverCredits {
                LabeledContent("今日剩余 AI 额度", value: "\(c)")
            } else if hasCloudAccessToken {
                LabeledContent("今日剩余 AI 额度", value: "轻点下方刷新")
            } else {
                LabeledContent("今日剩余 AI 额度", value: "登录并同步后显示")
            }
        }
    }

    @ViewBuilder
    private var accountSecondaryRows: some View {
        if let limit = serverSubscription?.dailyLimit {
            LabeledContent("每日 AI 额度", value: "\(limit) 点")
        }
        if serverSubscription?.reportUnlimited == true {
            LabeledContent("报告生成", value: "不限次")
        }
        if let p = serverSubscription?.monthlyPriceCNY {
            LabeledContent("会员价格", value: "¥\(p)/月")
        }
    }

    private func migrateProfileNameIfNeeded() {
        if realName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let fallback = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty {
                realName = fallback
            }
        }
    }

    private func syncAppleProfileDisplay() {
        guard Self.appleLoginEnabled else {
            signedInAppleUserID = nil
            storedUserId = ""
            KeychainStore.clearAppleUserIdentifier()
            KeychainStore.clearSafemasterAccessToken()
            serverCredits = nil
            serverSubscription = nil
            return
        }
        if let id = KeychainStore.appleUserIdentifier() {
            signedInAppleUserID = id
            storedUserId = String(id.prefix(8)).uppercased()
        } else {
            signedInAppleUserID = nil
            storedUserId = ""
            realName = ""
            displayName = "安全员"
            KeychainStore.clearSafemasterAccessToken()
            serverCredits = nil
            serverSubscription = nil
        }
    }

    private func signOutAppleSession() {
        authSessionRevision = UUID()
        KeychainStore.clearAppleUserIdentifier()
        KeychainStore.clearSafemasterAccessToken()
        signedInAppleUserID = nil
        storedUserId = ""
        realName = ""
        displayName = "安全员"
        serverCredits = nil
        serverSubscription = nil
        serverSyncMessage = "已退出登录。"
        appleSignInErrorMessage = nil
        isSyncingServer = false
        NotificationCenter.default.post(name: .appleUserSessionDidChange, object: nil)
        NotificationCenter.default.post(name: .safemasterAccessTokenDidChange, object: nil)
    }

    private func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) {
        appleSignInErrorMessage = nil
        serverSyncMessage = nil
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                appleSignInErrorMessage = "无法读取 Apple 登录信息。"
                return
            }
            guard KeychainStore.setAppleUserIdentifier(credential.user) else {
                appleSignInErrorMessage = "保存登录状态失败，请重试。"
                return
            }
            authSessionRevision = UUID()
            signedInAppleUserID = credential.user
            storedUserId = String(credential.user.prefix(8)).uppercased()
            if let name = credential.fullName {
                let formatted = PersonNameComponentsFormatter().string(from: name)
                if !formatted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    displayName = formatted
                    realName = formatted
                }
            }
            NotificationCenter.default.post(name: .appleUserSessionDidChange, object: nil)

            guard let idData = credential.identityToken,
                  let identityJWT = String(data: idData, encoding: .utf8),
                  !identityJWT.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                appleSignInErrorMessage = "未拿到 identityToken。若使用模拟器，请换真机再试。"
                return
            }
            Task {
                await signInToSafeMasterServer(identityToken: identityJWT)
            }
        case .failure(let error):
            let ns = error as NSError
            if ns.domain == ASAuthorizationError.errorDomain, ns.code == ASAuthorizationError.canceled.rawValue {
                return
            }
            appleSignInErrorMessage = error.localizedDescription
        }
    }

    private func signInToSafeMasterServer(identityToken: String) async {
        let session = authSessionRevision
        let base = SafeMasterAPIConfiguration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            serverSyncMessage = "官方服务地址未配置，请更新 App 版本或联系支持。"
            return
        }

        isSyncingServer = true
        defer {
            if authSessionRevision == session {
                isSyncingServer = false
            }
        }

        let client = SafeMasterAPIClient(baseURL: base)
        do {
            let (accessToken, account) = try await client.signInWithApple(identityToken: identityToken)
            guard authSessionRevision == session, isSignedInWithApple else { return }
            guard KeychainStore.setSafemasterAccessToken(accessToken) else {
                serverSyncMessage = "accessToken 保存失败，请重试。"
                return
            }
            serverCredits = account.remainingDailyQuota
            serverSubscription = account.subscription
            serverSyncMessage = "已与云端同步。"
            NotificationCenter.default.post(name: .safemasterAccessTokenDidChange, object: nil)
        } catch {
            guard authSessionRevision == session else { return }
            serverSyncMessage = error.localizedDescription
        }
    }

    private func refreshServerCreditsOnly() async {
        let session = authSessionRevision
        let base = SafeMasterAPIConfiguration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, isSignedInWithApple, let token = KeychainStore.safemasterAccessToken() else { return }

        isSyncingServer = true
        defer {
            if authSessionRevision == session {
                isSyncingServer = false
            }
        }

        let client = SafeMasterAPIClient(baseURL: base)
        do {
            let account = try await client.fetchMe(accessToken: token)
            guard authSessionRevision == session, KeychainStore.safemasterAccessToken() == token else { return }
            serverCredits = account.remainingDailyQuota
            serverSubscription = account.subscription
            serverSyncMessage = nil
        } catch {
            guard authSessionRevision == session else { return }
            serverSyncMessage = error.localizedDescription
        }
    }

    private func mockRenewMonthlyPlan(days: Int) async {
        let session = authSessionRevision
        let base = SafeMasterAPIConfiguration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, isSignedInWithApple, let token = KeychainStore.safemasterAccessToken() else { return }

        isSyncingServer = true
        defer {
            if authSessionRevision == session {
                isSyncingServer = false
            }
        }

        do {
            let baseTrimmed = base.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let url = URL(string: baseTrimmed + "/v1/subscription/mock/renew") else {
                throw SafeMasterAPIError.invalidBaseURL
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.httpBody = try JSONEncoder().encode(["days": max(1, days)])

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw SafeMasterAPIError.httpError((resp as? HTTPURLResponse)?.statusCode ?? -1, body)
            }
            struct RenewResp: Decodable {
                let credits: Int?
                let subscription: CloudSubscriptionSnapshot?
                let note: String?
            }
            let decoded = try JSONDecoder().decode(RenewResp.self, from: data)
            guard authSessionRevision == session, KeychainStore.safemasterAccessToken() == token else { return }
            serverCredits = decoded.credits ?? serverCredits
            serverSubscription = decoded.subscription ?? serverSubscription
            serverSyncMessage = decoded.note ?? "已续期。"
        } catch {
            guard authSessionRevision == session else { return }
            serverSyncMessage = error.localizedDescription
        }
    }

    private func purchaseMonthlyPlan() async {
        let session = authSessionRevision
        let base = SafeMasterAPIConfiguration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, isSignedInWithApple, let token = KeychainStore.safemasterAccessToken() else { return }

        isSyncingServer = true
        defer {
            if authSessionRevision == session {
                isSyncingServer = false
            }
        }

        do {
            let products = try await Product.products(for: [Self.monthlyProductID])
            guard let product = products.first else {
                throw SafeMasterAPIError.serverMessage("未找到月会员商品，请确认 Product ID 配置。")
            }

            let purchaseResult = try await product.purchase()
            switch purchaseResult {
            case .success(let verification):
                let (transaction, signedTransactionInfo) = try verifiedTransactionAndJWS(from: verification)
                let client = SafeMasterAPIClient(baseURL: base)
                let account = try await client.verifyAppleSubscription(
                    accessToken: token,
                    productId: Self.monthlyProductID,
                    signedTransactionInfo: signedTransactionInfo
                )
                guard authSessionRevision == session, KeychainStore.safemasterAccessToken() == token else { return }
                serverCredits = account.remainingDailyQuota
                serverSubscription = account.subscription
                serverSyncMessage = "购买成功，会员状态已同步云端。"
                await transaction.finish()
            case .pending:
                guard authSessionRevision == session else { return }
                serverSyncMessage = "购买请求已提交，正在等待系统确认，请稍后刷新。"
            case .userCancelled:
                guard authSessionRevision == session else { return }
                serverSyncMessage = "你已取消购买。"
            @unknown default:
                guard authSessionRevision == session else { return }
                serverSyncMessage = "购买结果未知，请稍后刷新会员状态。"
            }
        } catch {
            guard authSessionRevision == session else { return }
            serverSyncMessage = error.localizedDescription
        }
    }

    private func verifiedTransactionAndJWS(
        from result: VerificationResult<StoreKit.Transaction>
    ) throws -> (StoreKit.Transaction, String) {
        switch result {
        case .verified(let transaction):
            return (transaction, result.jwsRepresentation)
        case .unverified(_, let error):
            throw SafeMasterAPIError.serverMessage("交易校验失败：\(error.localizedDescription)")
        }
    }

    private static func formatIsoDate(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        guard let d = parser.date(from: iso) else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }
}

#Preview {
    NavigationStack {
        UserProfileView()
    }
}
