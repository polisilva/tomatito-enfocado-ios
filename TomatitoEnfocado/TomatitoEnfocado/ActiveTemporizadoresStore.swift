//
//  ActiveTemporizadoresStore.swift
//  TomatitoEnfocado
//
//  Estado global: temporizadores activos ("Ahora mismo"). A diferencia del
//  pomodoro, varios pueden coexistir — por eso es una lista.
//

import Foundation

@MainActor
final class ActiveTemporizadoresStore: ObservableObject {
    @Published var items: [ActiveTemporizadorItem] = []
    @Published var errorMessage: String?

    private var client: APIClient?
    private var ticker: Timer?

    func configure(client: APIClient?) {
        self.client = client
        if client == nil {
            ticker?.invalidate()
            ticker = nil
            items = []
            NotificationManager.shared.cancelAll(prefix: "temporizador-")
        }
    }

    private func syncNotification(_ item: ActiveTemporizadorItem) {
        if item.isPaused || item.secondsLeft <= 0 {
            NotificationManager.shared.cancel(ids: ["temporizador-\(item.timerId)"])
        } else {
            NotificationManager.shared.scheduleTemporizador(item)
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
                    guard !self.items[index].isPaused else { continue }
                    if self.items[index].secondsLeft > 0 {
                        self.items[index].secondsLeft -= 1
                    }
                    if self.items[index].secondsLeft == 0 && !self.items[index].hasPlayedFinishSound {
                        self.items[index].hasPlayedFinishSound = true
                        SoundPlayer.play(self.items[index].sound, defaultSound: AjustesStore.shared.sonidoTemporizador)
                    }
                }
            }
        }
    }

    func start(temporizador: Temporizador) async {
        guard let client else { return }
        errorMessage = nil
        do {
            let json = try await client.requestRaw("temporizadores/\(temporizador.id)/start", method: "POST")
            let timerId = intFromAny(json["timer_id"])
            let duration = intFromAny(json["duration"])
            let newItem = ActiveTemporizadorItem(timerId: timerId, name: temporizador.name, secondsLeft: duration, isPaused: false, sound: temporizador.sound)
            items.append(newItem)
            syncNotification(newItem)
            ensureTicking()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePause(_ item: ActiveTemporizadorItem) async {
        guard let client, let index = items.firstIndex(where: { $0.timerId == item.timerId }) else { return }
        errorMessage = nil
        do {
            if items[index].isPaused {
                let json = try await client.requestRaw("temporizadores/\(item.timerId)/resume", method: "POST")
                items[index].secondsLeft = intFromAny(json["time_left"])
                items[index].isPaused = false
            } else {
                let json = try await client.requestRaw("temporizadores/\(item.timerId)/pause", method: "POST")
                items[index].secondsLeft = intFromAny(json["time_left"])
                items[index].isPaused = true
            }
            syncNotification(items[index])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Igual al ↻ de la web: POST /temporizadores/{timer_id}/restart deja el
    /// mismo timer corriendo otra vez desde su duración original.
    func restart(_ item: ActiveTemporizadorItem) async {
        guard let client, let index = items.firstIndex(where: { $0.timerId == item.timerId }) else { return }
        errorMessage = nil
        do {
            let json = try await client.requestRaw("temporizadores/\(item.timerId)/restart", method: "POST")
            items[index].secondsLeft = intFromAny(json["duration"])
            items[index].isPaused = false
            items[index].hasPlayedFinishSound = false
            syncNotification(items[index])
            ensureTicking()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop(_ item: ActiveTemporizadorItem) async {
        guard let client else { return }
        errorMessage = nil
        do {
            try await client.requestRaw("temporizadores/\(item.timerId)/stop", method: "POST")
            items.removeAll { $0.timerId == item.timerId }
            NotificationManager.shared.cancel(ids: ["temporizador-\(item.timerId)"])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// "El servidor es la fuente de verdad": reemplaza la lista local por lo
    /// que devuelve GET /temporizadores/dashboard, para corregir desvíos del
    /// contador y detectar temporizadores lanzados desde la web.
    func resyncFromServer() async {
        guard let client else { return }
        struct DashboardEntry: Decodable {
            @FlexibleOptionalInt var timerId: Int?
            var name: String
            @FlexibleInt var remaining: Int
            var state: String
        }
        struct DashboardResponse: Decodable {
            var mode: String
            var data: [DashboardEntry]
        }
        do {
            let json = try await client.requestRaw("temporizadores/dashboard", method: "GET")
            let data = try JSONSerialization.data(withJSONObject: json)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(DashboardResponse.self, from: data)

            guard response.mode == "running" else {
                items = []
                NotificationManager.shared.cancelAll(prefix: "temporizador-")
                return
            }
            // El dashboard no manda "sound" — se conserva el que ya teníamos
            // (por timerId) para no perderlo en cada resync.
            let previousByTimerId = Dictionary(uniqueKeysWithValues: items.map { ($0.timerId, $0) })
            items = response.data.compactMap { entry in
                guard let timerId = entry.timerId else { return nil }
                let previous = previousByTimerId[timerId]
                return ActiveTemporizadorItem(
                    timerId: timerId,
                    name: entry.name,
                    secondsLeft: entry.remaining,
                    isPaused: entry.state == "paused",
                    sound: previous?.sound,
                    hasPlayedFinishSound: previous?.hasPlayedFinishSound ?? false
                )
            }
            let removed = Set(previousByTimerId.keys).subtracting(items.map(\.timerId))
            NotificationManager.shared.cancel(ids: removed.map { "temporizador-\($0)" })
            items.forEach(syncNotification)
            ensureTicking()
        } catch {
            // Silencioso: corrección de fondo, no debe interrumpir la UI.
        }
    }
}
