//
//  RecordingWaveformView.swift
//  安全大师
//

import SwiftUI

/// 语音听写时的呼吸圆环 + 声波动效条。
struct RecordingWaveformView: View {
    let tint: Color

    @State private var phase = false

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(phase ? 0.05 : 0.22), lineWidth: 1.5)
                    .frame(width: phase ? 36 : 18, height: phase ? 36 : 18)
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 38, height: 24)

            ForEach(0..<18, id: \.self) { index in
                Capsule()
                    .fill(tint.opacity(0.25 + Double(index % 4) * 0.14))
                    .frame(width: 3, height: phase ? CGFloat(8 + (index % 5) * 5) : CGFloat(20 - (index % 5) * 2))
                    .animation(
                        .easeInOut(duration: 0.75)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.035),
                        value: phase
                    )
            }

            Text("正在听写")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.10), in: Capsule())
        .onAppear { phase = true }
        .onDisappear { phase = false }
    }
}
