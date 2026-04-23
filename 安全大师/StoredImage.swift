//
//  StoredImage.swift
//  安全大师
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

extension Image {
    static func fromStoredData(_ data: Data?) -> Image? {
        guard let data, !data.isEmpty else { return nil }
        #if canImport(UIKit)
        if let ui = UIImage(data: data) {
            let s = ui.size
            guard s.width > 1, s.height > 1, s.width.isFinite, s.height.isFinite else { return nil }
            return Image(uiImage: ui)
        }
        #elseif canImport(AppKit)
        if let ns = NSImage(data: data) {
            let s = ns.size
            guard s.width > 1, s.height > 1, s.width.isFinite, s.height.isFinite else { return nil }
            return Image(nsImage: ns)
        }
        #endif
        return nil
    }
}
