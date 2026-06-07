//
//  SafetyMasterPhotoAlbumManager.swift
//  安全大师
//

#if os(iOS)
import Foundation
import Photos
import UIKit

enum SafetyMasterPhotoAlbumError: LocalizedError {
    case authorizationDenied(PHAuthorizationStatus)
    case invalidImageData
    case albumCreationFailed
    case assetCreationFailed

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "没有相册访问权限，照片未归档到系统相簿。"
        case .invalidImageData:
            return "照片数据无效，未归档到系统相簿。"
        case .albumCreationFailed:
            return "无法创建“安全大师”相簿。"
        case .assetCreationFailed:
            return "无法保存照片到“安全大师”相簿。"
        }
    }
}

struct SafetyMasterPhotoAlbumDebugReport {
    let authorizationStatus: PHAuthorizationStatus
    let albumLocalIdentifier: String
    let beforeCount: Int
    let afterCount: Int

    var didIncreasePhotoCount: Bool {
        afterCount > beforeCount
    }
}

enum SafetyMasterPhotoAlbumManager {
    static let albumName = "安全大师"
    private static let albumCoordinator = SafetyMasterPhotoAlbumCreationCoordinator()

    static func requestAuthorizationIfNeeded() async -> PHAuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                    continuation.resume(returning: newStatus)
                }
            }
        default:
            return status
        }
    }

    static func fetchOrCreateAlbum() async throws -> PHAssetCollection {
        try await albumCoordinator.fetchOrCreateAlbum()
    }

    static func saveImageDataToSafetyMasterAlbum(_ data: Data) async throws {
        guard !data.isEmpty else { return }
        guard let image = UIImage(data: data) else {
            throw SafetyMasterPhotoAlbumError.invalidImageData
        }
        try await saveUIImageToSafetyMasterAlbum(image)
    }

    static func saveUIImageToSafetyMasterAlbum(_ image: UIImage) async throws {
        let status = await requestAuthorizationIfNeeded()
        guard status == .authorized || status == .limited else {
            throw SafetyMasterPhotoAlbumError.authorizationDenied(status)
        }

        let album = try await fetchOrCreateAlbum()
        try await performPhotoLibraryChanges {
            let assetRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
            guard let placeholder = assetRequest.placeholderForCreatedAsset else {
                throw SafetyMasterPhotoAlbumError.assetCreationFailed
            }
            guard let albumRequest = PHAssetCollectionChangeRequest(for: album) else {
                throw SafetyMasterPhotoAlbumError.albumCreationFailed
            }
            albumRequest.addAssets([placeholder] as NSArray)
        }
    }

    static func saveImageDataToSafetyMasterAlbum(_ data: Data, completion: ((Result<Void, Error>) -> Void)? = nil) {
        Task {
            do {
                try await saveImageDataToSafetyMasterAlbum(data)
                completion?(.success(()))
            } catch {
                completion?(.failure(error))
            }
        }
    }

    static func saveUIImageToSafetyMasterAlbum(_ image: UIImage, completion: ((Result<Void, Error>) -> Void)? = nil) {
        Task {
            do {
                try await saveUIImageToSafetyMasterAlbum(image)
                completion?(.success(()))
            } catch {
                completion?(.failure(error))
            }
        }
    }

    static func saveImageDataInBackground(_ data: Data, source: String) {
        guard !data.isEmpty else { return }
        Task {
            do {
                try await saveImageDataToSafetyMasterAlbum(data)
            } catch {
                print("SafetyMasterPhotoAlbumManager: failed to save \(source): \(error.localizedDescription)")
            }
        }
    }

    static func debugSaveTestImageAndReport() async throws -> SafetyMasterPhotoAlbumDebugReport {
        let status = await requestAuthorizationIfNeeded()
        guard status == .authorized || status == .limited else {
            throw SafetyMasterPhotoAlbumError.authorizationDenied(status)
        }

        let album = try await fetchOrCreateAlbum()
        let before = assetCount(in: album)
        try await saveUIImageToSafetyMasterAlbum(debugTestImage())
        let refreshedAlbum = fetchAlbum(localIdentifier: album.localIdentifier) ?? album
        let after = assetCount(in: refreshedAlbum)
        return SafetyMasterPhotoAlbumDebugReport(
            authorizationStatus: status,
            albumLocalIdentifier: refreshedAlbum.localIdentifier,
            beforeCount: before,
            afterCount: after
        )
    }

    fileprivate static func fetchAlbum() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumName)
        options.fetchLimit = 1
        return PHAssetCollection
            .fetchAssetCollections(with: .album, subtype: .albumRegular, options: options)
            .firstObject
    }

    fileprivate static func fetchAlbum(localIdentifier: String) -> PHAssetCollection? {
        PHAssetCollection
            .fetchAssetCollections(withLocalIdentifiers: [localIdentifier], options: nil)
            .firstObject
    }

    fileprivate static func createAlbumIdentifier() async throws -> String {
        var placeholderIdentifier: String?
        try await performPhotoLibraryChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
            placeholderIdentifier = request.placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let placeholderIdentifier else {
            throw SafetyMasterPhotoAlbumError.albumCreationFailed
        }
        return placeholderIdentifier
    }

    fileprivate static func assetCount(in album: PHAssetCollection) -> Int {
        PHAsset.fetchAssets(in: album, options: nil).count
    }

    fileprivate static func debugTestImage() -> UIImage {
        let size = CGSize(width: 240, height: 240)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(red: 0.95, green: 0.65, blue: 0.30, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            let text = "安全大师\n相簿测试"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 28),
                .foregroundColor: UIColor.white
            ]
            let rect = CGRect(x: 24, y: 78, width: size.width - 48, height: 90)
            text.draw(in: rect, withAttributes: attributes)
        }
    }

    fileprivate static func performPhotoLibraryChanges(_ changes: @escaping () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var capturedError: Error?
            PHPhotoLibrary.shared().performChanges {
                do {
                    try changes()
                } catch {
                    capturedError = error
                }
            } completionHandler: { success, error in
                if let capturedError {
                    continuation.resume(throwing: capturedError)
                } else if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: SafetyMasterPhotoAlbumError.assetCreationFailed)
                }
            }
        }
    }
}

private actor SafetyMasterPhotoAlbumCreationCoordinator {
    private var cachedAlbumIdentifier: String?
    private var creationTask: Task<String, Error>?

    func fetchOrCreateAlbum() async throws -> PHAssetCollection {
        if let cachedAlbumIdentifier,
           let cached = SafetyMasterPhotoAlbumManager.fetchAlbum(localIdentifier: cachedAlbumIdentifier) {
            return cached
        }

        if let existing = SafetyMasterPhotoAlbumManager.fetchAlbum() {
            cachedAlbumIdentifier = existing.localIdentifier
            return existing
        }

        if let creationTask {
            let identifier = try await creationTask.value
            if let created = SafetyMasterPhotoAlbumManager.fetchAlbum(localIdentifier: identifier) {
                cachedAlbumIdentifier = identifier
                return created
            }
            if let existing = SafetyMasterPhotoAlbumManager.fetchAlbum() {
                cachedAlbumIdentifier = existing.localIdentifier
                return existing
            }
            throw SafetyMasterPhotoAlbumError.albumCreationFailed
        }

        let task = Task {
            try await SafetyMasterPhotoAlbumManager.createAlbumIdentifier()
        }
        creationTask = task
        do {
            let identifier = try await task.value
            creationTask = nil
            if let created = SafetyMasterPhotoAlbumManager.fetchAlbum(localIdentifier: identifier) {
                cachedAlbumIdentifier = identifier
                return created
            }
            if let existing = SafetyMasterPhotoAlbumManager.fetchAlbum() {
                cachedAlbumIdentifier = existing.localIdentifier
                return existing
            }
            throw SafetyMasterPhotoAlbumError.albumCreationFailed
        } catch {
            creationTask = nil
            throw error
        }
    }
}
#endif
