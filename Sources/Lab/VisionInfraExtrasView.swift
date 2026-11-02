import SwiftUI

struct VisionInfraExtrasView: View {
    @State private var metrics: VisionAPIMetrics?
    @State private var containers: [VisionDockerContainer] = []
    @State private var services: [VisionSystemdService] = []
    @State private var diskHealth: VisionDiskHealth?
    @State private var errors: [String: String] = [:]
    @State private var search = ""
    @Environment(\.pushWindow) private var pushWindow
    @State private var loading = false

    private var filteredContainers: [VisionDockerContainer] {
        search.isEmpty ? containers : containers.filter {
            $0.names.localizedCaseInsensitiveContains(search) || $0.image.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Saúde da API", systemImage: "waveform.path.ecg").font(.title2.bold())
            if let metrics {
                HStack(spacing: 12) {
                    metric("Uptime", "\(metrics.uptimeSeconds / 3600) h")
                    metric("Requisições", "\(metrics.requestCount)")
                    metric("Latência média", "\(metrics.avgResponseMs.formatted(.number.precision(.fractionLength(1)))) ms")
                    metric("Cache", "\(metrics.cacheHits) / \(metrics.cacheMisses)")
                }
            } else { unavailable("metrics") }

            HStack {
                Label("Containers Docker", systemImage: "shippingbox").font(.title2.bold())
                Spacer()
                Text("\(filteredContainers.count)").foregroundStyle(.secondary)
            }
            TextField("Buscar container", text: $search)
                .textFieldStyle(.roundedBorder)
            if containers.isEmpty {
                unavailable("docker")
            } else {
                ForEach(filteredContainers) { container in
                    Button {
                        pushWindow(id: "docker-logs", value: container.names)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: container.state.lowercased() == "running" ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(container.state.lowercased() == "running" ? .green : .orange)
                                .accessibilityLabel(container.state.lowercased() == "running" ? "Em execução" : "Com problema")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(container.names).font(.headline)
                                Text(container.image).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(container.health?.status ?? container.state).font(.caption)
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .padding(14)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .liftCard(cornerRadius: 12)
                    .accessibilityHint("Abre os logs em uma janela")
                }
            }

            Label("Serviços systemd", systemImage: "server.rack").font(.title2.bold())
            if services.isEmpty {
                unavailable("systemd")
            } else {
                ForEach(services) { service in
                    HStack(spacing: 12) {
                        Image(systemName: service.activeState == "active" ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(service.activeState == "active" ? .green : .orange)
                            .accessibilityLabel(service.activeState == "active" ? "Ativo" : "Inativo")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(service.service).font(.headline)
                            Text(service.description).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(service.activeState) · \(service.subState)").font(.caption)
                    }
                    .padding(14)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    .depthCard()
                }
            }

            Label("Saúde dos discos", systemImage: "internaldrive").font(.title2.bold())
            if let diskHealth, !diskHealth.devices.isEmpty {
                ForEach(diskHealth.devices) { device in
                    HStack(spacing: 12) {
                        Image(systemName: device.healthPassed == true ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .foregroundStyle(device.healthPassed == true ? .green : .orange)
                            .accessibilityLabel(device.healthPassed == true ? "Saudável" : "Com alerta")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.model ?? device.device).font(.headline)
                            Text(device.device).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let temperature = device.temperatureC { Text("\(temperature.formatted())°C") }
                        if let used = device.percentageUsed { Text("\(used.formatted())% usado") }
                        if let failures = device.mediaErrors, failures > 0 {
                            Text("\(failures.formatted()) erros").foregroundStyle(.orange)
                        }
                    }
                    .padding(14)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    .depthCard()
                }
            } else { unavailable("disk") }
        }
        .polling(every: .seconds(60)) { await refresh() }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .depthCard()
    }

    private func unavailable(_ key: String) -> some View {
        Text(errors[key] ?? (loading ? "Carregando…" : "Sem dados disponíveis."))
            .font(.callout).foregroundStyle(.secondary)
    }

    private func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let api = try VisionAPIClient.shared
            do { metrics = try await api.fetch("api/metrics"); errors["metrics"] = nil }
            catch { errors["metrics"] = error.localizedDescription }
            do {
                let response: VisionDockerStatus = try await api.fetch("api/docker/status?health=1")
                containers = response.containers
                errors["docker"] = nil
            } catch { errors["docker"] = error.localizedDescription }
            do {
                let response: VisionSystemdStatus = try await api.fetch("api/systemd/status")
                services = response.services
                errors["systemd"] = nil
            } catch { errors["systemd"] = error.localizedDescription }
            do { diskHealth = try await api.fetch("api/system/disk_health"); errors["disk"] = nil }
            catch { errors["disk"] = error.localizedDescription }
        } catch {
            for key in ["metrics", "docker", "systemd", "disk"] { errors[key] = error.localizedDescription }
        }
    }
}
