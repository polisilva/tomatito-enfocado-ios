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
    let alarmId: Int
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
    private var ticks = 0
    /// Próximo recordatorio permitido por clave "id_fecha_hora" (misma
    /// clave que usa la web para no repetir antes de tiempo).
    private var nextReminderAt: [String: Date] = [:]
    /// Ocurrencias que el usuario ya detuvo hoy — no vuelven a sonar.
    private var stopped: Set<String> = []

    func configure(client: APIClient?) {
        self.client = client
        SoundPlayer.stopAlarm()
        timer?.invalidate()
        timer = nil
        firing = nil
        ticks = 0
        nextReminderAt = [:]
        stopped = []
        if client != nil {
            ensureWatching()
        }
    }

    /// Recibe la alarma explícitamente: el .alert(item:) de SwiftUI pone
    /// `firing` en nil ANTES de ejecutar la acción del botón, así que no se
    /// puede leer de self.firing (antes salía sin parar el sonido).
    func stopFiring(_ alarm: FiringAlarm) {
        SoundPlayer.stopAlarm()
        stopped.insert(alarm.key)
        nextReminderAt.removeValue(forKey: alarm.key)
        if firing?.key == alarm.key { firing = nil }
        // Avisa al servidor para que la web (y otros dispositivos) también la detengan.
        if let client {
            Task { _ = try? await client.requestRaw("alarmas/\(alarm.alarmId)/detener", method: "POST") }
        }
    }

    private func ensureWatching() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                await self.check()
                // Cada ~5 min se refrescan los avisos programados, por si se
                // creó o cambió una alarma desde la web.
                self.ticks += 1
                if self.ticks % 15 == 0 { await self.syncNotifications() }
            }
        }
        Task {
            await check()
            await syncNotifications()
        }
    }

    /// Reprograma los avisos locales de todas las alarmas activas, para que
    /// suenen aunque el app esté cerrado.
    func syncNotifications() async {
        guard let client else { return }
        if let alarmas: [Alarma] = try? await client.request("alarmas") {
            NotificationManager.shared.syncAlarmas(alarmas)
        }
    }

    private func check() async {
        guard let client else { return }
        struct UpcomingRaw: Decodable {
            @FlexibleInt var id: Int
            var name: String
            var time: String
            var sound: String?
            @FlexibleOptionalInt var reminderMinutes: Int?
            /// true si ya se detuvo hoy desde otro dispositivo (p.ej. la web).
            var detenida: Bool?
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
                let key = "\(alarma.id)_\(todayKey)_\(alarma.time)"

                // La detuvieron en otro dispositivo: se calla y se cierra el aviso aquí también.
                if alarma.detenida == true {
                    stopped.insert(key)
                    nextReminderAt.removeValue(forKey: key)
                    if firing?.key == key {
                        SoundPlayer.stopAlarm()
                        firing = nil
                    }
                    continue
                }

                guard nowMinutes >= alarmMinutes else { continue }
                if stopped.contains(key) { continue }
                if let nextAt = nextReminderAt[key], now < nextAt { continue }

                let reminderMinutes = max(1, alarma.reminderMinutes ?? 5)
                nextReminderAt[key] = now.addingTimeInterval(TimeInterval(reminderMinutes * 60))
                SoundPlayer.playAlarm(alarma.sound, defaultSound: AjustesStore.shared.sonidoAlarma)
                firing = FiringAlarm(alarmId: alarma.id, key: key, name: alarma.name, time: alarma.time)
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
