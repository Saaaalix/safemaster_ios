//
//  KeychainStore.swift
//  安全大师
//

import Foundation
import Security

enum KeychainStore {
    private static let authService = "com.safemaster.app.signin"
    private static let appleUserAccount = "appleUserIdentifier"
    private static let safemasterAccessTokenAccount = "safemasterAccessToken"

    // MARK: - Sign in with Apple（`user` 稳定标识，供后续服务端绑定）

    static func appleUserIdentifier() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: authService,
            kSecAttrAccount as String: appleUserAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let s = String(data: data, encoding: .utf8)
        else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    @discardableResult
    static func setAppleUserIdentifier(_ user: String) -> Bool {
        let trimmed = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearAppleUserIdentifier()
            return true
        }
        let data = Data(trimmed.utf8)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: authService,
            kSecAttrAccount as String: appleUserAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: authService,
            kSecAttrAccount as String: appleUserAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func clearAppleUserIdentifier() {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: authService,
            kSecAttrAccount as String: appleUserAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
    }

    // MARK: - 自建 API（`POST /v1/auth/apple` 返回的 accessToken）

    static func safemasterAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: authService,
            kSecAttrAccount as String: safemasterAccessTokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let s = String(data: data, encoding: .utf8)
        else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    @discardableResult
    static func setSafemasterAccessToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearSafemasterAccessToken()
            return true
        }
        let data = Data(trimmed.utf8)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: authService,
            kSecAttrAccount as String: safemasterAccessTokenAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: authService,
            kSecAttrAccount as String: safemasterAccessTokenAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func clearSafemasterAccessToken() {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: authService,
            kSecAttrAccount as String: safemasterAccessTokenAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
    }
}

extension Notification.Name {
    static let appleUserSessionDidChange = Notification.Name("appleUserSessionDidChange")
    static let safemasterAccessTokenDidChange = Notification.Name("safemasterAccessTokenDidChange")
    /// userInfo 可含 "credits"（Int），供「我的」刷新剩余次数
    static let safemasterCreditsDidChange = Notification.Name("safemasterCreditsDidChange")
}
