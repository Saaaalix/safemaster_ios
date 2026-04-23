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

    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("profileDisplayName") private var displayName: String = "安全员"
    @AppStorage("profileUserId") private var storedUserId: String = ""

    @State private var appleSignInErrorMessage: String?
    @State private var serverCredits: Int?
    @State private var serverSubscription: CloudSubscriptionSnapshot?
    @State private var serverSyncMessage: String?
    @State private var isSyncingServer = false

    private var isSignedInWithApple: Bool {
        KeychainStore.appleUserIdentifier() != nil
    }

    var body: some View {
        List {
            Section {
                Text("账号与次数由安全大师官方云端服务提供，无需也不支持在 App 内填写服务器地址。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("安全大师云端")
            }

            Section {
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
                        TextField("昵称", text: $displayName)
                            .font(.headline)
                        Text("ID：\(storedUserId.isEmpty ? "请使用下方 Apple 登录" : storedUserId)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("登录成功后，会把 Apple 的 identityToken 发给官方服务器，换取 accessToken 并保存在本机钥匙串，用于查询云端剩余次数。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if isSignedInWithApple {
                        Label("已通过 Apple 登录", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if isSyncingServer {
                            HStack {
                                ProgressView()
                                Text("正在连接云端…")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("退出 Apple 登录", role: .destructive) {
                            KeychainStore.clearAppleUserIdentifier()
                            KeychainStore.clearSafemasterAccessToken()
                            storedUserId = ""
                            serverCredits = nil
                            serverSubscription = nil
                            serverSyncMessage = nil
                            appleSignInErrorMessage = nil
                            NotificationCenter.default.post(name: .appleUserSessionDidChange, object: nil)
                        }
                    } else {
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
                Text("Apple 登录")
            }

            Section("账户") {
                if let sub = serverSubscription {
                    LabeledContent("会员状态", value: sub.active == true ? "月会员有效" : "未开通/已过期")
                    if let exp = sub.expiresAt, !exp.isEmpty {
                        LabeledContent("到期时间", value: Self.formatIsoDate(exp))
                    }
                    if let limit = sub.dailyLimit {
                        LabeledContent("每日分析上限", value: "\(limit) 次")
                    }
                    if sub.reportUnlimited == true {
                        LabeledContent("报告生成", value: "不限次")
                    }
                    if let p = sub.monthlyPriceCNY {
                        LabeledContent("会员价格", value: "¥\(p)/月")
                    }
                }
                if let c = serverCredits {
                    LabeledContent("今日剩余分析次数", value: "\(c)")
                } else if KeychainStore.safemasterAccessToken() != nil {
                    LabeledContent("今日剩余分析次数", value: "轻点下方刷新")
                } else {
                    LabeledContent("今日剩余分析次数", value: "登录并同步后显示")
                }
                Button("刷新会员与次数") {
                    Task { await refreshServerCreditsOnly() }
                }
                .disabled(KeychainStore.safemasterAccessToken() == nil || isSyncingServer)
                Button("购买月会员") {
                    Task { await purchaseMonthlyPlan() }
                }
                .disabled(KeychainStore.safemasterAccessToken() == nil || isSyncingServer)
                Button("模拟续费30天（开发联调）") {
                    Task { await mockRenewMonthlyPlan(days: 30) }
                }
                .disabled(KeychainStore.safemasterAccessToken() == nil || isSyncingServer)
            }

            Section {
                Text("当前阶段先完成规则联调：月费48元、每日20次分析、报告生成不限次。正式版本将接入 Apple 订阅与验票。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("我的")
        .inlineNavigationTitleMode()
        .onAppear {
            syncAppleProfileDisplay()
            Task { await refreshServerCreditsOnly() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .safemasterCreditsDidChange)) { note in
            if let c = note.userInfo?["credits"] as? Int {
                serverCredits = c
            }
        }
    }

    private func syncAppleProfileDisplay() {
        if let id = KeychainStore.appleUserIdentifier() {
            storedUserId = String(id.prefix(8)).uppercased()
        } else {
            storedUserId = ""
        }
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
            storedUserId = String(credential.user.prefix(8)).uppercased()
            if let name = credential.fullName {
                let formatted = PersonNameComponentsFormatter().string(from: name)
                if !formatted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    displayName = formatted
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
        let base = SafeMasterAPIConfiguration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            serverSyncMessage = "官方服务地址未配置，请更新 App 版本或联系支持。"
            return
        }

        isSyncingServer = true
        defer { isSyncingServer = false }

        let client = SafeMasterAPIClient(baseURL: base)
        do {
            let (accessToken, account) = try await client.signInWithApple(identityToken: identityToken)
            guard KeychainStore.setSafemasterAccessToken(accessToken) else {
                serverSyncMessage = "accessToken 保存失败，请重试。"
                return
            }
            serverCredits = account.remainingDailyQuota
            serverSubscription = account.subscription
            serverSyncMessage = "已与云端同步。"
            NotificationCenter.default.post(name: .safemasterAccessTokenDidChange, object: nil)
        } catch {
            serverSyncMessage = error.localizedDescription
        }
    }

    private func refreshServerCreditsOnly() async {
        let base = SafeMasterAPIConfiguration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, let token = KeychainStore.safemasterAccessToken() else { return }

        isSyncingServer = true
        defer { isSyncingServer = false }

        let client = SafeMasterAPIClient(baseURL: base)
        do {
            let account = try await client.fetchMe(accessToken: token)
            serverCredits = account.remainingDailyQuota
            serverSubscription = account.subscription
            serverSyncMessage = nil
        } catch {
            serverSyncMessage = error.localizedDescription
        }
    }

    private func mockRenewMonthlyPlan(days: Int) async {
        let base = SafeMasterAPIConfiguration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, let token = KeychainStore.safemasterAccessToken() else { return }

        isSyncingServer = true
        defer { isSyncingServer = false }

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
            serverCredits = decoded.credits ?? serverCredits
            serverSubscription = decoded.subscription ?? serverSubscription
            serverSyncMessage = decoded.note ?? "已续期。"
        } catch {
            serverSyncMessage = error.localizedDescription
        }
    }

    private func purchaseMonthlyPlan() async {
        let base = SafeMasterAPIConfiguration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, let token = KeychainStore.safemasterAccessToken() else { return }

        isSyncingServer = true
        defer { isSyncingServer = false }

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
                serverCredits = account.remainingDailyQuota
                serverSubscription = account.subscription
                serverSyncMessage = "购买成功，会员状态已同步云端。"
                await transaction.finish()
            case .pending:
                serverSyncMessage = "购买请求已提交，正在等待系统确认，请稍后刷新。"
            case .userCancelled:
                serverSyncMessage = "你已取消购买。"
            @unknown default:
                serverSyncMessage = "购买结果未知，请稍后刷新会员状态。"
            }
        } catch {
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
