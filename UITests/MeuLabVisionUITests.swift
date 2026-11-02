import XCTest

final class MeuLabVisionUITests: XCTestCase {
    /// Launch independent from what earlier runs persisted, and without the notification prompt over the window.
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-radar.tableScale", "1", "-radar.radiusKilometers", "100", "-skipNotificationPrompt", "YES"]
        app.launch()
        return app
    }

    /// Tab rows expose the SF Symbol as identifier; their label also matches a nested button.
    private func openTab(_ symbol: String, in app: XCUIApplication) {
        let tab = app.buttons.matching(identifier: symbol).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "Aba \(symbol) ausente")
        tab.tap()
    }

    func testRadar3DOpensAutomaticallyAndCanReopen() {
        let app = launchApp()

        let close = app.buttons["Fechar radar"]
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Mesa 0,8 m · raio 100 km"].waitForExistence(timeout: 10))
        close.tap()
        let open = app.buttons["Radar 3D"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 10))
    }

    func testInteractiveMapOpensAndCanClose() {
        let app = launchApp()

        let open = app.buttons["Mapa interativo"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()
        XCTAssertTrue(app.staticTexts["Mapa interativo"].waitForExistence(timeout: 10))
        let close = app.buttons["Fechar janela do mapa"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: close)
        wait(for: [closed], timeout: 10)
        app.activate()
        XCTAssertTrue(open.waitForExistence(timeout: 10))
    }

    func testFlightSearchOpensWithLiveAndAirportModes() {
        let app = launchApp()

        let open = app.buttons["Buscar voos"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()
        XCTAssertTrue(app.textFields["Número, matrícula ou ICAO"].waitForExistence(timeout: 10))
        app.buttons["Aeroportos"].tap()
        XCTAssertTrue(app.buttons["Atualizar"].waitForExistence(timeout: 10))
    }

    func testTripShowsItineraryFlightsAndWeather() throws {
        let app = launchApp()
        openTab("suitcase.rolling.fill", in: app)
        // The itinerary is personal and not in git, so clean checkouts have none.
        try XCTSkipIf(app.staticTexts["Roteiro não encontrado no app."].waitForExistence(timeout: 3),
                      "TripItinerary.json is not in this build")
        XCTAssertTrue(app.staticTexts["8 trechos confirmados"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Clima na rota"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Roteiro"].waitForExistence(timeout: 10))
    }

    func testRadioShowsHistorySection() {
        let app = launchApp()
        openTab("play.rectangle.on.rectangle", in: app)
        XCTAssertTrue(app.staticTexts["Histórico recente"].waitForExistence(timeout: 20))
    }

    func testAnalyticsShowsSystemAndRadarSections() {
        let app = launchApp()
        openTab("chart.xyaxis.line", in: app)
        XCTAssertTrue(app.staticTexts["Sistema · dados do servidor · CPU"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Tráfego ADS-B · histórico do receptor"].waitForExistence(timeout: 20))
    }

    func testAlertsShowsRulesAndTriggers() {
        let app = launchApp()
        openTab("bell.badge", in: app)
        XCTAssertTrue(app.staticTexts["Disparos recentes"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Regras do servidor"].waitForExistence(timeout: 10))
    }

    func testInfrastructureShowsAdvancedTools() {
        let app = launchApp()
        openTab("cpu", in: app)
        let infrastructure = app.buttons["Infraestrutura"]
        XCTAssertTrue(infrastructure.waitForExistence(timeout: 10))
        infrastructure.tap()
        XCTAssertTrue(app.staticTexts["Saúde da API"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Containers Docker"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Serviços systemd"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Saúde dos discos"].waitForExistence(timeout: 10))
    }

    func testAllSectionsAreReachable() {
        let app = launchApp()

        openTab("play.rectangle.on.rectangle", in: app)
        let series = app.buttons["Séries"]
        XCTAssertTrue(series.waitForExistence(timeout: 10))
        series.tap()
        XCTAssertTrue(app.staticTexts["Séries"].waitForExistence(timeout: 10))

        openTab("waveform.path", in: app)
        XCTAssertTrue(app.staticTexts["Buscar mensagens"].waitForExistence(timeout: 20))

        openTab("cloud.sun", in: app)
        XCTAssertTrue(app.staticTexts["Próximos 10 dias"].waitForExistence(timeout: 20))

        openTab("cpu", in: app)
        XCTAssertTrue(app.staticTexts["Histórico de CPU"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Fire Stick"].waitForExistence(timeout: 10))
    }

    func testHeatmapOpens3DVolume() {
        let app = launchApp()
        openTab("waveform.path", in: app)
        let open = app.buttons["Ver em 3D"]
        XCTAssertTrue(open.waitForExistence(timeout: 20))
        open.tap()
        // The volume has no accessible text of its own: the panel must survive opening it.
        XCTAssertTrue(open.waitForExistence(timeout: 10))
    }
}
