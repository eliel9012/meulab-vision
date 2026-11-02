import SwiftUI

/// Content of one Lab section. Shared by the main TabView and the detached
/// "lab-panel" windows.
struct VisionSectionContent: View {
    let section: VisionSection
    /// Detached panels refresh store-backed sections themselves; the main
    /// window relies on `VisionLabStore.start()` polling.
    var pollsOwnData = false

    var body: some View {
        Group {
            switch section {
            case .radar: DashboardView()
            case .trip: VisionTripView()
            case .analytics: VisionAnalyticsView()
            case .alerts: VisionAlertsView()
            case .series: VisionSeriesView()
            case .acars: VisionACARSView()
            case .weather: VisionWeatherView()
            case .system, .infrastructure, .radio: VisionDataView(section: section, pollsOwnData: pollsOwnData)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Covers detached lab-panel windows too (radio artwork etc.).
        .visionImageCache()
    }
}

/// Window for `WindowGroup(id: "lab-panel", for: VisionSection.self)`.
struct VisionLabPanelView: View {
    let section: VisionSection?
    @Environment(FlightStore.self) private var flights
    @State private var pollingKey = "panel-\(UUID().uuidString)"

    var body: some View {
        Group {
            if let section {
                VisionSectionContent(section: section, pollsOwnData: true)
                    .padding(24)
                    .navigationTitle(section.title)
            } else {
                ContentUnavailableView("Seção indisponível", systemImage: "rectangle.on.rectangle.slash")
            }
        }
        .onAppear { if section == .radar { flights.acquirePolling(pollingKey) } }
        .onDisappear { flights.releasePolling(pollingKey) }
    }
}
