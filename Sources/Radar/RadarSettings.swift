import Foundation

enum AircraftFilter: String, CaseIterable, Identifiable, Sendable, Equatable {
    case all = "Todas"
    case positioned = "Com posição"
    case withoutPosition = "Sem posição"
    var id: String { rawValue }
}

enum RadarMapStyle: String, CaseIterable, Identifiable, Sendable {
    case standard = "Padrão"
    case imagery = "Satélite"
    case hybrid = "Híbrido"

    var id: String { rawValue }
}

struct RadarSettings: Sendable, Equatable {
    var radiusKilometers: Double = 100
    var verticalExaggeration: Double = 1.5
    var maxPositionAgeSeconds: Double = 30
    var minimumAltitudeFeet: Double = 0
    var filter: AircraftFilter = .all
    /// Physical scale of the radar table (1 = 0.8 m). A bigger table keeps the same
    /// km-per-metre density, so it shows proportionally more range; a smaller one is
    /// a miniature of the selected range.
    var tableScale: Double = 1.0
    /// "Som espacial": short positional ping for new / selected aircraft.
    var spatialAudioEnabled: Bool = true

    /// Range actually drawn on the table: selected radius grown with a table above 1×.
    /// Never shrunk, or a small table would hide most of the traffic.
    var displayRadiusKilometers: Double { radiusKilometers * max(1, tableScale) }
}

extension RadarSettings {
    /// Horizontal radius choices offered in settings and the volume ornament.
    static let radiusOptions: [Double] = [50, 100, 200, 300]
    /// Table size multipliers; 1× is the 0.8 m base table.
    static let tableScaleOptions: [Double] = [0.25, 0.5, 1.0, 1.25, 1.5, 2.0]
    /// Physical width of the 1× table in metres.
    static let baseTableWidthMeters: Double = 0.8

    var tableWidthMeters: Double { Self.baseTableWidthMeters * tableScale }

    static func scaleLabel(_ scale: Double) -> String {
        "\(scale.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "pt_BR"))))×"
    }

    static func metersLabel(_ meters: Double) -> String {
        "\(meters.formatted(.number.precision(.fractionLength(1...2)).locale(Locale(identifier: "pt_BR")))) m"
    }
}

/// Persists the user-facing radar sizing (radius + table scale) in UserDefaults.
enum RadarSettingsPersistence {
    static let radiusKey = "radar.radiusKilometers"
    static let tableScaleKey = "radar.tableScale"
    static let spatialAudioKey = "radar.spatialAudio"

    static func save(_ settings: RadarSettings, to defaults: UserDefaults = .standard) {
        defaults.set(settings.radiusKilometers, forKey: radiusKey)
        defaults.set(settings.tableScale, forKey: tableScaleKey)
        defaults.set(settings.spatialAudioEnabled, forKey: spatialAudioKey)
    }

    /// Returns `settings` with any stored, still-valid radius / scale applied.
    static func restored(_ settings: RadarSettings, from defaults: UserDefaults = .standard) -> RadarSettings {
        var result = settings
        let radius = defaults.double(forKey: radiusKey)
        if RadarSettings.radiusOptions.contains(radius) { result.radiusKilometers = radius }
        let scale = defaults.double(forKey: tableScaleKey)
        if RadarSettings.tableScaleOptions.contains(scale) { result.tableScale = scale }
        if let audio = defaults.object(forKey: spatialAudioKey) as? Bool { result.spatialAudioEnabled = audio }
        return result
    }

    @MainActor private static var didRestore = false

    /// Restores once per process; safe to call from every radar view's onAppear.
    @MainActor static func restoreOnce(into store: FlightStore) {
        guard !didRestore else { return }
        didRestore = true
        let restored = restored(store.settings)
        if restored != store.settings { store.settings = restored }
    }
}
