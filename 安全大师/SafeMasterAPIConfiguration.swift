//
//  SafeMasterAPIConfiguration.swift
//  安全大师
//

import Foundation

enum SafeMasterAPIConfiguration {
    /// 线上 API 根地址（发版 / Release 使用）。
    private static let productionBaseURL = "http://111.229.218.215:3000"

    #if DEBUG
    /// 仅调试：改为 Mac 的局域网地址，例如 `http://192.168.1.5:3000`（与 Mac 同 Wi‑Fi）。
    /// 真机可连本机 `node index.js`；不需要时保持 `nil`，将请求线上 `productionBaseURL`。
    /// 在终端执行 `ipconfig getifaddr en0` 可查看本机常见 Wi‑Fi IP。
    private static let debugLocalBaseURL: String? = nil
    #endif

    static var baseURL: String {
        #if DEBUG
        if let s = debugLocalBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return s
        }
        #endif
        return productionBaseURL
    }
}
