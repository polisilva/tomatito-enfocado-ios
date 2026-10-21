//
//  NotificationManager.swift
//  TomatitoEnfocado
//
//  Notificaciones locales: el banner que aparece cuando termina una fase de
//  pomodoro, un temporizador o suena una alarma — también con el app en
//  segundo plano o la pantalla bloqueada, porque se programan por adelantado
//  para la hora exacta en que terminan (como cualquier app de temporizador).
//
//  Con el app abierto el sonido lo reproduce SoundPlayer; el banner se
//  muestra igual, pero sin sonido propio para no duplicarlo. Las alarmas
//  además tienen su aviso "Detener alarma" dentro del app (AlarmScheduler).
//

import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func setup() {
        center.delegate = self
        installSoundsForNotifications()
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - Sonidos

    /// Los sonidos de notificación personalizados deben estar en
    /// Library/Sounds (o en la raíz del bundle); los .caf viajan dentro de
    /// la carpeta Sounds/ del bundle, así que se copian al arrancar.
    private func installSoundsForNotifications() {
        let fm = FileManager.default
        guard let library = fm.urls(for: .libraryDirectory, in: .userDomainMask).first,
              let bundled = Bundle.main.resourceURL?.appendingPathComponent("Sounds"),
              let files = try? fm.contentsOfDirectory(at: bundled, includingPropertiesForKeys: nil) else { return }
        let target = library.appendingPathComponent("Sounds")
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        for file in files where file.pathExtension == "caf" {
            let destination = target.appendingPathComponent(file.lastPathComponent)
            if !fm.fileExists(atPath: destination.path) {
                try? fm.copyItem(at: file, to: destination)
            }
        }
    }

    private func notificationSound(_ sound: String?, defaultSound: String) -> UNNotificationSound? {
        let key = (sound?.isEmpty ?? true) || sound == "default" ? defaultSound : sound!
        switch key {
        case "silent": return nil
        case "vibracion": return .default
        default: return UNNotificationSound(named: UNNotificationSoundName("\(key).caf"))
        }
    }

    // MARK: - Pomodoros y temporizadores (cuenta atrás)

    func schedule(id: String, title: String, body: String, after seconds: Int, sound: String?, defaultSound: String) {
        guard AjustesStore.shared.notificacionesActivas else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = notificationSound(sound, defaultSound: defaultSound)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, seconds)), repeats: false)
        // Mismo identificador = reemplaza la notificación pendiente anterior.
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func cancel(ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func cancelAll(prefix: String) {
        center.getPendingNotificationRequests { [center] requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    func schedulePomodoro(_ item: ActivePomodoroItem) {
        let body: String
        switch item.phase {
        case "work": body = "¡Trabajo terminado! \(item.nextPhaseText)"
        case "short_break": body = "Descanso terminado. ¡Vuelve al trabajo!"
        default: body = "Descanso largo terminado."
        }
        schedule(
            id: "pomodoro-\(item.timerId)",
            title: "🍅 \(item.name)",
            body: body,
            after: item.secondsLeft,
            sound: item.sound,
            defaultSound: AjustesStore.shared.sonidoPomodoro
        )
    }

    func scheduleTemporizador(_ item: ActiveTemporizadorItem) {
        schedule(
            id: "temporizador-\(item.timerId)",
            title: "⏳ \(item.name)",
            body: "¡Tiempo terminado!",
            after: item.secondsLeft,
            sound: item.sound,
            defaultSound: AjustesStore.shared.sonidoTemporizador
        )
    }

    // MARK: - Alarmas

    /// Reprograma todas las alarmas activas. Se llama cada vez que cambia la
    /// lista (abrir Alarmas, crear, editar, activar/desactivar, eliminar) y al
    /// iniciar sesión.
    func syncAlarmas(_ alarmas: [Alarma]) {
        center.getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            let old = requests.map(\.identifier).filter { $0.hasPrefix("alarma-") }
            self.center.removePendingNotificationRequests(withIdentifiers: old)
            guard AjustesStore.shared.notificacionesActivas else { return }
            for alarma in alarmas where alarma.isOn {
                self.scheduleAlarma(alarma)
            }
        }
    }

    private func scheduleAlarma(_ alarma: Alarma) {
        let parts = alarma.time.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return }

        // Weekday de Calendar: 1 = domingo … 7 = sábado.
        var weekdays: [Int] = []
        switch alarma.repeatMode {
        case "daily":
            weekdays = []
        case "weekdays":
            weekdays = [2, 3, 4, 5, 6]
        case "custom":
            let flags: [(Int, Int)] = [
                (2, alarma.mon), (3, alarma.tue), (4, alarma.wed), (5, alarma.thu),
                (6, alarma.fri), (7, alarma.sat), (1, alarma.sun),
            ]
            weekdays = flags.filter { $0.1 != 0 }.map(\.0)
            if weekdays.isEmpty { return }
        default:
            weekdays = []
        }
        let repeats = alarma.repeatMode != "none"

        // Vigencia (fecha de inicio / límite). Los avisos solo se programan si hoy
        // está dentro del período; se reevalúan en cada sincronización.
        let today = Self.isoDay.string(from: Date())
        if let end = alarma.endDate, !end.isEmpty, end < today { return }
        if let start = alarma.startDate, !start.isEmpty, start > today { return }

        let content = UNMutableNotificationContent()
        content.title = "⏰ \(alarma.name)"
        content.body = String(format: "%02d:%02d", hour, minute)
        content.sound = notificationSound(alarma.sound, defaultSound: AjustesStore.shared.sonidoAlarma)

        func add(_ suffix: String, weekday: Int?) {
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            components.second = 0
            components.weekday = weekday
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
            center.add(UNNotificationRequest(identifier: "alarma-\(alarma.id)-\(suffix)", content: content, trigger: trigger))
        }

        if weekdays.isEmpty {
            add("all", weekday: nil)
        } else {
            for day in weekdays { add("d\(day)", weekday: day) }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Primer plano: las alarmas ya muestran el alerta "Detener alarma" de
        // AlarmScheduler, así que no se duplica el banner (solo queda en la lista).
        // Pomodoros y temporizadores sí muestran el banner.
        // Sin .sound: el audio ya lo reproduce SoundPlayer dentro del app.
        if notification.request.identifier.hasPrefix("alarma-") {
            completionHandler([.list])
        } else {
            completionHandler([.banner, .list])
        }
    }
}
