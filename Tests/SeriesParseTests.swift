import Testing
@testable import MeuLabVision

@Suite("Séries – parse de nome")
struct SeriesParseTests {
    @Test(arguments: [
        ("S01E02 - Piloto", 1, 2, "Piloto"),
        ("Show.s3e104.O Retorno", 3, 104, "O Retorno"),
        ("Serie S10E01_Final.", 10, 1, "Final"),
        ("Minha Série — S02E05 — Título", 2, 5, "Título")
    ])
    func parsesCode(name: String, season: Int, episode: Int, title: String) {
        let parsed = VisionSeriesLibrary.parse(name)
        #expect(parsed.0 == season)
        #expect(parsed.1 == episode)
        #expect(parsed.2 == title)
    }

    @Test func withoutCodeKeepsName() {
        let parsed = VisionSeriesLibrary.parse("Documentário avulso")
        #expect(parsed.0 == nil)
        #expect(parsed.1 == nil)
        #expect(parsed.2 == "Documentário avulso")
    }

    @Test func codeOnlyFallsBackToFullName() {
        let parsed = VisionSeriesLibrary.parse("S01E01")
        #expect(parsed.0 == 1 && parsed.1 == 1)
        #expect(parsed.2 == "S01E01")
    }
}
