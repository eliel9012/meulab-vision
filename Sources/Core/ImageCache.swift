import Foundation
import SwiftUI

/// Sessão dedicada às imagens remotas (fotos PlaneSpotters, artwork da rádio,
/// ícones de clima) com `URLCache` em disco, separada do `URLCache.shared`
/// usado pela API do MeuLab.
enum VisionImageCache {
    static let memoryCapacity = 16 * 1024 * 1024
    static let diskCapacity = 100 * 1024 * 1024
    static let directoryName = "VisionImageCache"
    static let requestTimeout: TimeInterval = 20

    static var directory: URL {
        URL.cachesDirectory.appending(path: directoryName, directoryHint: .isDirectory)
    }

    static func makeCache(directory: URL = directory) -> URLCache {
        URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, directory: directory)
    }

    static func makeConfiguration(cache: URLCache = makeCache()) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        // Respeita Cache-Control/ETag do servidor; sem cabeçalhos, URLCache usa heurística.
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 4
        return configuration
    }

    /// Sessão única compartilhada (URLSession é Sendable).
    static let session = URLSession(configuration: makeConfiguration())
}

extension View {
    /// Faz os `AsyncImage` descendentes usarem a sessão com cache em disco.
    func visionImageCache() -> some View {
        asyncImageURLSession(VisionImageCache.session)
    }
}
