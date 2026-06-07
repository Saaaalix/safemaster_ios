//
//  HazardVoiceTranscriber.swift
//  安全大师
//

import Foundation
import Combine
import SwiftUI

#if os(iOS) || os(visionOS) || os(macOS)
import AVFoundation
import Speech
#endif
#if os(iOS) || os(visionOS)
import UIKit
#endif

/// 隐患描述等场景：按住说话式的实时听写（依赖系统语音识别与麦克风权限）。
@MainActor
final class HazardVoiceTranscriber: ObservableObject {
#if os(iOS) || os(visionOS) || os(macOS)
    @Published private(set) var isRecording = false
    @Published var lastError: String?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    /// 音频 tap 始终写入当前 request；分段 final 后换新 request 而不重装 tap。
    private let speechBufferSink = SpeechBufferSink()

    /// 已固化段落（含开始录音前输入框内容）；每段 isFinal 并入此处。
    private var committedText = ""
    /// 当前识别任务内的实时 partial，UI = committed + live。
    private var liveSegmentText = ""
    private var liveBinding: Binding<String>?
    /// 分段结束后重启识别任务时忽略 cancel 回调（216）。
    private var isRestartingRecognition = false
    /// 本次听写结束（含手动停止或识别 final）时回调最终全文。
    var onTranscriptionFinished: ((String) -> Void)?
    private var activeFieldKey: AnyHashable?
    #if os(iOS) || os(visionOS)
    private var appLifecycleObservers: [NSObjectProtocol] = []
    #endif

    init() {
        #if os(iOS) || os(visionOS)
        let center = NotificationCenter.default
        appLifecycleObservers.append(
            center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stopSessionIfNeeded()
                }
            }
        )
        appLifecycleObservers.append(
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stopSessionIfNeeded()
                }
            }
        )
        #endif
    }

    deinit {
        #if os(iOS) || os(visionOS)
        let center = NotificationCenter.default
        appLifecycleObservers.forEach { center.removeObserver($0) }
        appLifecycleObservers.removeAll()
        #endif
    }

    func isActive<FieldID: Hashable>(fieldID: FieldID) -> Bool {
        isRecording && activeFieldKey == AnyHashable(fieldID)
    }

    func toggle<FieldID: Hashable>(
        fieldID: FieldID,
        onto text: Binding<String>,
        onFinished: ((String) -> Void)? = nil
    ) async {
        if isRecording {
            if activeFieldKey == AnyHashable(fieldID) {
                stopSession()
                return
            }
            stopSession()
        }
        activeFieldKey = AnyHashable(fieldID)
        onTranscriptionFinished = onFinished
        await start(onto: text)
    }

    /// 页面消失或分析开始时调用，避免后台仍占用麦克风。
    func stopSessionIfNeeded() {
        guard isRecording else { return }
        stopSession()
    }

    private func start(onto text: Binding<String>) async {
        lastError = nil
        liveBinding = text
        committedText = text.wrappedValue
        liveSegmentText = ""

        guard let recognizer, recognizer.isAvailable else {
            lastError = "当前设备不支持或未开启中文语音识别。"
            liveBinding = nil
            return
        }

        let speechStatus = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            lastError = "请在系统设置中允许「语音识别」权限。"
            liveBinding = nil
            return
        }

        let micOK = await requestMicrophonePermission()
        guard micOK else {
            lastError = "请在系统设置中允许「麦克风」权限。"
            liveBinding = nil
            return
        }

        tearDownAudioPipeline(clearBinding: false)
        guard let recognitionRequest = makeRecognitionRequest(preferOnDevice: true) else {
            lastError = "无法创建语音识别请求。"
            liveBinding = nil
            return
        }
        self.recognitionRequest = recognitionRequest

#if os(iOS) || os(visionOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            lastError = error.localizedDescription
            liveBinding = nil
            return
        }
#endif

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        speechBufferSink.request = recognitionRequest
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak speechBufferSink] buffer, _ in
            speechBufferSink?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            lastError = error.localizedDescription
            cleanupAudioTaps()
            liveBinding = nil
            return
        }

        isRecording = true
        publishDisplayText(force: true)

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                self.handleRecognition(result: result, error: error)
            }
        }
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        guard liveBinding != nil else { return }
        if let result {
            let spoken = result.bestTranscription.formattedString
            // partial 可能回退变短，只拉长当前段，避免 live 变短拖累展示
            if spoken.count >= liveSegmentText.count || result.isFinal {
                liveSegmentText = spoken
            }
            publishDisplayText()
            if result.isFinal {
                commitFinalSegment()
                restartRecognitionAfterFinalSegment()
            }
            return
        }
        if let error {
            if isRestartingRecognition {
                let ns = error as NSError
                if ns.domain == "kAFAssistantErrorDomain" && ns.code == 216 { return }
            }
            let ns = error as NSError
            if ns.code == 216 {
                return
            }
            lastError = error.localizedDescription
            stopSession()
        }
    }

    /// isFinal：以输入框当前全文为准固化（停顿后 final 常比 partial 更短，不能信 spoken  alone）。
    private func commitFinalSegment() {
        if let binding = liveBinding {
            let uiFull = binding.wrappedValue
            if !uiFull.isEmpty, uiFull.count >= committedText.count {
                committedText = uiFull
                liveSegmentText = ""
                publishDisplayText(force: true)
                return
            }
        }
        let segmentBest = Self.longest(liveSegmentText)
        guard !segmentBest.isEmpty else {
            liveSegmentText = ""
            publishDisplayText(force: true)
            return
        }
        committedText = Self.merge(prefix: committedText, spoken: segmentBest)
        liveSegmentText = ""
        publishDisplayText(force: true)
    }

    /// 停顿触发的 isFinal 只结束当前识别任务；保留 committed 并继续听写，直到用户点结束。
    private func restartRecognitionAfterFinalSegment() {
        guard isRecording, let recognizer, recognizer.isAvailable else { return }

        isRestartingRecognition = true
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        // 重启前锁定 UI 为已固化全文，避免 cancel 与空 partial 把 binding 缩短。
        publishDisplayText(force: true)

        guard let newRequest = makeRecognitionRequest(preferOnDevice: false) else {
            isRestartingRecognition = false
            lastError = "无法继续语音识别。"
            stopSession()
            return
        }
        recognitionRequest = newRequest
        speechBufferSink.request = newRequest
        liveSegmentText = ""

        recognitionTask = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                self.handleRecognition(result: result, error: error)
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard self.isRecording else { return }
            self.isRestartingRecognition = false
        }
    }

    private func makeRecognitionRequest(preferOnDevice: Bool) -> SFSpeechAudioBufferRecognitionRequest? {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if preferOnDevice, let recognizer, recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else {
            request.requiresOnDeviceRecognition = false
        }
        return request
    }

    private func displayText() -> String {
        Self.merge(prefix: committedText, spoken: liveSegmentText)
    }

    /// 将 committed + live 同步到 binding；默认不因 partial 变短而回退。
    private func publishDisplayText(force: Bool = false) {
        guard let binding = liveBinding else { return }
        let display = displayText()
        if force || display.count >= binding.wrappedValue.count {
            binding.wrappedValue = display
        }
    }

    private static func merge(prefix: String, spoken: String) -> String {
        if spoken.isEmpty { return prefix }
        if prefix.isEmpty { return spoken }
        let needsSpace = !prefix.hasSuffix(" ") && !prefix.hasSuffix("\n") && !spoken.hasPrefix(" ")
        return prefix + (needsSpace ? " " : "") + spoken
    }

    private static func longest(_ strings: String...) -> String {
        strings.max(by: { $0.count < $1.count }) ?? ""
    }

    private func stopSession() {
        publishDisplayText(force: true)
        if liveBinding != nil {
            commitFinalSegment()
        }
        let finalText = liveBinding?.wrappedValue ?? committedText
        if finalText.count > committedText.count {
            committedText = finalText
        }
        let callback = onTranscriptionFinished
        tearDownAudioPipeline(clearBinding: true)
        onTranscriptionFinished = nil
        if !finalText.isEmpty {
            callback?(finalText)
        }
    }

    /// 结束识别任务与音频引擎；`clearBinding == false` 时保留 `liveBinding`（用于在同一次用户操作内重启引擎）。
    private func tearDownAudioPipeline(clearBinding: Bool) {
        isRestartingRecognition = false
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        speechBufferSink.request = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        cleanupAudioTaps()

#if os(iOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif

        isRecording = false
        liveSegmentText = ""
        if clearBinding {
            committedText = ""
            liveBinding = nil
            activeFieldKey = nil
        }
    }

    private func cleanupAudioTaps() {
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
    }

    private func requestMicrophonePermission() async -> Bool {
#if os(iOS) || os(visionOS)
        return await AVAudioApplication.requestRecordPermission()
#elseif os(macOS)
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { c in
                AVCaptureDevice.requestAccess(for: .audio) { c.resume(returning: $0) }
            }
        default:
            return false
        }
#else
        return false
#endif
    }

#else
    var isRecording: Bool { false }
    var lastError: String? { nil }

    func isActive<FieldID: Hashable>(fieldID _: FieldID) -> Bool { false }

    func toggle<FieldID: Hashable>(
        fieldID _: FieldID,
        onto _: Binding<String>,
        onFinished _: ((String) -> Void)? = nil
    ) async {}
    func stopSessionIfNeeded() {}
#endif
}

#if os(iOS) || os(visionOS) || os(macOS)
private final class SpeechBufferSink: @unchecked Sendable {
    weak var request: SFSpeechAudioBufferRecognitionRequest?

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }
}
#endif
