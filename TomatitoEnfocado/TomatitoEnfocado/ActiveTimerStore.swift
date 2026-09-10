//
//  ActiveTimerStore.swift
//  TomatitoEnfocado
//
//  Estado global: pomodoro ativo ("Ahora mismo").
//
//  Regla de la especificación "13. Móvil": solo puede haber UN pomodoro
//  activo a la vez, y "Ahora mismo" es la única pantalla que lo controla.
//  Por eso este estado vive a nivel de app (no dentro de una sola pantalla)
//  y se comparte vía @EnvironmentObject.
//

import Foundation

@MainActor
final class ActiveTimerStore: ObservableObject {
    @Published private(set) var pomodoroId: Int?
    @Published private(set) var pomodoroName: String = ""
    @Published private(set) var timerId: Int?
    @Published private(set) var phase: String = "work"
    @Published private(set) var totalSeconds: Int = 0
    @Published private(set) var secondsLeft: Int = 0
    @Published private(set) var isPaused = false
    @Published private(set) var cycle: Int = 0
    @Published private(set) var cyclesTotal: Int = 1
    @Published var isFinished = false
    @Published var isBusy = false
    @Published var errorMessage: String?

    // Duraciones del pomodoro en marcha (minutos), guardadas al iniciar para
    // poder anunciar la fase siguiente sin depender de una llamada extra.
    private var workMinutes: Int = 25
    private var shortBreakMinutes: Int = 5
    private var longBreakMinutes: Int = 15

    private var client: APIClient?
    private var ticker: Timer?
    private var resyncTimer: Timer?

    var hasActive: Bool { pomodoroId != nil }

    var phaseLabel: String {
        switch phase {
        case "work": return "Trabajo"
        case "short_break": return "Descanso corto"
        case "long_break": return "Descanso largo"
        default: return phase
        }
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(secondsLeft) / Double(totalSeconds)
    }

    /// Etiqueta "Ciclo actual" (ej. "2/4"), como en el mockup de "Ahora mismo".
    var cycleLabel: String {
        "\(min(cycle + 1, cyclesTotal))/\(cyclesTotal)"
    }

    /// Texto contextual "Siguiente: 5 min descanso corto" — calculado en el
    /// cliente a partir de la fase actual, sin llamar a la API.
    var nextPhaseText: String {
        switch phase {
        case "work":
            let isLastCycle = cycle + 1 >= cyclesTotal
            let minutes = isLastCycle ? longBreakMinutes : shortBreakMinutes
            let label = isLastCycle ? "descanso largo" : "descanso corto"
            return "Siguiente: \(minutes) min \(label)"
        case "short_break":
            return "Siguiente: \(workMinutes) min trabajo"
        case "long_break":
            return "Siguiente: nueva repetición (\(workMinutes) min trabajo)"
        default:
            return ""
        }
    }

    /// Chamado a partir do root quando o login muda — sem client não há
    /// como falar com a API, então qualquer estado antigo é limpo.
    func configure(client: APIClient?) {
        self.client = client
        if client == nil {
            reset()
        }
    }

    func reset() {
        ticker?.invalidate()
        ticker = nil
        resyncTimer?.invalidate()
        resyncTimer = nil
        pomodoroId = nil
        pomodoroName = ""
        timerId = nil
        phase = "work"
        totalSeconds = 0
        secondsLeft = 0
        isPaused = false
        cycle = 0
        cyclesTotal = 1
        isFinished = false
        errorMessage = nil
    }

    private func intFromAny(_ value: Any?) -> Int {
        if let n = value as? Int { return n }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) ?? 0 }
        return 0
    }

    private func startTicking() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                guard !self.isPaused, self.secondsLeft > 0 else { return }
                self.secondsLeft -= 1
            }
        }
        ensureResyncing()
    }

    /// "El servidor es la fuente de verdad": cada 15s se contrasta el estado
    /// local con GET /pomodoros/active para corregir cualquier desvío del
    /// contador (o detectar que el pomodoro fue pausado/cancelado desde la web).
    private func ensureResyncing() {
        guard resyncTimer == nil else { return }
        resyncTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in await self.resyncFromServer() }
        }
    }

    /// Contrasta (o adopta) el estado del pomodoro activo con el servidor.
    /// Se usa tanto en el timer periódico como al abrir "Ahora mismo", para
    /// detectar un pomodoro iniciado desde la web mientras el móvil no miraba.
    func resyncFromServer() async {
        guard let client, !isFinished else { return }
        do {
            let active: [ActivePomodoroStatus] = try await client.request("pomodoros/active")
            guard let match = pomodoroId != nil
                ? active.first(where: { $0.pomodoroId == pomodoroId })
                : active.first
            else {
                // El servidor ya no tiene nada en marcha: si el móvil creía
                // que sí, es que fue cancelado/completado desde otro lado.
                if pomodoroId != nil { reset() }
                return
            }

            if pomodoroId != match.pomodoroId {
                pomodoroId = match.pomodoroId
                pomodoroName = match.name
            }
            timerId = match.timerId
            phase = match.phase
            totalSeconds = match.duration
            secondsLeft = match.remaining
            isPaused = (match.state == "paused")
            cycle = match.cycle
            cyclesTotal = max(1, match.cyclesTotal)
            if ticker == nil { startTicking() }
        } catch {
            // Silencioso: esto es una corrección de fondo, no debe interrumpir la UI.
        }
    }

    /// Regla: iniciar un pomodoro nuevo cancela el que estuviera activo.
    func start(pomodoro: Pomodoro) async {
        guard let client else { return }
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        if let currentId = pomodoroId, currentId != pomodoro.id {
            try? await client.requestRaw("pomodoros/\(currentId)/stop", method: "POST")
        }

        do {
            struct StartResult: Decodable {
                @FlexibleInt var timerId: Int
                var phase: String
                @FlexibleInt var duration: Int
            }
            let result: StartResult = try await client.request(
                "pomodoros/\(pomodoro.id)/start", method: "POST"
            )
            pomodoroId = pomodoro.id
            pomodoroName = pomodoro.name
            timerId = result.timerId
            phase = result.phase
            totalSeconds = result.duration
            secondsLeft = result.duration
            isPaused = false
            isFinished = false
            cycle = 0
            cyclesTotal = max(1, pomodoro.cycles)
            workMinutes = pomodoro.work
            shortBreakMinutes = pomodoro.shortBreak
            longBreakMinutes = pomodoro.longBreak
            startTicking()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePause() async {
        guard let client, let pomodoroId else { return }
        errorMessage = nil
        do {
            if isPaused {
                let json = try await client.requestRaw("pomodoros/\(pomodoroId)/resume", method: "POST")
                secondsLeft = intFromAny(json["time_left"])
                isPaused = false
            } else {
                let json = try await client.requestRaw("pomodoros/\(pomodoroId)/pause", method: "POST")
                secondsLeft = intFromAny(json["time_left"])
                isPaused = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() async {
        guard let client, let pomodoroId else { return }
        errorMessage = nil
        do {
            try await client.requestRaw("pomodoros/\(pomodoroId)/stop", method: "POST")
            reset()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func advancePhase() async {
        guard let client, let pomodoroId else { return }
        errorMessage = nil
        do {
            struct AdvancePhaseResult: Decodable {
                var isFinal: Bool
                var phase: String?
                @FlexibleOptionalInt var duration: Int?
                @FlexibleOptionalInt var cycle: Int?
                @FlexibleOptionalInt var cyclesTotal: Int?
            }
            let result: AdvancePhaseResult = try await client.request(
                "pomodoros/\(pomodoroId)/advance-phase", method: "POST"
            )
            if result.isFinal {
                if let timerId {
                    try? await client.requestRaw("complete?timer_id=\(timerId)", method: "POST")
                }
                ticker?.invalidate()
                resyncTimer?.invalidate()
                resyncTimer = nil
                isFinished = true
            } else {
                phase = result.phase ?? phase
                totalSeconds = result.duration ?? totalSeconds
                secondsLeft = result.duration ?? 0
                isPaused = false
                cycle = result.cycle ?? cycle
                cyclesTotal = result.cyclesTotal.map { max(1, $0) } ?? cyclesTotal
                startTicking()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
