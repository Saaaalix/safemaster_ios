//
//  VisionImageContext.swift
//  安全大师
//
//  模型侧以文本为主，此处用系统 Vision 从照片提取 OCR 与分类，
//  再将摘要交给服务端组装的分析请求，使结论与图片内容相关。

import Foundation

#if canImport(Vision) && (canImport(UIKit) || canImport(AppKit))
import Vision
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum VisionImageContext {
    /// `supplementaryText` 用于在摘要末尾附加与用户描述相关的观察提示（如「配电」类）。
    static func summarizePhotoData(_ data: Data, supplementaryText: String = "") async -> String {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: buildSummary(data, supplementaryText: supplementaryText))
            }
        }
    }

    /// 多张现场图（至多 2 张）：各做 Vision 摘要后拼接，供云端检索与模型上下文使用。
    static func summarizePhotoDatas(_ items: [Data], supplementaryText: String = "") async -> String {
        let chunks = Array(items.filter { !$0.isEmpty }.prefix(2))
        guard !chunks.isEmpty else { return "" }
        if chunks.count == 1 {
            return await summarizePhotoData(chunks[0], supplementaryText: supplementaryText)
        }
        let first = await summarizePhotoData(chunks[0], supplementaryText: supplementaryText)
        let second = await summarizePhotoData(chunks[1], supplementaryText: supplementaryText)
        return "【照片 1】\n\(first)\n\n【照片 2】\n\(second)"
    }

    private static func buildSummary(_ data: Data, supplementaryText: String) -> String {
        guard let cg = cgImage(from: data) else {
            return "（无法解码图片，请确认格式为 JPEG/PNG。）"
        }
        var chunks: [String] = []
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])

        let ocr = VNRecognizeTextRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            let lines = observations.compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if lines.isEmpty {
                chunks.append("【OCR】照片中未识别到清晰可读文字（可能无标牌或分辨率不足）。")
            } else {
                let joined = lines.prefix(20).joined(separator: "\n")
                chunks.append("【OCR 摘录】\n\(joined)")
            }
        }
        ocr.recognitionLevel = .accurate
        ocr.recognitionLanguages = ["zh-Hans", "en-US"]

        let classify = VNClassifyImageRequest { request, _ in
            guard let observations = request.results as? [VNClassificationObservation] else { return }
            let top = observations.prefix(14).map { obs in
                "\(obs.identifier)（\(String(format: "%.0f%%", obs.confidence * 100))）"
            }
            if top.isEmpty {
                chunks.append("【场景分类】无有效分类结果。")
            } else {
                chunks.append("【场景/物体分类（Vision）】\n\(top.joined(separator: "\n"))")
            }
        }

        do {
            try handler.perform([ocr, classify])
        } catch {
            chunks.append("【Vision】分析失败：\(error.localizedDescription)")
        }

        chunks.append("""
        【画面优先（给分析模型）】请结合像素判断可见的相对位置、遮挡物、线缆敷设形态等；勿仅凭用户一两个关键词就复述无法从本张单张照片核实的制度性数据（例如多级配电是否越级、二级箱与三级箱间距 30m、开关箱与固定设备 3m 等），除非 OCR 或画面能明确体现多级箱布置关系。
        """)

        let hint = supplementaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hintLower = hint.lowercased()
        let electricalHint =
            hint.contains("电") || hint.contains("配") || hint.contains("箱") || hint.contains("缆")
                || hint.contains("闸") || hint.contains("漏保") || hintLower.contains("tn-s")
                || hintLower.contains("tns")
        if electricalHint {
            chunks.append("""
            【临电/配电类补充观察】请重点从画面推断并写入隐患与措施：配电箱（柜）与邻近金属梯、脚手架、钢筋等可导电或可攀爬物的距离与碰撞风险；箱顶或散热部位是否被帆布等遮盖影响散热与检修；电缆是否杂乱、拖地或绞绕；无法在照片中量化的数值应写「须现场实测核查」，不要编造具体米数。
            """)
        }

        return chunks.joined(separator: "\n\n")
    }

    private static func cgImage(from data: Data) -> CGImage? {
#if canImport(UIKit)
        guard let img = UIImage(data: data) else { return nil }
        return img.cgImage
#elseif canImport(AppKit)
        guard let img = NSImage(data: data) else { return nil }
        var rect = CGRect(origin: .zero, size: img.size)
        return img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
#endif
    }
}

#else

enum VisionImageContext {
    static func summarizePhotoData(_ data: Data, supplementaryText: String = "") async -> String {
        if data.isEmpty { return "" }
        return "（当前平台未启用 Vision，无法从像素提取信息；请补充文字说明或仅在支持 Vision 的设备上使用。）"
    }

    static func summarizePhotoDatas(_ items: [Data], supplementaryText: String = "") async -> String {
        let chunks = Array(items.filter { !$0.isEmpty }.prefix(2))
        guard !chunks.isEmpty else { return "" }
        if chunks.count == 1 {
            return await summarizePhotoData(chunks[0], supplementaryText: supplementaryText)
        }
        let first = await summarizePhotoData(chunks[0], supplementaryText: supplementaryText)
        let second = await summarizePhotoData(chunks[1], supplementaryText: supplementaryText)
        return "【照片 1】\n\(first)\n\n【照片 2】\n\(second)"
    }
}

#endif
