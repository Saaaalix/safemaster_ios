//
//  StoredImage.swift
//  安全大师
//

import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
import ImageIO
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(AppKit)
import AppKit
#endif

extension Image {
    static func fromStoredData(_ data: Data?) -> Image? {
        guard let data, !data.isEmpty else { return nil }
        #if canImport(UIKit)
        let key = data as NSData
        if let cached = StoredUIImageCache.shared.object(forKey: key) {
            return Image(uiImage: cached)
        }
        if let ui = UIImage(data: data) {
            let s = ui.size
            guard s.width > 1, s.height > 1, s.width.isFinite, s.height.isFinite else { return nil }
            StoredUIImageCache.shared.setObject(ui, forKey: key)
            return Image(uiImage: ui)
        }
        #elseif canImport(AppKit)
        let key = data as NSData
        if let cached = StoredNSImageCache.shared.object(forKey: key) {
            return Image(nsImage: cached)
        }
        if let ns = NSImage(data: data) {
            let s = ns.size
            guard s.width > 1, s.height > 1, s.width.isFinite, s.height.isFinite else { return nil }
            StoredNSImageCache.shared.setObject(ns, forKey: key)
            return Image(nsImage: ns)
        }
        #endif
        return nil
    }
}

#if canImport(UIKit)
private enum StoredUIImageCache {
    static let shared: NSCache<NSData, UIImage> = {
        let cache = NSCache<NSData, UIImage>()
        cache.countLimit = 120
        return cache
    }()
}
#endif

#if canImport(AppKit)
private enum StoredNSImageCache {
    static let shared: NSCache<NSData, NSImage> = {
        let cache = NSCache<NSData, NSImage>()
        cache.countLimit = 120
        return cache
    }()
}
#endif

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

#if canImport(UIKit)
struct EvidencePhotoStampContext {
    var projectName: String?
    var shooterName: String?
    var sceneName: String?
    var sourceName: String?
    var capturedAt: Date
    var coordinate: CLLocationCoordinate2D?
}

final class EvidenceLocationProvider: NSObject, ObservableObject {
    static let shared = EvidenceLocationProvider()

    @Published private(set) var latestLocation: CLLocation?

    private let manager = CLLocationManager()
    private var started = false

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
    }

    func start() {
        guard !started else { return }
        started = true
        manager.requestWhenInUseAuthorization()
    }

    func snapshotCoordinate() -> CLLocationCoordinate2D? {
        latestLocation?.coordinate ?? manager.location?.coordinate
    }
}

extension EvidenceLocationProvider: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        DispatchQueue.main.async { [weak self] in
            self?.latestLocation = last
        }
    }
}

extension Data {
    /// 统一收敛拍照/相册导入图片体积，降低 Core Data 存储与列表解码压力。
    static func optimizedPhotoStorageData(
        from rawData: Data?,
        maxPixel: CGFloat = 1_920,
        jpegQuality: CGFloat = 0.78,
        maxBytes: Int = 1_500_000
    ) -> Data? {
        guard let rawData, !rawData.isEmpty else { return nil }
        guard let image = downsampledUIImage(from: rawData, maxPixel: maxPixel) ?? UIImage(data: rawData) else { return rawData }
        return optimizedPhotoStorageData(
            from: image,
            maxPixel: maxPixel,
            jpegQuality: jpegQuality,
            maxBytes: maxBytes
        ) ?? rawData
    }

    static func optimizedPhotoStorageData(
        from image: UIImage,
        maxPixel: CGFloat = 1_920,
        jpegQuality: CGFloat = 0.78,
        maxBytes: Int = 1_500_000
    ) -> Data? {
        let iw = image.size.width
        let ih = image.size.height
        guard iw > 1, ih > 1, iw.isFinite, ih.isFinite else { return nil }

        let longest = Swift.max(iw, ih)
        let scale = Swift.min(1, maxPixel / longest)
        let target = CGSize(
            width: Swift.max(1, floor(iw * scale)),
            height: Swift.max(1, floor(ih * scale))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }

        var quality = Swift.min(Swift.max(jpegQuality, 0.45), 0.92)
        var jpeg = resized.jpegData(compressionQuality: quality)
        while let data = jpeg, data.count > maxBytes, quality > 0.48 {
            quality -= 0.08
            jpeg = resized.jpegData(compressionQuality: quality)
        }
        return jpeg
    }

    static func watermarkedPhotoStorageData(
        from rawData: Data?,
        context: EvidencePhotoStampContext,
        maxPixel: CGFloat = 1_920,
        jpegQuality: CGFloat = 0.78,
        maxBytes: Int = 1_500_000
    ) -> Data? {
        guard let rawData, !rawData.isEmpty else { return nil }
        guard let image = UIImage(data: rawData) else { return optimizedPhotoStorageData(from: rawData) }
        return watermarkedPhotoStorageData(
            from: image,
            context: context,
            maxPixel: maxPixel,
            jpegQuality: jpegQuality,
            maxBytes: maxBytes
        )
    }

    static func watermarkedPhotoStorageData(
        from image: UIImage,
        context: EvidencePhotoStampContext,
        maxPixel: CGFloat = 1_920,
        jpegQuality: CGFloat = 0.78,
        maxBytes: Int = 1_500_000
    ) -> Data? {
        let iw = image.size.width
        let ih = image.size.height
        guard iw > 1, ih > 1, iw.isFinite, ih.isFinite else { return nil }

        let longest = Swift.max(iw, ih)
        let scale = Swift.min(1, maxPixel / longest)
        let target = CGSize(
            width: Swift.max(1, floor(iw * scale)),
            height: Swift.max(1, floor(ih * scale))
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let stamped = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
            drawWatermark(context: context, canvasSize: target)
        }

        var quality = Swift.min(Swift.max(jpegQuality, 0.45), 0.92)
        var jpeg = stamped.jpegData(compressionQuality: quality)
        while let data = jpeg, data.count > maxBytes, quality > 0.48 {
            quality -= 0.08
            jpeg = stamped.jpegData(compressionQuality: quality)
        }
        return jpeg
    }

    private static func drawWatermark(context: EvidencePhotoStampContext, canvasSize: CGSize) {
        let horizontalPadding: CGFloat = 12
        let verticalPadding: CGFloat = 10

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = timeFormatter.string(from: context.capturedAt)

        let location = context.projectName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未填写部位"
        let shooter = EvidenceWatermarkIdentity.resolvedShooterName(preferred: context.shooterName)
        let scene = context.sceneName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "现场照片"
        let source = context.sourceName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "安全大师"

        let gpsText: String
        if let coordinate = context.coordinate {
            gpsText = String(format: "GPS %.6f, %.6f", coordinate.latitude, coordinate.longitude)
        } else {
            gpsText = "GPS 未定位"
        }

        let lines = [
            "部位: \(location) | 拍摄人: \(shooter)",
            "时间: \(timestamp) | \(gpsText)",
            "\(scene) | \(source)"
        ]

        let font = UIFont.systemFont(ofSize: Swift.max(11, canvasSize.width * 0.022), weight: .medium)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingTail

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph
        ]

        let lineHeight = ceil(font.lineHeight)
        let textHeight = lineHeight * CGFloat(lines.count)
        let boxHeight = textHeight + verticalPadding * 2
        let boxRect = CGRect(
            x: horizontalPadding,
            y: Swift.max(0, canvasSize.height - boxHeight - horizontalPadding),
            width: Swift.max(120, canvasSize.width - horizontalPadding * 2),
            height: boxHeight
        )

        let bg = UIBezierPath(roundedRect: boxRect, cornerRadius: 8)
        UIColor.black.withAlphaComponent(0.52).setFill()
        bg.fill()

        for (idx, line) in lines.enumerated() {
            let y = boxRect.minY + verticalPadding + CGFloat(idx) * lineHeight
            let drawRect = CGRect(
                x: boxRect.minX + horizontalPadding * 0.6,
                y: y,
                width: boxRect.width - horizontalPadding * 1.2,
                height: lineHeight
            )
            (line as NSString).draw(in: drawRect, withAttributes: attrs)
        }
    }

    /// 先做缩略解码，避免超大原图在内存中完整展开导致峰值抖动。
    private static func downsampledUIImage(from data: Data, maxPixel: CGFloat) -> UIImage? {
        let options: CFDictionary = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return nil
        }

        let pixelSize = Swift.max(1, Int(maxPixel))
        let thumbOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }
}

enum EvidenceWatermarkIdentity {
    private static let profileRealNameKey = "profileRealName"
    private static let profileDisplayNameKey = "profileDisplayName"

    static func currentDisplayName() -> String? {
        let realName = UserDefaults.standard.string(forKey: profileRealNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !realName.isEmpty { return realName }
        let text = UserDefaults.standard.string(forKey: profileDisplayNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    static func resolvedShooterName(preferred: String?) -> String {
        let local = preferred?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !local.isEmpty { return local }
        if let display = currentDisplayName() { return display }
        return "未设置姓名"
    }
}
#else
extension Data {
    static func optimizedPhotoStorageData(
        from rawData: Data?,
        maxPixel: CGFloat = 1_920,
        jpegQuality: CGFloat = 0.78,
        maxBytes: Int = 1_500_000
    ) -> Data? {
        rawData
    }
}
#endif
