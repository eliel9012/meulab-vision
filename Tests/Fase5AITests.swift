import Foundation
import FoundationModels
import Testing
@testable import MeuLabVision

@Suite("Fase 5C · Foundation Models + cache de imagem")
struct Fase5AITests {
    private func trigger(_ id: String, acknowledged: Bool = false, value: Double = 91.5) -> VisionAlertTrigger {
        VisionAlertTrigger(id: id, ruleName: "CPU alta \(id)", triggeredAt: "2026-10-30T12:00:00",
                           value: value, threshold: 80, message: "CPU acima do limite", acknowledged: acknowledged)
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: Alertas

    @Test func alertsPromptIsNilWithoutActiveTriggers() {
        #expect(VisionInsightPrompt.alertsPrompt(triggers: []) == nil)
        #expect(VisionInsightPrompt.alertsPrompt(triggers: [trigger("1", acknowledged: true)]) == nil)
    }

    @Test func alertsPromptListsOnlyActiveTriggers() throws {
        let prompt = try #require(VisionInsightPrompt.alertsPrompt(
            triggers: [trigger("1"), trigger("2", acknowledged: true), trigger("3")]))
        #expect(prompt.contains("Alertas ativos (2):"))
        #expect(prompt.contains("CPU alta 1"))
        #expect(prompt.contains("CPU alta 3"))
        #expect(!prompt.contains("CPU alta 2"))
        #expect(prompt.contains("valor 91,5, limite 80"))
        #expect(prompt.contains("em 2026-10-30 12:00:00"))
    }

    @Test func alertsPromptCapsItemCount() throws {
        let triggers = (1...20).map { trigger(String($0)) }
        let prompt = try #require(VisionInsightPrompt.alertsPrompt(triggers: triggers, maxItems: 5))
        #expect(prompt.split(separator: "\n").filter { $0.hasPrefix("- CPU alta") }.count == 5)
        #expect(prompt.contains("e mais 15 alertas"))
    }

    // MARK: Logs

    @Test func logTailKeepsLastLinesAndMarksTruncation() {
        let raw = (1...300).map { "linha \($0)" }.joined(separator: "\n")
        let tail = VisionInsightPrompt.truncatedLogTail(raw, maxLines: 10, maxCharacters: 10_000)
        let lines = tail.split(separator: "\n").map(String.init)
        #expect(lines.first == VisionInsightPrompt.truncationMarker)
        #expect(lines.count == 11)
        #expect(lines[1] == "linha 291")
        #expect(lines.last == "linha 300")
    }

    @Test func logTailRespectsCharacterBudget() {
        let raw = (1...50).map { "evento \($0) " + String(repeating: "x", count: 80) }.joined(separator: "\n")
        let tail = VisionInsightPrompt.truncatedLogTail(raw, maxLines: 50, maxCharacters: 500)
        let body = tail.replacingOccurrences(of: VisionInsightPrompt.truncationMarker + "\n", with: "")
        #expect(body.count <= 500)
        #expect(tail.hasPrefix(VisionInsightPrompt.truncationMarker))
        #expect(tail.hasSuffix(String(repeating: "x", count: 80)))
        #expect(tail.contains("evento 50"))
    }

    @Test func logTailCutsSingleHugeLine() {
        let raw = String(repeating: "a", count: 1_000) + "FIM"
        let tail = VisionInsightPrompt.truncatedLogTail(raw, maxLines: 10, maxCharacters: 100)
        #expect(tail.count == 100)
        #expect(tail.hasPrefix("…"))
        #expect(tail.hasSuffix("FIM"))
    }

    @Test func logTailSkipsBlankLinesWithoutMarker() {
        let tail = VisionInsightPrompt.truncatedLogTail("\n  ok  \n\n pronto \n\n")
        #expect(tail == "ok\npronto")
    }

    @Test func logsPromptIncludesContainerAndIsNilWhenEmpty() throws {
        #expect(VisionInsightPrompt.logsPrompt(container: "radar", logs: "  \n\n") == nil)
        let prompt = try #require(VisionInsightPrompt.logsPrompt(container: "readsb", logs: "ERROR boom"))
        #expect(prompt.contains("Container: readsb"))
        #expect(prompt.contains("ERROR boom"))
    }

    @Test func defaultLogBudgetFitsSmallContext() {
        // ~4k tokens de contexto: logs + instruções devem ficar bem abaixo disso.
        #expect(VisionInsightPrompt.maxLogCharacters + VisionInsightPrompt.logsInstructions.count < 8_000)
    }

    // MARK: Telemetria

    @Test func telemetryContextFormatsStoreData() throws {
        let system: SystemStatus = try decode("""
            {"timestamp":"2026-10-30T12:00:00","hostname":"radar","location":"Franca",
             "uptime":{"seconds":90000,"formatted":"1d 1h","days":1,"hours":1,"minutes":0},
             "cpu":{"usage_percent":42.25,"temperature_c":55,"load_1min":0.8,"cores":4},
             "memory":{"total_mb":8000,"used_mb":4000,"used_percent":50},
             "disk":{"used_percent":70.2,"available_gb":30.5},
             "wifi":{"ssid":"Casa","quality_percent":80,"signal_dbm":-55}}
            """)
        let processes: VisionProcessList = try decode("""
            {"items":[{"pid":1,"command":"low","cpu_percent":1,"mem_percent":1},
                      {"pid":2,"command":"readsb","cpu_percent":30.5,"mem_percent":2}]}
            """)
        let history: VisionCPUHistory = try decode("""
            {"cpu":{"average":20,"peak":95,"minimum":3,"dataPoints":[]}}
            """)
        let context = VisionInsightPrompt.telemetryContext(system: system, processes: processes.items,
                                                           cpuHistory: history)
        #expect(context.contains("Host: radar (Franca)"))
        #expect(context.contains("Uptime: 1d 1h"))
        #expect(context.contains("CPU: uso 42,2%") || context.contains("CPU: uso 42,3%"))
        #expect(context.contains("temperatura 55°C"))
        #expect(context.contains("4 núcleos"))
        #expect(context.contains("Memória: 50% usada (4000 de 8000 MB)"))
        #expect(context.contains("Disco: 70,2% usado (30,5 GB livres)"))
        #expect(context.contains("Wi-Fi: Casa, qualidade 80%, -55 dBm"))
        #expect(context.contains("pico 95%"))
        let processLine = try #require(context.split(separator: "\n").first { $0.hasPrefix("Processos") })
        #expect(processLine.range(of: "readsb")!.lowerBound < processLine.range(of: "low")!.lowerBound)
    }

    @Test func telemetryContextEmptyWithoutData() {
        #expect(VisionInsightPrompt.telemetryContext(system: nil).isEmpty)
    }

    @Test func questionPromptValidation() throws {
        #expect(VisionInsightPrompt.questionPrompt(question: "   ", context: "Host: x") == nil)
        #expect(VisionInsightPrompt.questionPrompt(question: "CPU?", context: "") == nil)
        let prompt = try #require(VisionInsightPrompt.questionPrompt(question: "  CPU ok? ", context: "Host: x"))
        #expect(prompt.hasSuffix("Pergunta: CPU ok?"))
        #expect(prompt.contains("Host: x"))
        let long = String(repeating: "q", count: 2_000)
        #expect(VisionInsightPrompt.sanitizedQuestion(long).count == VisionInsightPrompt.maxQuestionCharacters)
    }

    @Test func numberFormattingIsPortuguese() {
        #expect(VisionInsightPrompt.number(80) == "80")
        #expect(VisionInsightPrompt.number(91.54) == "91,5")
        #expect(VisionInsightPrompt.cleanedResponse("\n  Tudo ok.  \n") == "Tudo ok.")
    }

    // MARK: Disponibilidade

    @Test func availabilityMapping() {
        #expect(VisionInsightAvailability.from(.available) == .available)
        let device = VisionInsightAvailability.from(.unavailable(.deviceNotEligible))
        #expect(device.hidesFeature)
        #expect(!device.isAvailable)
        let disabled = VisionInsightAvailability.from(.unavailable(.appleIntelligenceNotEnabled))
        #expect(!disabled.hidesFeature)
        #expect(disabled.message?.contains("Ative") == true)
        let notReady = VisionInsightAvailability.from(.unavailable(.modelNotReady))
        #expect(!notReady.hidesFeature)
        #expect(notReady.message != nil)
    }

    // MARK: Cache de imagem

    @Test func imageCacheConfiguration() throws {
        #expect(VisionImageCache.diskCapacity == 100 * 1024 * 1024)
        let directory = URL.temporaryDirectory.appending(path: "Fase5AITests-\(UUID().uuidString)")
        let cache = VisionImageCache.makeCache(directory: directory)
        #expect(cache.diskCapacity == VisionImageCache.diskCapacity)
        #expect(cache.memoryCapacity == VisionImageCache.memoryCapacity)
        let configuration = VisionImageCache.makeConfiguration(cache: cache)
        #expect(configuration.urlCache === cache)
        #expect(configuration.requestCachePolicy == .useProtocolCachePolicy)
        #expect(configuration.timeoutIntervalForRequest == VisionImageCache.requestTimeout)
        #expect(VisionImageCache.directory.lastPathComponent == VisionImageCache.directoryName)
        #expect(VisionImageCache.session.configuration.urlCache?.diskCapacity == VisionImageCache.diskCapacity)
        #expect(VisionImageCache.session.configuration.urlCache !== URLCache.shared)
    }
}
