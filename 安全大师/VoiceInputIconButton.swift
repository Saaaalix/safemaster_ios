//
//  VoiceInputIconButton.swift
//  安全大师
//

import SwiftUI

/// 文本框旁紧凑麦克风按钮；`isRecordingForThisField` 为真时红色脉冲表示正在向该字段听写。
struct VoiceInputIconButton: View {
    let isRecordingForThisField: Bool
    var isDisabled: Bool = false
    var accessibilityLabel: String = "语音输入"
    let action: () -> Void

    private static let productivityAccent = Color(red: 0.95, green: 0.65, blue: 0.3)

    var body: some View {
        Button(action: action) {
            Image(systemName: isRecordingForThisField ? "stop.fill" : "mic.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(isRecordingForThisField ? Color.red : Self.productivityAccent)
                .symbolEffect(.pulse, isActive: isRecordingForThisField)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecordingForThisField ? "停止语音输入" : accessibilityLabel)
        .disabled(isDisabled)
    }
}
