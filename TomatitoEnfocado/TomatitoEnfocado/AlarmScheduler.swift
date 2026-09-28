//
//  AlarmScheduler.swift
//  TomatitoEnfocado
//
//  "Vigía de alarmas": mismo mecanismo que vigiarAlarmasGlobal() en la web
//  (21-tomatito-notifications.php) — mientras el app está abierto, consulta
//  GET /alarmas/upcoming cada 20s y, cuando el horario de una alarma ya
//  pasó hoy, suena y queda "pendiente" hasta que el usuario la detenga,
//  repitiendo cada reminder_minutes mientras tanto. No hay notificaciones
//  en segundo plano (ni la web las tiene): esto solo funciona con el app
//  abierto, igual que allá solo funciona con la pestaña abierta.
//

import Foundation

struct FiringAlarm: Identifiable {
    let key: String
    let name: String
    let time: String
    var id: String { key }
}

@MainActor
final class AlarmScheduler: ObservableObject {
    @Published var firing: FiringAlarm?

    private var client: APIClient?
    private var timer: Timer?
    /// Próximo recordatorio permitido por clave "id_fecha_hora" (misma
    /// clave que usa la web para no repetir antes de tiempo).
    private var nextReminderAt: [String: Date] = [:]
    /// Ocurrencias que el usuario ya detuvo hoy — no vuelven a sonar.
    private var stopped: Set<String> = []

    func configure(client: APIClient?) {
        self.client = client
        timer?.invalidate()
        timer = nil
        firing = nil
        nextReminderAt = [:]
        stopped = []
        if client != nil {
            ensureWatching()
        }
    }

    func stopFiring() {
        guard let firing else { return }
        stopped.insert(firing.key)
        nextReminderAt.removeValue(forKey: firing.key)
        self.firing = nil
    }

    private func ensureWatching() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in await self.check() }
        }
        Task { await check() }
    }

    private func check() async {
        guard let client else { return }
        struct UpcomingRaw: Decodable {
            @FlexibleInt var id: Int
            var name: String
            var time: String
            var sound: String?
            @FlexibleOptionalInt var reminderMinutes: Int?
        }
        do {
            let alarmas: [UpcomingRaw] = try await client.request("alarmas/upcoming")
            let now = Date()
            let calendar = Calendar.current
            let nowMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
            let todayKey = Self.dayFormatter.string(from: now)

            for alarma in alarmas {
                let parts = alarma.time.split(separator: ":")
                guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { continue }
                let alarmMinutes = hour * 60 + minute
                guard nowMinutes >= alarmMinutes else { continue }

                let key = "\(alarma.id)_\(todayKey)_\(alarma.time)"
                if stopped.contains(key) { continue }
                if let nextAt = nextReminderAt[key], now < nextAt { continue }

                let reminderMinutes = max(1, alarma.reminderMinutes ?? 5)
                nextReminderAt[key] = now.addingTimeInterval(TimeInterval(reminderMinutes * 60))
                SoundPlayer.play(alarma.sound, defaultSound: "campana")
                firing = FiringAlarm(key: key, name: alarma.name, time: alarma.time)
            }
        } catch {
            // Silencioso: esto es un chequeo de fondo, no debe interrumpir la UI.
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
