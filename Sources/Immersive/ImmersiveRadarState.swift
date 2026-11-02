import Observation
import SwiftUI

/// App-wide state of the immersive radar (one ImmersiveSpace per app).
@MainActor
@Observable
final class ImmersiveRadarState {
    static let shared = ImmersiveRadarState()
    static let spaceID = "radar-immersive"

    var isOpen = false
    /// True while `openImmersiveSpace` is in flight (button disabled).
    var isTransitioning = false
    var mode: ImmersiveRadarMode = .table
    var roomWidthMeters: Double = ImmersiveRadarLayout.defaultRoomWidthMeters
    /// "Seguir avião": selected aircraft held at eye level, progressive immersion.
    var followSelected = false
    /// Set when the `.table` plane anchor locks onto a real table.
    var isAnchoredToTable = false
    /// Plane tracking denied / unsupported (simulator): floating fallback only.
    var planeTrackingUnavailable = false

    /// Selection for `.immersionStyle(selection:in:)`.
    var immersionStyle: any ImmersionStyle = .mixed

    var placement: ImmersiveRadarPlacement {
        ImmersiveRadarLayout.placement(mode: mode, tableAnchored: isAnchoredToTable, following: followSelected)
    }

    var scale: Float { ImmersiveRadarLayout.scale(mode: mode, roomWidthMeters: roomWidthMeters) }

    func setFollow(_ follow: Bool) {
        followSelected = follow
        immersionStyle = follow ? ProgressiveImmersionStyle.progressive : MixedImmersionStyle.mixed
    }
}
