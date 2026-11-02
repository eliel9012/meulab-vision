import SwiftUI

/// Shared request logic for Docker container logs (used by the pushed logs window).
enum DockerLogsRequest {
    static let path = "api/docker/logs"
    static let defaultTail = 200
    static let defaultSince = 3600
    static let emptyMessage = "Nenhum log recente."

    static func queryItems(container: String, tail: Int = defaultTail, since: Int = defaultSince) -> [URLQueryItem] {
        [
            URLQueryItem(name: "container", value: container),
            URLQueryItem(name: "tail", value: String(tail)),
            URLQueryItem(name: "since", value: String(since))
        ]
    }

    /// Text shown in the window: placeholder when the server returns nothing useful.
    static func displayText(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? emptyMessage : raw
    }

    /// Window title for a container (or a generic one when the window was restored without value).
    static func title(for container: String?) -> String {
        guard let container, !container.isEmpty else { return "Logs Docker" }
        return "Logs · \(container)"
    }

    @MainActor
    static func fetch(container: String) async throws -> String {
        try await VisionAPIClient.shared.fetchText(path, query: queryItems(container: container))
    }
}

/// Docker logs in their own window, opened with `pushWindow(id: "docker-logs", value: name)`.
struct DockerLogsWindowView: View {
    let containerName: String?
    @State private var logs = ""
    @State private var error: String?
    /// Container of the fetch in flight: a late answer for another one is dropped.
    @State private var loadingContainer: String?
    @State private var summary: VisionInsightState = .idle
    @State private var insightAvailability: VisionInsightAvailability = .available

    init(containerName: String?) {
        self.containerName = containerName
    }

    private var loading: Bool { loadingContainer != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(DockerLogsRequest.title(for: containerName)).font(.title2.bold())
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if let message = insightAvailability.message, !insightAvailability.hidesFeature, containerName != nil {
                Label(message, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
            VisionInsightResultCard(title: "Resumo dos logs", state: summary) { summary = .idle }
            if containerName == nil {
                ContentUnavailableView("Nenhum container", systemImage: "shippingbox",
                                       description: Text("Abra os logs a partir da lista de containers em Infraestrutura."))
            } else {
                ScrollView {
                    Text(loading && logs.isEmpty ? "Carregando…" : DockerLogsRequest.displayText(logs))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollInputBehavior(.enabled, for: .look)
                .defaultScrollAnchor(.bottom)
            }
        }
        .padding(26)
        .frame(minWidth: 620, idealWidth: 760, minHeight: 420, idealHeight: 540)
        .glassBackgroundEffect()
        .toolbar {
            ToolbarItemGroup(placement: .bottomOrnament) {
                if loading { ProgressView() }
                Button("Atualizar", systemImage: "arrow.clockwise") { Task { await refresh() } }
                    .disabled(containerName == nil || loading)
                VisionInsightButton(title: "Resumir", availability: insightAvailability,
                                    isLoading: summary == .loading) { Task { await summarize() } }
                    .disabled(containerName == nil || logs.isEmpty)
            }
        }
        .task(id: containerName) {
            insightAvailability = VisionInsightService.availability
            summary = .idle
            logs = ""
            await refresh()
        }
    }

    private func summarize() async {
        guard let containerName else { return }
        summary = .loading
        do {
            summary = .result(try await VisionInsightService.summarizeLogs(container: containerName, logs: logs))
        } catch {
            summary = .failure(error.localizedDescription)
        }
    }

    private func refresh() async {
        guard let containerName, loadingContainer != containerName else { return }
        loadingContainer = containerName
        defer { if loadingContainer == containerName { loadingContainer = nil } }
        do {
            let text = try await DockerLogsRequest.fetch(container: containerName)
            guard loadingContainer == containerName else { return }
            logs = text
            error = nil
        } catch {
            guard loadingContainer == containerName else { return }
            self.error = error.localizedDescription
        }
    }
}
