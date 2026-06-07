//
//  SitePhotoLibrarySaver.swift
//  安全大师
//

#if os(iOS)
import UIKit

/// App 内拍照默认只进 Core Data；可选同步写入系统相册便于用户留存。
enum SitePhotoLibrarySaver {
    static func saveToPhotoLibraryIfPermitted(_ image: UIImage) {
        SafetyMasterPhotoAlbumManager.saveUIImageToSafetyMasterAlbum(image) { result in
            if case .failure(let error) = result {
                print("SitePhotoLibrarySaver: failed to save photo: \(error.localizedDescription)")
            }
        }
    }

    static func saveToPhotoLibraryIfPermitted(_ data: Data, source: String) {
        SafetyMasterPhotoAlbumManager.saveImageDataInBackground(data, source: source)
    }
}
#endif
