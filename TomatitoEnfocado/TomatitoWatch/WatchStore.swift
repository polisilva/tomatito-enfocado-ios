//
//  WatchStore.swift
//  TomatitoWatch
//
//  Estado del reloj: pomodoros guardados, los que están en marcha y la próxima
//  alarma. El servidor es la fuente de verdad; el reloj solo cuenta en local
//  entre actualizaciones.
//

import Foundation
import WatchConnectivity

struct WatchActive: Identifiable {
    let timerId: Int
    let pomodoroId: Int
    var name: String
    var phase: String
    var phaseLabel: String
    var remaining: Int
    var duration: Int
    var isPaused: Bool
    var id: Int { timerId }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return Double(remaining) / Double(duration)
    }
}

@MainActor
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published var isLoggedIn = false
    @Published var pomodoros: [Pomodoro] = []
    @Published var active: [WatchActive] = []
    @Published var nextAlarma: UpcomingAlarma?
    @Published var todayMinutes = 0
    @Published var todayCompleted = 0
    /// Meta diaria de foco (min) para los anillos de "Hoy".
    let goalMinutes = 100
    @Published var errorMessage: String?
    @Published var isLoading = false

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var client: APIClient?
    private var ticker: Timer?
    private var lastSync = Date.distantPast

    override init() {
        super.init()
        if let saved = KeychainHelper.load() {
            client = APIClient(baseURL: saved.baseURL, username: saved.username, appPassword: saved.appPassword)
            isLoggedIn = true
        }
        #if DEBUG
        // Solo simulador: allí el iPhone no ve el app del reloj como "instalado" y no
        // puede mandar la sesión; se usa la misma clave de desarrollo que el iPhone.
        if !isLoggedIn, !DevCredentials.username.isEmpty, !DevCredentials.appPassword.isEmpty {
            client = APIClient(baseURL: DevCredentials.baseURL, username: DevCredentials.username, appPassword: DevCredentials.appPassword)
            isLoggedIn = true
        }
        #endif
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
        startTicker()
        Task {
            await refresh()
            #if DEBUG
            // Solo desarrollo: `-autostart` inicia el primer pomodoro para ver la pantalla "Ahora".
            if ProcessInfo.processInfo.arguments.contains("-autostart"), active.isEmpty, let first = pomodoros.first {
                await start(first)
            }
            #endif
        }
    }

    // MARK: - Sesión (llega desde el iPhone)

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in self.apply(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in self.apply(context) }
    }

    private func apply(_ context: [String: Any]) {
        guard !context.isEmpty else { return }
        if let baseURL = context["baseURL"] as? String,
           let username = context["username"] as? String,
           let password = context["appPassword"] as? String,
           !username.isEmpty, !password.isEmpty {
            KeychainHelper.save(username: username, appPassword: password, baseURL: baseURL)
            client = APIClient(baseURL: baseURL, username: username, appPassword: password)
            isLoggedIn = true
            Task { await refresh() }
        } else {
            // El iPhone cerró sesión.
            KeychainHelper.clear()
            client = nil
            isLoggedIn = false
            pomodoros = []
            active = []
            nextAlarma = nil
        }
    }

    // MARK: - Datos

    func refresh() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            async let pomodorosRequest: [Pomodoro] = client.request("pomodoros")
            async let activeRequest: [ActivePomodoroStatus] = client.request("pomodoros/active")
            async let alarmasRequest: [UpcomingAlarma]? = try? await client.request("alarmas/upcoming")
            let day = Self.isoDay.string(from: Date())
            async let todayRequest: HistorialPage? = try? await client.requestFull("history-sesiones?date_from=\(day)&date_to=\(day)&per_page=1")
            pomodoros = try await pomodorosRequest
            let status = try await activeRequest
            active = status.map {
                WatchActive(
                    timerId: $0.timerId, pomodoroId: $0.pomodoroId, name: $0.name,
                    phase: $0.phase, phaseLabel: $0.phaseLabel, remaining: $0.remaining, duration: $0.duration,
                    isPaused: $0.state == "paused"
                )
            }
            nextAlarma = await alarmasRequest?.first
            if let today = await todayRequest {
                todayMinutes = today.summary.minutos
                todayCompleted = today.summary.completadas
            }
            lastSync = Date()
        } catch {
            errorMessage = error.localizedDescription
            NSLog("TomatitoWatch refresh error: \(error.localizedDescription)")
        }
    }

    private func startTicker() {
        // El Timer corre en el hilo principal; MainActor.assumeIsolated evita
        // capturar `self` dentro de un Task concurrente.
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        for index in active.indices where !active[index].isPaused && active[index].remaining > 0 {
            active[index].remaining -= 1
        }
        // Cada 15 s se corrige con el servidor (fase nueva, parado desde otro lado…).
        if Date().timeIntervalSince(lastSync) > 15 {
            lastSync = Date()
            Task { await refresh() }
        }
    }

    // MARK: - Acciones

    func start(_ pomodoro: Pomodoro) async {
        guard let client else { return }
        struct StartResult: Decodable {
            @FlexibleInt var timerId: Int
            var phase: String
            @FlexibleInt var duration: Int
        }
        // Se muestra al instante con lo que responde /start; la lista completa
        // se corrige en segundo plano.
        if let result: StartResult = try? await client.request("pomodoros/\(pomodoro.id)/start", method: "POST") {
            let label = result.phase == "work" ? "Trabajo" : result.phase
            active.insert(WatchActive(
                timerId: result.timerId, pomodoroId: pomodoro.id, name: pomodoro.name,
                phase: result.phase, phaseLabel: label, remaining: result.duration, duration: result.duration, isPaused: false
            ), at: 0)
        }
        Task { await refresh() }
    }

    func stop(_ item: WatchActive) async {
        guard let client else { return }
        active.removeAll { $0.timerId == item.timerId }
        _ = try? await client.requestRaw("pomodoros/\(item.pomodoroId)/stop", method: "POST")
        await refresh()
    }

    func togglePause(_ item: WatchActive) async {
        guard let client else { return }
        let path = item.isPaused ? "resume" : "pause"
        _ = try? await client.requestRaw("pomodoros/\(item.pomodoroId)/\(path)", method: "POST")
        await refresh()
    }
}
