//
//  ActiveTimerStore.swift
//  TomatitoEnfocado
//
//  Estado global: pomodoros activos ("Ahora mismo").
//
//  Igual que en la web, pueden correr varios pomodoros distintos al mismo
//  tiempo — por eso este estado es una lista (mismo patrón que
//  ActiveTemporizadoresStore), no un único activo. La regla vieja de "solo
//  uno a la vez" era una limitación exclusiva del móvil, no del backend:
//  /pomodoros/{id}/start nunca detiene otros timers, y /pomodoros/active ya
//  devuelve la lista completa de todo lo que está corriendo.
//

import Foundation

@MainActor
final class ActiveTimerStore: ObservableObject {
    @Published var items: [ActivePomodoroItem] = []
    @Published var errorMessage: String?
    /// El pomodoro marcado como "principal" — se persiste en el servidor
    /// (GET/POST /principal, user_meta) para sincronizar con la web, no es
    /// solo un estado local del móvil.
    @Published private(set) var principalPomodoroId: Int?

    private var client: APIClient?
    private var ticker: Timer?
    private var resyncTimer: Timer?

    var hasActive: Bool { !items.isEmpty }

    /// Cuál pomodoro destacar en el anel grande. Misma regla que
    /// tomatito_api_current() en el backend: el principal si sigue activo;
    /// si no hay principal válido y solo queda uno, ese; si hay varios, el
    /// más reciente (items ya viene ordenado así, igual que /pomodoros/active).
    var featured: ActivePomodoroItem? {
        if let principalPomodoroId, let match = items.first(where: { $0.pomodoroId == principalPomodoroId }) {
            return match
        }
        return items.first
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
        items = []
        principalPomodoroId = nil
        errorMessage = nil
    }

    /// Marca `pomodoroId` como principal — se refleja de inmediato en el
    /// anel grande y sincroniza con la web (misma preferencia, user_meta).
    func setPrincipal(pomodoroId: Int) async {
        guard let client else { return }
        principalPomodoroId = pomodoroId
        try? await client.requestRaw("principal", method: "POST", body: ["kind": "pomodoro", "source_id": pomodoroId])
    }

    private func loadPrincipal() async {
        guard let client else { return }
        do {
            let json = try await client.requestRaw("principal", method: "GET")
            if let data = json["data"] as? [String: Any],
               (data["kind"] as? String) == "pomodoro" {
                principalPomodoroId = intFromAny(data["source_id"])
            } else {
                principalPomodoroId = nil
            }
        } catch {
            // Silencioso: sin principal guardado, se usa el fallback (más reciente).
        }
    }

    /// Espeja la regla del backend: con un solo activo, se adopta como
    /// principal automáticamente (y se persiste, igual que tomatito_api_current()).
    private func syncPrincipalIfNeeded() {
        if items.isEmpty {
            principalPomodoroId = nil
        } else if items.count == 1, principalPomodoroId != items[0].pomodoroId {
            let onlyId = items[0].pomodoroId
            Task { await setPrincipal(pomodoroId: onlyId) }
        } else if let pid = principalPomodoroId, !items.contains(where: { $0.pomodoroId == pid }) {
            principalPomodoroId = nil
        }
    }

    private func intFromAny(_ value: Any?) -> Int {
        if let n = value as? Int { return n }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) ?? 0 }
        return 0
    }

    private func ensureTicking() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                for index in self.items.indices {
                    if !self.items[index].isPaused && !self.items[index].isFinished && self.items[index].secondsLeft > 0 {
                        self.items[index].secondsLeft -= 1
                    }
                }
            }
        }
        ensureResyncing()
    }

    /// "El servidor es la fuente de verdad": cada 15s se contrasta el estado
    /// local con GET /pomodoros/active, para corregir cualquier desvío del
    /// contador (o detectar pomodoros iniciados/cancelados desde la web).
    private func ensureResyncing() {
        guard resyncTimer == nil else { return }
        resyncTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in await self.resyncFromServer() }
        }
    }

    func resyncFromServer() async {
        guard let client else { return }
        await loadPrincipal()
        do {
            let active: [ActivePomodoroStatus] = try await client.request("pomodoros/active")
            let finished = items.filter(\.isFinished)
            items = active.map { status in
                ActivePomodoroItem(
                    timerId: status.timerId,
                    pomodoroId: status.pomodoroId,
                    name: status.name,
                    phase: status.phase,
                    totalSeconds: status.duration,
                    secondsLeft: status.remaining,
                    isPaused: status.state == "paused",
                    cycle: status.cycle,
                    cyclesTotal: max(1, status.cyclesTotal),
                    workMinutes: status.work,
                    shortBreakMinutes: status.shortBreak,
                    longBreakMinutes: status.longBreak
                )
            } + finished
            if !items.isEmpty { ensureTicking() }
            syncPrincipalIfNeeded()
        } catch {
            // Silencioso: esto es una corrección de fondo, no debe interrumpir la UI.
        }
    }

    func start(pomodoro: Pomodoro) async {
        guard let client else { return }
        errorMessage = nil
        do {
            struct StartResult: Decodable {
                @FlexibleInt var timerId: Int
                var phase: String
                @FlexibleInt var duration: Int
            }
            let result: StartResult = try await client.request(
                "pomodoros/\(pomodoro.id)/start", method: "POST"
            )
            items.append(ActivePomodoroItem(
                timerId: result.timerId,
                pomodoroId: pomodoro.id,
                name: pomodoro.name,
                phase: result.phase,
                totalSeconds: result.duration,
                secondsLeft: result.duration,
                isPaused: false,
                cycle: 0,
                cyclesTotal: max(1, pomodoro.cycles),
                workMinutes: pomodoro.work,
                shortBreakMinutes: pomodoro.shortBreak,
                longBreakMinutes: pomodoro.longBreak
            ))
            ensureTicking()
            syncPrincipalIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Igual al botón ↻ "Reiniciar" de la web: para el timer y arranca de
    /// nuevo desde el principio (siempre en fase 'work'), sin tocar los
    /// demás pomodoros activos.
    func restart(_ item: ActivePomodoroItem) async {
        guard let client, let index = items.firstIndex(where: { $0.timerId == item.timerId }) else { return }
        errorMessage = nil
        do {
            try? await client.requestRaw("pomodoros/\(item.pomodoroId)/stop", method: "POST")
            struct StartResult: Decodable {
                @FlexibleInt var timerId: Int
                var phase: String
                @FlexibleInt var duration: Int
            }
            let result: StartResult = try await client.request(
                "pomodoros/\(item.pomodoroId)/start", method: "POST"
            )
            items[index] = ActivePomodoroItem(
                timerId: result.timerId,
                pomodoroId: item.pomodoroId,
                name: item.name,
                phase: result.phase,
                totalSeconds: result.duration,
                secondsLeft: result.duration,
                isPaused: false,
                cycle: 0,
                cyclesTotal: item.cyclesTotal,
                workMinutes: item.workMinutes,
                shortBreakMinutes: item.shortBreakMinutes,
                longBreakMinutes: item.longBreakMinutes
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePause(_ item: ActivePomodoroItem) async {
        guard let client, let index = items.firstIndex(where: { $0.timerId == item.timerId }) else { return }
        errorMessage = nil
        do {
            if items[index].isPaused {
                let json = try await client.requestRaw("pomodoros/\(item.pomodoroId)/resume", method: "POST")
                items[index].secondsLeft = intFromAny(json["time_left"])
                items[index].isPaused = false
            } else {
                let json = try await client.requestRaw("pomodoros/\(item.pomodoroId)/pause", method: "POST")
                items[index].secondsLeft = intFromAny(json["time_left"])
                items[index].isPaused = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop(_ item: ActivePomodoroItem) async {
        guard let client else { return }
        errorMessage = nil
        do {
            try await client.requestRaw("pomodoros/\(item.pomodoroId)/stop", method: "POST")
            items.removeAll { $0.timerId == item.timerId }
            syncPrincipalIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func advancePhase(_ item: ActivePomodoroItem) async {
        guard let client, let index = items.firstIndex(where: { $0.timerId == item.timerId }) else { return }
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
                "pomodoros/\(item.pomodoroId)/advance-phase", method: "POST"
            )
            if result.isFinal {
                try? await client.requestRaw("complete?timer_id=\(item.timerId)", method: "POST")
                items[index].isFinished = true
            } else {
                items[index].phase = result.phase ?? items[index].phase
                items[index].totalSeconds = result.duration ?? items[index].totalSeconds
                items[index].secondsLeft = result.duration ?? 0
                items[index].isPaused = false
                items[index].cycle = result.cycle ?? items[index].cycle
                items[index].cyclesTotal = result.cyclesTotal.map { max(1, $0) } ?? items[index].cyclesTotal
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissFinished(_ item: ActivePomodoroItem) {
        items.removeAll { $0.timerId == item.timerId }
    }
}
