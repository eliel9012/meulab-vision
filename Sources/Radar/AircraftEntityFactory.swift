import Foundation
import RealityKit
import UIKit
import simd

/// Material slot of the merged aircraft mesh. Raw value == material index.
enum AircraftMaterialSlot: Int, CaseIterable, Sendable {
    case paint, glass, motor, intake, flap, lightRed, lightGreen
}

/// Procedural aircraft silhouettes, merged into one multi-part mesh per variant.
/// Pure geometry (no RealityKit state) so it can be unit tested. Forward is -Z.
enum AircraftGeometry {
    static func detailed(propeller prop: Bool) -> [RadarMeshBatch] {
        var slots = Array(repeating: RadarMeshBatch(), count: AircraftMaterialSlot.allCases.count)
        func add(_ slot: AircraftMaterialSlot, _ build: (inout RadarMeshBatch) -> Void) {
            build(&slots[slot.rawValue])
        }
        typealias Place = RadarMeshBatch.Placement
        let cylinder = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        let nose = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])

        add(.paint) {
            $0.addCylinder(height: prop ? 0.046 : 0.054, radius: prop ? 0.005 : 0.0045,
                           Place(rotation: cylinder))
            $0.addCone(height: prop ? 0.011 : 0.015, radius: prop ? 0.005 : 0.0045,
                       Place(translation: [0, 0, prop ? -0.028 : -0.034], rotation: nose))
            $0.addCone(height: 0.012, radius: 0.0043,
                       Place(translation: [0, 0, prop ? 0.028 : 0.031], rotation: cylinder))
            $0.addBox(size: [0.0018, 0.016, 0.012],
                      Place(translation: [0, 0.009, prop ? 0.025 : 0.027],
                            rotation: simd_quatf(angle: -0.22, axis: [1, 0, 0])))
        }
        add(.glass) {
            $0.addSphere(radius: 0.0043, Place(translation: [0, 0.003, prop ? -0.024 : -0.027],
                                               scale: [1, 0.42, prop ? 1.35 : 1.7]))
        }
        add(.lightRed) { $0.addSphere(radius: 0.0018, rings: 4, segments: 6, Place(translation: [0, 0.006, 0.008])) }

        for side: Float in [-1, 1] {
            add(.paint) {
                $0.addSlab(outline: wingOutline(prop: prop, tail: false).map { [side * $0.x, $0.y] },
                           halfThickness: 0.0012)
                $0.addSlab(outline: wingOutline(prop: prop, tail: true).map { [side * $0.x, $0.y] },
                           halfThickness: 0.0008)
                if !prop {
                    $0.addBox(size: [0.0012, 0.006, 0.003], Place(translation: [side * 0.040, 0.004, 0.006]))
                }
            }
            let engineX = side * (prop ? 0.017 : 0.015)
            let engineY: Float = prop ? 0 : -0.004
            let engineZ: Float = prop ? -0.014 : 0.003
            add(.motor) {
                $0.addCylinder(height: prop ? 0.013 : 0.016, radius: prop ? 0.004 : 0.0036,
                               Place(translation: [engineX, engineY, engineZ], rotation: cylinder))
                guard prop else { return }
                for angle in [Float(0), .pi / 2, .pi, 3 * .pi / 2] {
                    $0.addBox(size: [0.0011, 0.010, 0.0006],
                              Place(translation: [engineX + sin(angle) * 0.005, engineY + cos(angle) * 0.005,
                                                  engineZ - 0.011],
                                    rotation: simd_quatf(angle: angle, axis: [0, 0, 1])))
                }
            }
            add(.intake) {
                $0.addSphere(radius: 0.002, rings: 4, segments: 8,
                             Place(translation: [engineX, engineY, engineZ - (prop ? 0.008 : 0.010)]))
            }
            add(side < 0 ? .lightRed : .lightGreen) {
                $0.addSphere(radius: 0.0018, rings: 4, segments: 6,
                             Place(translation: [side * (prop ? 0.043 : 0.041), 0.002, prop ? -0.009 : 0.006]))
            }
            add(.flap) {
                $0.addBox(size: [0.023, 0.0007, 0.0015],
                          Place(translation: [side * 0.024, 0.001, prop ? 0.001 : 0.009],
                                rotation: simd_quatf(angle: side * (prop ? -0.09 : 0.22), axis: [0, 1, 0])))
            }
            // Cabin windows stay dark when the paint changes with selection or age.
            add(.glass) {
                for row in 0..<5 {
                    $0.addSphere(radius: 0.00115, rings: 3, segments: 6,
                                 Place(translation: [side * (prop ? 0.0048 : 0.0043), 0.0019,
                                                     -0.016 + Float(row) * 0.008]))
                }
            }
        }
        return slots
    }

    /// Far-away silhouette: a dozen boxes in the paint slot only.
    static func lowDetail(propeller prop: Bool) -> [RadarMeshBatch] {
        var paint = RadarMeshBatch()
        paint.addBox(size: [0.009, 0.009, prop ? 0.062 : 0.074])
        paint.addBox(size: [0.084, 0.0024, prop ? 0.012 : 0.014], .init(translation: [0, 0, prop ? -0.008 : 0.0]))
        paint.addBox(size: [0.040, 0.0016, 0.010], .init(translation: [0, 0, prop ? 0.027 : 0.028]))
        paint.addBox(size: [0.0018, 0.016, 0.012], .init(translation: [0, 0.009, prop ? 0.025 : 0.027]))
        return [paint]
    }

    static func wingOutline(prop: Bool, tail: Bool) -> [SIMD2<Float>] {
        if tail { return [[0.002, 0.020], [0.002, 0.033], [0.021, 0.033], [0.021, 0.028]] }
        if prop { return [[0.003, -0.018], [0.003, 0.006], [0.043, -0.005], [0.043, -0.013]] }
        return [[0.003, -0.014], [0.003, 0.012], [0.041, 0.009], [0.041, 0.003]]
    }

    static func isPropellerAircraft(_ type: String?) -> Bool {
        guard let type = type?.uppercased() else { return false }
        return ["C1", "C2", "C3", "BE", "PA", "PC", "AT", "DH8", "E12", "SF3"].contains { type.hasPrefix($0) }
    }
}

/// Builds aircraft entities: root (input, collision, hover, a11y, motion) with
/// two LOD children sharing cached merged meshes, plus a stem line.
@MainActor
final class AircraftEntityFactory {
    static let namePrefix = "flight:"
    static let detailName = "aircraft-detail"
    static let lowName = "aircraft-low"
    static let stemName = "aircraft-stem"
    /// Detailed mesh until this camera distance (metres), silhouette beyond.
    static let detailDistance: Float = 1.5

    private var meshes: [String: MeshResource] = [:]
    private let stemMesh = MeshResource.generateBox(size: [0.0015, 1, 0.0015])

    private static func paint(_ color: UIColor) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.metallic = 0.65
        material.roughness = 0.32
        return material
    }

    private let regular = paint(UIColor(red: 0.27, green: 0.68, blue: 1, alpha: 1))
    private let aging = paint(.systemOrange)
    private let active = paint(.cyan)
    private lazy var detailMaterials: [any Material] = AircraftMaterialSlot.allCases.map { Self.material(for: $0) }

    static func material(for slot: AircraftMaterialSlot) -> any Material {
        var material = PhysicallyBasedMaterial()
        switch slot {
        case .paint:
            return paint(UIColor(red: 0.27, green: 0.68, blue: 1, alpha: 1))
        case .glass:
            material.baseColor = .init(tint: UIColor(red: 0.04, green: 0.14, blue: 0.22, alpha: 1))
            material.metallic = 0.2
            material.roughness = 0.05
            material.clearcoat = .init(floatLiteral: 1)
        case .motor:
            material.baseColor = .init(tint: .darkGray)
            material.metallic = 0.85
            material.roughness = 0.45
        case .intake:
            material.baseColor = .init(tint: .black)
            material.roughness = 0.9
        case .flap:
            material.baseColor = .init(tint: UIColor(red: 0.12, green: 0.28, blue: 0.38, alpha: 1))
            material.metallic = 0.5
            material.roughness = 0.4
        case .lightRed, .lightGreen:
            let color: UIColor = slot == .lightRed ? .systemRed : .systemGreen
            material.baseColor = .init(tint: color)
            material.emissiveColor = .init(color: color)
            material.emissiveIntensity = 2
        }
        return material
    }

    func make(aircraft: Aircraft) -> Entity {
        let prop = AircraftGeometry.isPropellerAircraft(aircraft.aircraftType)
        let root = Entity()
        root.name = Self.namePrefix + aircraft.hex

        let detail = ModelEntity(mesh: mesh(prop: prop, low: false), materials: detailMaterials)
        detail.name = Self.detailName
        let low = ModelEntity(mesh: mesh(prop: prop, low: true), materials: [regular])
        low.name = Self.lowName
        for model in [detail, low] {
            model.components.set(GroundingShadowComponent(castsShadow: true, receivesShadow: false))
            root.addChild(model)
        }
        let stem = ModelEntity(mesh: stemMesh, materials: [RadarMaterials.stemNormal])
        stem.name = Self.stemName
        root.addChild(stem)

        LevelOfDetailComponent.addByCameraDistance(to: root, levels: [
            (entities: [detail], maxDistance: Self.detailDistance),
            (entities: [low], maxDistance: .greatestFiniteMagnitude)
        ])
        Self.applyThermalState(ProcessInfo.processInfo.thermalState, to: root)

        root.components.set(InputTargetComponent())
        applyHitShape(to: root)
        root.components.set(HoverEffectComponent(.highlight(.default)))
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.systemActions = [.activate]
        root.components.set(accessibility)
        updateAccessibility(root, aircraft: aircraft)
        return root
    }

    /// Grows the tap target only, so aircraft stay selectable on a small table.
    var hitScale: Float = 1

    func applyHitShape(to root: Entity) {
        let size = SIMD3<Float>(0.09, 0.035, 0.08) * hitScale
        root.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
    }

    /// Hot device: pin the cheap silhouette regardless of distance.
    static func applyThermalState(_ state: ProcessInfo.ThermalState, to root: Entity) {
        guard var lod = root.components[LevelOfDetailComponent.self] else { return }
        let hot = state == .serious || state == .critical
        lod.levelSelection = hot ? .fixed(1) : .automatic
        root.components.set(lod)
    }

    func restyle(_ root: Entity, selected: Bool, aging: Bool) {
        let state = RadarMarkerState(selected: selected, aging: aging)
        let material = selected ? active : (aging ? self.aging : regular)
        if let detail = root.findEntity(named: Self.detailName) as? ModelEntity,
           var materials = detail.model?.materials, !materials.isEmpty {
            materials[AircraftMaterialSlot.paint.rawValue] = material
            detail.model?.materials = materials
        }
        (root.findEntity(named: Self.lowName) as? ModelEntity)?.model?.materials = [material]
        (root.findEntity(named: Self.stemName) as? ModelEntity)?.model?.materials = [RadarMaterials.stem(state)]
        root.scale = SIMD3<Float>(repeating: selected ? 1.4 : 1.15)
    }

    /// Writes label/value only when the spoken text changes.
    func updateAccessibility(_ root: Entity, aircraft: Aircraft) {
        guard var component = root.components[AccessibilityComponent.self] else { return }
        let text = Self.accessibilityText(for: aircraft)
        guard component.label.map(String.init(localized:)) != text.label
                || component.value.map(String.init(localized:)) != text.value else { return }
        component.label = LocalizedStringResource(stringLiteral: text.label)
        component.value = LocalizedStringResource(stringLiteral: text.value)
        root.components.set(component)
    }

    nonisolated static func accessibilityText(for aircraft: Aircraft) -> (label: String, value: String) {
        let callsign = aircraft.callsign.trimmingCharacters(in: .whitespaces)
        let label = callsign.isEmpty ? aircraft.hex.uppercased() : callsign
        var parts: [String] = []
        if let altitude = aircraft.altitudeMeters {
            parts.append("altitude \(Int((altitude / 0.3048).rounded())) pés")
        }
        if let speed = aircraft.speedKnots { parts.append("velocidade \(Int(speed.rounded())) nós") }
        if let track = aircraft.trackDegrees { parts.append("rumo \(Int(track.rounded())) graus") }
        return (label, parts.joined(separator: ", "))
    }

    /// Hex of the aircraft owning `entity` (itself or any ancestor named `flight:<hex>`).
    static func hex(for entity: Entity) -> String? {
        var current: Entity? = entity
        while let node = current {
            if node.name.hasPrefix(namePrefix) { return String(node.name.dropFirst(namePrefix.count)) }
            current = node.parent
        }
        return nil
    }

    private func mesh(prop: Bool, low: Bool) -> MeshResource {
        let key = "\(prop)-\(low)"
        if let cached = meshes[key] { return cached }
        let batches = low ? AircraftGeometry.lowDetail(propeller: prop) : AircraftGeometry.detailed(propeller: prop)
        let mesh = (try? RadarMeshBatch.meshResource(batches, name: low ? "aircraft-low" : "aircraft"))
            ?? .generateBox(size: [0.04, 0.008, 0.06])
        meshes[key] = mesh
        return mesh
    }
}
