import Foundation

/// Construção pura (testável) dos prompts enviados ao modelo on-device.
/// O modelo do sistema tem janela de contexto pequena (~4k tokens), então
/// tudo aqui é truncado por linhas e caracteres antes de virar prompt.
enum VisionInsightPrompt {
    static let maxAlertItems = 15
    static let maxLogLines = 120
    static let maxLogCharacters = 3_000
    static let maxQuestionCharacters = 500
    static let maxProcesses = 5
    static let truncationMarker = "[… linhas anteriores omitidas …]"

    // MARK: Instruções

    static let alertsInstructions = """
        Você é o assistente do MeuLab, um homelab pessoal. Resuma alertas de monitoramento \
        em português do Brasil, em no máximo 4 frases curtas. Destaque o mais grave primeiro, \
        agrupe alertas repetidos e sugira uma ação prática. Não invente dados.
        """

    static let logsInstructions = """
        Você é o assistente do MeuLab. Analise logs de um container Docker e responda em \
        português do Brasil, em até 5 tópicos curtos: estado geral, erros ou avisos relevantes \
        (com o trecho-chave) e uma sugestão. Se não houver problemas, diga isso. Não invente dados.
        """

    static let telemetryInstructions = """
        Você é o assistente do MeuLab. Responda perguntas sobre a telemetria do servidor \
        usando apenas os dados fornecidos, em português do Brasil, de forma curta e direta. \
        Se os dados não bastarem para responder, diga o que está faltando.
        """

    // MARK: Alertas

    /// Alertas ativos = disparos ainda não reconhecidos.
    static func activeTriggers(_ triggers: [VisionAlertTrigger]) -> [VisionAlertTrigger] {
        triggers.filter { !$0.acknowledged }
    }

    static func alertLine(_ trigger: VisionAlertTrigger) -> String {
        let when = trigger.triggeredAt.replacingOccurrences(of: "T", with: " ")
        return "- \(trigger.ruleName): \(trigger.message) (valor \(number(trigger.value)), limite \(number(trigger.threshold)), em \(when))"
    }

    /// `nil` quando não há alertas ativos (não vale a pena chamar o modelo).
    static func alertsPrompt(triggers: [VisionAlertTrigger], maxItems: Int = maxAlertItems) -> String? {
        let active = activeTriggers(triggers)
        guard !active.isEmpty else { return nil }
        var lines = ["Alertas ativos (\(active.count)):"]
        lines += active.prefix(maxItems).map(alertLine)
        if active.count > maxItems {
            lines.append("- … e mais \(active.count - maxItems) alertas não listados.")
        }
        lines.append("Resuma a situação.")
        return lines.joined(separator: "\n")
    }

    // MARK: Logs

    /// Mantém só o final do log: no máximo `maxLines` linhas não vazias e
    /// `maxCharacters` caracteres (linhas longas são cortadas no começo).
    static func truncatedLogTail(_ raw: String,
                                 maxLines: Int = maxLogLines,
                                 maxCharacters: Int = maxLogCharacters) -> String {
        let all = raw.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var kept: [String] = []
        var used = 0
        for line in all.suffix(maxLines).reversed() {
            let remaining = maxCharacters - used
            guard remaining > 0 else { break }
            let piece = line.count > remaining ? "…" + String(line.suffix(max(remaining - 1, 0))) : line
            kept.append(piece)
            used += piece.count + 1
        }
        kept.reverse()
        if kept.count < all.count { kept.insert(truncationMarker, at: 0) }
        return kept.joined(separator: "\n")
    }

    static func logsPrompt(container: String, logs: String,
                           maxLines: Int = maxLogLines,
                           maxCharacters: Int = maxLogCharacters) -> String? {
        let tail = truncatedLogTail(logs, maxLines: maxLines, maxCharacters: maxCharacters)
        guard !tail.isEmpty else { return nil }
        return """
            Container: \(container)
            Últimas linhas do log:
            \(tail)

            Resuma o que está acontecendo.
            """
    }

    // MARK: Telemetria

    static func telemetryContext(system: SystemStatus?,
                                 processes: [VisionProcess] = [],
                                 partitions: [VisionPartition] = [],
                                 interfaces: [VisionNetworkInterface] = [],
                                 cpuHistory: VisionCPUHistory? = nil) -> String {
        var lines: [String] = []
        if let system {
            lines.append("Host: \(system.hostname) (\(system.location))")
            if let uptime = system.uptime { lines.append("Uptime: \(uptime.formatted)") }
            if let cpu = system.cpu {
                var parts: [String] = []
                if let usage = cpu.usagePercent { parts.append("uso \(number(usage))%") }
                if let temp = cpu.temperatureC { parts.append("temperatura \(number(temp))°C") }
                if let load = cpu.load1min { parts.append("load 1m \(number(load))") }
                if let cores = cpu.cores { parts.append("\(cores) núcleos") }
                if !parts.isEmpty { lines.append("CPU: " + parts.joined(separator: ", ")) }
            }
            if let memory = system.memory, let used = memory.usedPercent {
                var text = "Memória: \(number(used))% usada"
                if let usedMb = memory.usedMb, let total = memory.totalMb { text += " (\(usedMb) de \(total) MB)" }
                lines.append(text)
            }
            if let disk = system.disk, let used = disk.usedPercent {
                var text = "Disco: \(number(used))% usado"
                if let free = disk.availableGb { text += " (\(number(free)) GB livres)" }
                lines.append(text)
            }
            if let wifi = system.wifi, let ssid = wifi.ssid {
                var text = "Wi-Fi: \(ssid)"
                if let quality = wifi.qualityPercent { text += ", qualidade \(quality)%" }
                if let dbm = wifi.signalDbm { text += ", \(dbm) dBm" }
                lines.append(text)
            }
        }
        if let cpuHistory {
            let cpu = cpuHistory.cpu
            lines.append("CPU nas últimas 24h: média \(number(cpu.average))%, pico \(number(cpu.peak))%, mínimo \(number(cpu.minimum))%")
        }
        if !processes.isEmpty {
            let top = processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(maxProcesses)
            lines.append("Processos com mais CPU: " + top.map {
                "\($0.command) (CPU \(number($0.cpuPercent))%, RAM \(number($0.memPercent))%)"
            }.joined(separator: "; "))
        }
        if !partitions.isEmpty {
            lines.append("Partições: " + partitions.map { "\($0.mount) \($0.usedPercent)" }.joined(separator: ", "))
        }
        if !interfaces.isEmpty {
            lines.append("Rede: " + interfaces.map {
                "\($0.iface) ↓\(ByteCountFormatter.string(fromByteCount: $0.rxBytes, countStyle: .file)) ↑\(ByteCountFormatter.string(fromByteCount: $0.txBytes, countStyle: .file))"
            }.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    static func sanitizedQuestion(_ question: String, maxCharacters: Int = maxQuestionCharacters) -> String {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > maxCharacters ? String(trimmed.prefix(maxCharacters)) : trimmed
    }

    /// `nil` para pergunta vazia ou sem telemetria disponível.
    static func questionPrompt(question: String, context: String) -> String? {
        let question = sanitizedQuestion(question)
        guard !question.isEmpty, !context.isEmpty else { return nil }
        return """
            Telemetria atual do MeuLab:
            \(context)

            Pergunta: \(question)
            """
    }

    // MARK: Formatação

    /// Número curto em pt-BR (até 1 casa decimal), estável para testes.
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "pt_BR")))
    }

    /// Limpa a resposta do modelo para exibição.
    static func cleanedResponse(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
