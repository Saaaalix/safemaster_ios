//
//  AnalysisErrorMessages.swift
//  安全大师
//

import Foundation

/// 将云端分析链路上的错误统一为简短、可操作的中文提示（避免直接展示英文或 raw body）。
enum AnalysisErrorMessages {
    static func localizedUserMessage(for error: Error) -> String {
        if error is CancellationError {
            return "已取消。"
        }

        if let e = error as? HazardAnalysisError {
            switch e {
            case .missingInput:
                return e.errorDescription ?? "请先填写隐患描述。"
            case .cloudCredits(let msg):
                return msg
            case .network(let msg):
                return polishNetworkFragment(msg)
            case .apiStatus(let code, let msg):
                return httpStatusUserMessage(statusCode: code, serverDetail: msg)
            case .emptyModelReply, .jsonDecodeFailed:
                return e.errorDescription ?? "请稍后重试。"
            }
        }

        if let e = error as? SafeMasterAPIError {
            return mapSafeMasterAPIError(e)
        }

        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return urlErrorUserMessage(code: ns.code)
        }

        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return "请求失败，请检查网络后重试，或使用「无网先记录」。"
        }
        return text
    }

    // MARK: - Private

    private static func mapSafeMasterAPIError(_ e: SafeMasterAPIError) -> String {
        switch e {
        case .invalidBaseURL:
            return "服务地址无效，请更新 App 或联系支持。"
        case .httpError(let code, let body):
            return httpStatusUserMessage(statusCode: code, serverDetail: body)
        case .serverMessage(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "服务器返回异常，请稍后重试。" : t
        case .decoding:
            return "无法解析服务器返回，请稍后重试。"
        case .insufficientCredits(let remaining):
            if let remaining, remaining <= 0 {
                return "今日分析次数已用完。请在「我的」查看会员与每日额度，或明日再试。"
            }
            if let remaining {
                return "今日分析次数不足（当前约剩 \(remaining) 次）。请在「我的」刷新次数或检查会员状态。"
            }
            return "今日分析次数不足，请在「我的」查看或稍后再试。"
        case .cloudSessionMissing:
            return "请先在「我的」使用 Apple 登录完成同步，再使用云端分析。"
        }
    }

    private static func httpStatusUserMessage(statusCode: Int, serverDetail: String?) -> String {
        let detail = serverDetail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch statusCode {
        case 401:
            return "登录已失效，请在「我的」重新完成 Apple 登录后再试。"
        case 402:
            return "今日分析次数不足，请在「我的」刷新次数或检查会员状态。"
        case 403:
            return "没有权限执行该操作，请确认账号状态或联系管理员。"
        case 404:
            return "服务接口不存在，请更新 App 或联系支持。"
        case 408, 504:
            return "请求超时，请稍后重试；弱网环境可先使用「无网先记录」。"
        case 429:
            return "请求过于频繁，请稍后再试。"
        case 500 ... 599:
            return "服务暂时不可用（\(statusCode)），请稍后再试或使用「无网先记录」。"
        default:
            if !detail.isEmpty, detail.count < 200 {
                return "请求失败（\(statusCode)）：\(detail)"
            }
            return "请求失败（HTTP \(statusCode)），请稍后重试。"
        }
    }

    private static func urlErrorUserMessage(code: Int) -> String {
        switch code {
        case NSURLErrorTimedOut:
            return "连接超时，请检查网络或稍后再试；隧道等弱网可先点「无网先记录」。"
        case NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed:
            return "当前无可用网络，请连接网络后再试，或直接使用「无网先记录」保存现场。"
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
            return "无法连接服务器，请检查网络或稍后再试。"
        case NSURLErrorNetworkConnectionLost:
            return "网络中断，请重试；若持续失败可先「无网先记录」。"
        case NSURLErrorCancelled:
            return "已取消。"
        default:
            return "网络异常（\(code)），请重试或使用「无网先记录」。"
        }
    }

    /// 处理 `HazardAnalysisError.network` 中可能夹带的英文系统错误描述。
    private static func polishNetworkFragment(_ msg: String) -> String {
        let prefix = "请求分析服务失败："
        guard msg.hasPrefix(prefix) else { return msg }
        let tail = String(msg.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        if tail.isEmpty {
            return "请求分析服务失败，请检查网络后重试。"
        }
        let low = tail.lowercased()
        if low.contains("timed out") || low.contains("time-out") || low.contains("timeout") {
            return urlErrorUserMessage(code: NSURLErrorTimedOut)
        }
        if low.contains("not connected") || low.contains("internet connection") || low.contains("offline") {
            return urlErrorUserMessage(code: NSURLErrorNotConnectedToInternet)
        }
        if low.contains("could not connect") || low.contains("failed to connect") || low.contains("connection refused") {
            return urlErrorUserMessage(code: NSURLErrorCannotConnectToHost)
        }
        if tail.range(of: "[\\u4e00-\\u9fff]", options: .regularExpression) != nil {
            return tail
        }
        return "请求分析服务失败，请检查网络后重试，或使用「无网先记录」。"
    }
}

