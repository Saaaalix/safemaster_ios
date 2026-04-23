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

    /// 开始本次听写前输入框已有内容，听写结果追加在其后。
    private var recordingPrefix = ""
    private var liveBinding: Binding<String>?

    func toggle(onto text: Binding<String>) async {
        if isRecording {
            stopSession()
            return
        }
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
        recordingPrefix = text.wrappedValue

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
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            lastError = "无法创建语音识别请求。"
            liveBinding = nil
            return
        }
        recognitionRequest.shouldReportPartialResults = true

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
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak recognitionRequest] buffer, _ in
            recognitionRequest?.append(buffer)
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

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                self.handleRecognition(result: result, error: error)
            }
        }
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        guard let binding = liveBinding else { return }
        if let result {
            let spoken = result.bestTranscription.formattedString
            binding.wrappedValue = Self.merge(prefix: recordingPrefix, spoken: spoken)
        }
        if let error {
            let ns = error as NSError
            if ns.code == 216 {
                stopSession()
                return
            }
            lastError = error.localizedDescription
            stopSession()
            return
        }
        if result?.isFinal == true {
            stopSession()
        }
    }

    private static func merge(prefix: String, spoken: String) -> String {
        if spoken.isEmpty { return prefix }
        if prefix.isEmpty { return spoken }
        let needsSpace = !prefix.hasSuffix(" ") && !prefix.hasSuffix("\n") && !spoken.hasPrefix(" ")
        return prefix + (needsSpace ? " " : "") + spoken
    }

    private func stopSession() {
        tearDownAudioPipeline(clearBinding: true)
    }

    /// 结束识别任务与音频引擎；`clearBinding == false` 时保留 `liveBinding`（用于在同一次用户操作内重启引擎）。
    private func tearDownAudioPipeline(clearBinding: Bool) {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        cleanupAudioTaps()

#if os(iOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif

        isRecording = false
        if clearBinding {
            liveBinding = nil
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
    func toggle(onto _: Binding<String>) async {}
    func stopSessionIfNeeded() {}
#endif
}
