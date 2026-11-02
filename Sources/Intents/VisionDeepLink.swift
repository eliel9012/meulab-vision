import Foundation
import Observation

/// Esquema de deep link do app: `meulabvision://section/<id>`, onde `<id>` é o
/// nome do case de `VisionSection` (radar, system, alerts, trip…). Usado por
/// widgets, notificações e App Intents. Alertas individuais usam
/// `meulabvision://alert/<id codificado>` e abrem a seção Alertas.
enum VisionDeepLink {
    static let scheme = "meulabvision"
    static let sectionHost = "section"
    static let alertHost = "alert"

    static func url(for section: VisionSection) -> URL {
        // swiftlint:disable:next force_unwrapping
        URL(string: "\(scheme)://\(sectionHost)/\(section.routeID)")!
    }

    static func url(forAlert id: String) -> URL {
        // swiftlint:disable:next force_unwrapping
        URL(string: "\(scheme)://\(alertHost)/\(VisionQuery.pathSegment(id))")!
    }

    /// Id do alerta em `meulabvision://alert/<id>` (decodificado), ou `nil`.
    static func alertID(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme,
              url.host(percentEncoded: false)?.lowercased() == alertHost else { return nil }
        var path = Substring(url.path(percentEncoded: true))
        while path.hasPrefix("/") { path = path.dropFirst() }
        while path.hasSuffix("/") { path = path.dropLast() }
        guard !path.isEmpty, let id = String(path).removingPercentEncoding, !id.isEmpty else { return nil }
        return id
    }

    /// Aceita `meulabvision://section/<id>` (canônico), o atalho `meulabvision://<id>`
    /// e `meulabvision://alert/<id>` (seção Alertas).
    static func section(from url: URL) -> VisionSection? {
        guard url.scheme?.lowercased() == scheme,
              let host = url.host(percentEncoded: false)?.lowercased() else { return nil }
        if host == alertHost {
            return alertID(from: url) == nil ? nil : .alerts
        }
        let components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        if host == sectionHost {
            guard let id = components.first else { return nil }
            return VisionSection(routeID: id)
        }
        return components.isEmpty ? VisionSection(routeID: host) : nil
    }
}

extension VisionSection {
    /// Identificador estável (nome do case), independente do rótulo em português.
    var routeID: String { SectionAppEnum(self).rawValue }

    init?(routeID: String) {
        guard let value = SectionAppEnum(rawValue: routeID.lowercased()) else { return nil }
        self = value.section
    }
}

/// Pedido de navegação. `token` diferencia pedidos repetidos para a mesma seção.
struct VisionRouteRequest: Equatable, Sendable {
    let section: VisionSection
    let token: UUID

    init(section: VisionSection, token: UUID = UUID()) {
        self.section = section
        self.token = token
    }
}

/// Fonte única de navegação vinda de fora da UI (App Intents, URLs, toque em
/// notificação). O mission-control observa `pending`, aplica com `lab.select`
/// (e abre o volume no radar) e chama `consume`.
@MainActor
@Observable
final class VisionDeepLinkRouter {
    static let shared = VisionDeepLinkRouter()

    private(set) var pending: VisionRouteRequest?
    /// Alerta pedido por `OpenAlertIntent`/deep link; a tela de Alertas pode
    /// destacá-lo e chamar `consumeFocusedAlert()`.
    private(set) var focusedAlertID: String?

    func open(_ section: VisionSection) {
        pending = VisionRouteRequest(section: section)
    }

    /// Abre a seção Alertas focando um alerta específico.
    func openAlert(id: String) {
        focusedAlertID = id
        open(.alerts)
    }

    @discardableResult
    func consumeFocusedAlert() -> String? {
        defer { focusedAlertID = nil }
        return focusedAlertID
    }

    /// Retorna `false` se a URL não é um deep link reconhecido.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        if let alertID = VisionDeepLink.alertID(from: url) {
            openAlert(id: alertID)
            return true
        }
        guard let section = VisionDeepLink.section(from: url) else { return false }
        open(section)
        return true
    }

    /// Limpa o pedido aplicado (ignora se outro pedido já o substituiu).
    func consume(_ request: VisionRouteRequest) {
        if pending == request { pending = nil }
    }
}
