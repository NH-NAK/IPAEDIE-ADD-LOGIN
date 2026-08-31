import Foundation

#if canImport(UIKit)
import Combine
import ImageIO
import UIKit
#endif

enum RepositoryDownloadDurationFormatter {
    static func string(elapsedSeconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(elapsedSeconds.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct RepositoryPreviewSize: Equatable {
    let width: Double
    let height: Double
}

enum RepositoryPreviewLayout {
    static func fittedSize(
        pixelWidth: Double,
        pixelHeight: Double,
        maximumWidth: Double,
        maximumHeight: Double
    ) -> RepositoryPreviewSize {
        guard pixelWidth.isFinite,
              pixelHeight.isFinite,
              maximumWidth.isFinite,
              maximumHeight.isFinite,
              pixelWidth > 0,
              pixelHeight > 0,
              maximumWidth > 0,
              maximumHeight > 0 else {
            return RepositoryPreviewSize(
                width: max(0, maximumWidth),
                height: max(0, maximumHeight)
            )
        }
        let scale = min(
            maximumWidth / pixelWidth,
            maximumHeight / pixelHeight
        )
        return RepositoryPreviewSize(
            width: pixelWidth * scale,
            height: pixelHeight * scale
        )
    }
}

#if canImport(UIKit)
private enum RepositoryImagePipelineError: Error {
    case invalidResponse
    case imageTooLarge
    case decodeFailed
}

private final class RepositoryImageRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              (try? PackageRepositoryURLPolicy.validate(url)) != nil else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

actor RepositoryImagePipeline {
    static let shared = RepositoryImagePipeline()

    private static let maximumImageBytes = 32 * 1_024 * 1_024
    private let decodedCache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private var inFlight: [String: Task<UIImage, Error>] = [:]
    private var dataInFlight: [URL: Task<Data, Error>] = [:]

    private init() {
        let responseCache = URLCache(
            memoryCapacity: 48 * 1_024 * 1_024,
            diskCapacity: 256 * 1_024 * 1_024,
            diskPath: "repository-images"
        )
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = responseCache
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        session = URLSession(
            configuration: configuration,
            delegate: RepositoryImageRedirectDelegate(),
            delegateQueue: nil
        )
        decodedCache.totalCostLimit = 64 * 1_024 * 1_024
    }

    func image(for rawURL: URL, maximumPixelSize: CGFloat) async throws -> UIImage {
        let url = try PackageRepositoryURLPolicy.validate(rawURL)
        let pixelSize = max(80, min(Int(maximumPixelSize.rounded(.up)), 2_048))
        let cacheKey = "\(url.absoluteString)#\(pixelSize)"
        if let cached = decodedCache.object(forKey: cacheKey as NSString) {
            return cached
        }
        if let existing = inFlight[cacheKey] {
            return try await existing.value
        }

        let task = Task<UIImage, Error> {
            let data = try await self.data(for: url)
            return try Self.downsample(data, maximumPixelSize: pixelSize)
        }
        inFlight[cacheKey] = task

        do {
            let image = try await task.value
            decodedCache.setObject(
                image,
                forKey: cacheKey as NSString,
                cost: image.memoryCost
            )
            inFlight[cacheKey] = nil
            return image
        } catch {
            inFlight[cacheKey] = nil
            throw error
        }
    }

    private func data(for url: URL) async throws -> Data {
        if let existing = dataInFlight[url] {
            return try await existing.value
        }

        let session = session
        let task = Task<Data, Error> {
            var downloadError: Error?
            
            // Helper to append token query parameter
            func appendToken(to rawURL: URL) -> URL {
                guard let token = UserDefaults.standard.string(forKey: "download_token"), !token.isEmpty else {
                    return rawURL
                }
                guard var components = URLComponents(url: rawURL, resolvingAgainstBaseURL: false) else {
                    return rawURL
                }
                var queryItems = components.queryItems ?? []
                queryItems.append(URLQueryItem(name: "token", value: token))
                components.queryItems = queryItems
                return components.url ?? rawURL
            }
            
            // 1. Try primary URL download
            do {
                let targetURL = appendToken(to: url)
                var request = URLRequest(url: targetURL)
                request.cachePolicy = .useProtocolCachePolicy
                request.setValue("3105", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: request)
                if let response = response as? HTTPURLResponse,
                   (200..<300).contains(response.statusCode),
                   response.mimeType?.hasPrefix("image/") == true,
                   data.count <= Self.maximumImageBytes {
                    return data
                }
                downloadError = RepositoryImagePipelineError.invalidResponse
            } catch {
                downloadError = error
            }
            
            // 2. Try fallback URL download
            let primaryStr = url.absoluteString
            let fallbackStr = primaryStr.contains("server-key-3105.onrender.com")
                ? primaryStr.replacingOccurrences(of: "server-key-3105.onrender.com", with: "server-key-3105-oiaa.onrender.com")
                : primaryStr.replacingOccurrences(of: "server-key-3105-oiaa.onrender.com", with: "server-key-3105.onrender.com")
                
            if let fallbackURL = URL(string: fallbackStr) {
                do {
                    let targetURL = appendToken(to: fallbackURL)
                    var request = URLRequest(url: targetURL)
                    request.cachePolicy = .useProtocolCachePolicy
                    request.setValue("3105", forHTTPHeaderField: "User-Agent")
                    let (data, response) = try await session.data(for: request)
                    if let response = response as? HTTPURLResponse,
                       (200..<300).contains(response.statusCode),
                       response.mimeType?.hasPrefix("image/") == true,
                       data.count <= Self.maximumImageBytes {
                        return data
                    }
                } catch {
                    downloadError = error
                }
            }
            
            throw downloadError ?? RepositoryImagePipelineError.invalidResponse
        }
        dataInFlight[url] = task

        do {
            let data = try await task.value
            dataInFlight[url] = nil
            return data
        } catch {
            dataInFlight[url] = nil
            throw error
        }
    }

    private static func downsample(
        _ data: Data,
        maximumPixelSize: Int
    ) throws -> UIImage {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            sourceOptions
        ) else {
            throw RepositoryImagePipelineError.decodeFailed
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions
        ) else {
            throw RepositoryImagePipelineError.decodeFailed
        }
        return UIImage(cgImage: thumbnail)
    }
}

@MainActor
final class RepositoryImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var isLoading = false
    @Published private(set) var didFail = false

    private var requestKey: String?

    func load(url: URL, maximumPixelSize: CGFloat) async {
        let key = "\(url.absoluteString)#\(maximumPixelSize)"
        guard requestKey != key || (image == nil && !isLoading) else { return }

        requestKey = key
        image = nil
        didFail = false
        isLoading = true
        defer {
            if requestKey == key { isLoading = false }
        }

        do {
            let loadedImage = try await RepositoryImagePipeline.shared.image(
                for: url,
                maximumPixelSize: maximumPixelSize
            )
            guard !Task.isCancelled, requestKey == key else { return }
            image = loadedImage
        } catch is CancellationError {
            return
        } catch {
            guard requestKey == key else { return }
            didFail = true
        }
    }
}

private extension UIImage {
    var memoryCost: Int {
        guard let cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
#endif
