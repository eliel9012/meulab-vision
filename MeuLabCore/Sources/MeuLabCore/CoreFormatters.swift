import Foundation

/// Formatters used by the shared models. Kept internal so they don't clash with
/// each app's own `Formatters`.
enum CoreFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter
    }()

    static let dayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE dd/MM"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter
    }()

    static let apiDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // ISO8601DateFormatter é thread-safe (Foundation), mas não declara Sendable.
    nonisolated(unsafe) static let isoDate: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) static let isoDateNoFrac: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
