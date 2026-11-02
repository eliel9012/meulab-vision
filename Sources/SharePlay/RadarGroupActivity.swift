import CoreTransferable
import Foundation
import GroupActivities

/// SharePlay activity "Radar MeuLab": shared selection + table transform of the radar volume.
/// `Transferable` (default `GroupActivity` representation) so `ShareLink` can start it.
struct RadarGroupActivity: GroupActivity, Transferable {
    static let activityIdentifier = "fun.meulab.vision.radar"

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.title = "Radar MeuLab"
        metadata.subtitle = "Aeronaves ao vivo em 3D"
        metadata.type = .exploreTogether
        // `.default`: the session joins the scene that started it (the radar volume,
        // where the share button lives). Switch to `.content("radar-volume")` once the
        // volume WindowGroup declares `.handlesExternalEvents(matching: ["radar-volume"])`.
        metadata.sceneAssociationBehavior = .default
        return metadata
    }
}
