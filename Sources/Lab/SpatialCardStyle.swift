import SwiftUI

/// Depth values used by Lab/Trip cards. Kept small so glass panels don't look detached.
enum SpatialDepth {
    static let card: CGFloat = 6
    static let interactiveCard: CGFloat = 10

    /// Clamps a requested z offset into a modest range that reads well inside a window.
    static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 24)
    }
}

extension View {
    /// Interactive card: hover shape + lift effect + small z offset.
    func liftCard(cornerRadius: CGFloat, depth: CGFloat = SpatialDepth.interactiveCard) -> some View {
        self
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .hoverEffect(.lift)
            .offset(z: SpatialDepth.clamped(depth))
    }

    /// Static metric/status card: lifted a little off the window and read as one accessibility element.
    func depthCard(depth: CGFloat = SpatialDepth.card) -> some View {
        self
            .accessibilityElement(children: .combine)
            .offset(z: SpatialDepth.clamped(depth))
    }
}
