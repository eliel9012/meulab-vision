import Foundation

public struct NowPlaying: Codable, Equatable, Sendable {
    public let timestamp: String
    public let streamUrl: String
    public let radioName: String
    public let rawMetadata: String?
    public let artist: String
    public let title: String
    public let album: String?
    public let artworkUrl: String?
    public let itunesUrl: String?
    public let genre: String?
    public let hasItunes: Bool

    enum CodingKeys: String, CodingKey {
        case timestamp
        case streamUrl = "stream_url"
        case radioName = "radio_name"
        case rawMetadata = "raw_metadata"
        case artist, title, album
        case artworkUrl = "artwork_url"
        case itunesUrl = "itunes_url"
        case genre
        case hasItunes = "has_itunes"
    }

    public var displayTitle: String {
        if artist == "Desconhecido" {
            return title
        }
        return "\(artist) - \(title)"
    }

    public var artworkURL: URL? {
        guard let urlString = artworkUrl else { return nil }
        return URL(string: urlString)
    }

    // Backends frequentemente mudam `timestamp` mesmo quando a musica/metadata
    // continuam as mesmas. Ignorar `timestamp` evita recomposicoes e trabalho
    // desnecessario (ex.: reload de artwork) a cada polling.
    public static func == (lhs: NowPlaying, rhs: NowPlaying) -> Bool {
        lhs.streamUrl == rhs.streamUrl && lhs.radioName == rhs.radioName
            && lhs.rawMetadata == rhs.rawMetadata && lhs.artist == rhs.artist
            && lhs.title == rhs.title && lhs.album == rhs.album && lhs.artworkUrl == rhs.artworkUrl
            && lhs.itunesUrl == rhs.itunesUrl && lhs.genre == rhs.genre
            && lhs.hasItunes == rhs.hasItunes
    }

    public init(timestamp: String, streamUrl: String, radioName: String, rawMetadata: String?, artist: String, title: String, album: String?, artworkUrl: String?, itunesUrl: String?, genre: String?, hasItunes: Bool) {
        self.timestamp = timestamp
        self.streamUrl = streamUrl
        self.radioName = radioName
        self.rawMetadata = rawMetadata
        self.artist = artist
        self.title = title
        self.album = album
        self.artworkUrl = artworkUrl
        self.itunesUrl = itunesUrl
        self.genre = genre
        self.hasItunes = hasItunes
    }
}

public struct RadioHistoryResponse: Codable, Sendable {
    public let ok: Bool?
    public let items: [NowPlaying]
    public let count: Int?

    public init(ok: Bool?, items: [NowPlaying], count: Int?) {
        self.ok = ok
        self.items = items
        self.count = count
    }
}

// MARK: - Radio Status (API2)

public struct RadioTopSong: Codable, Sendable {
    public let artist: String
    public let title: String
    public let plays: Int

    public init(artist: String, title: String, plays: Int) {
        self.artist = artist
        self.title = title
        self.plays = plays
    }
}

public struct RadioStatsData: Codable, Sendable {
    public let total: Int
    public let today: Int
    public let topSongs: [RadioTopSong]

    enum CodingKeys: String, CodingKey {
        case total, today
        case topSongs = "top_songs"
    }

    public init(total: Int, today: Int, topSongs: [RadioTopSong]) {
        self.total = total
        self.today = today
        self.topSongs = topSongs
    }
}

public struct RadioStatusResponse: Codable, Sendable {
    public let service: String
    public let radioName: String
    public let running: Bool
    public let dbPath: String?
    public let dbExists: Bool?
    public let pollIntervalSeconds: Int?
    public let duplicateWindowMinutes: Int?
    public let retentionDays: Int?
    public let lastPollAt: String?
    public let lastError: String?
    public let stats: RadioStatsData?
    public let displayName: String?

    enum CodingKeys: String, CodingKey {
        case service
        case radioName = "radio_name"
        case running
        case dbPath = "db_path"
        case dbExists = "db_exists"
        case pollIntervalSeconds = "poll_interval_seconds"
        case duplicateWindowMinutes = "duplicate_window_minutes"
        case retentionDays = "retention_days"
        case lastPollAt = "last_poll_at"
        case lastError = "last_error"
        case stats
        case displayName = "display_name"
    }

    public init(service: String, radioName: String, running: Bool, dbPath: String?, dbExists: Bool?, pollIntervalSeconds: Int?, duplicateWindowMinutes: Int?, retentionDays: Int?, lastPollAt: String?, lastError: String?, stats: RadioStatsData?, displayName: String?) {
        self.service = service
        self.radioName = radioName
        self.running = running
        self.dbPath = dbPath
        self.dbExists = dbExists
        self.pollIntervalSeconds = pollIntervalSeconds
        self.duplicateWindowMinutes = duplicateWindowMinutes
        self.retentionDays = retentionDays
        self.lastPollAt = lastPollAt
        self.lastError = lastError
        self.stats = stats
        self.displayName = displayName
    }
}

public struct RadioStatsResponse: Codable, Sendable {
    public let radioName: String
    public let total: Int
    public let today: Int
    public let topSongs: [RadioTopSong]

    enum CodingKeys: String, CodingKey {
        case radioName = "radio_name"
        case total, today
        case topSongs = "top_songs"
    }

    public init(radioName: String, total: Int, today: Int, topSongs: [RadioTopSong]) {
        self.radioName = radioName
        self.total = total
        self.today = today
        self.topSongs = topSongs
    }
}
