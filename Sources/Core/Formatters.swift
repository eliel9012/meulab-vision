import Foundation

/// Subconjunto de `MeuLabApp/Services/Formatters.swift` usado pelo alvo visionOS.
/// Cópia própria para compilar em Swift 6 sem editar o arquivo do iOS.
enum Formatters {
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
        // Formato fixo da API: não pode depender do calendário/região do aparelho.
        formatter.locale = Locale(identifier: "en_US_POSIX")
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

    /// O servidor grava parte das datas sem fuso, no horário local dele (Franca, SP).
    static let serverLocalDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Sao_Paulo")
        return formatter
    }()

    static let dayMonthTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter
    }()

    /// Datas ISO da API: com ou sem fração de segundo, com ou sem fuso.
    static func parseISO(_ string: String) -> Date? {
        isoDate.date(from: string) ?? isoDateNoFrac.date(from: string)
            ?? serverLocalDate.date(from: String(string.prefix(19)))
    }
}
