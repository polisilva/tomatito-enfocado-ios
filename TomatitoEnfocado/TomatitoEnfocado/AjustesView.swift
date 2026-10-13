//
//  AjustesView.swift
//  TomatitoEnfocado
//
//  Pantalla "Ajustes": las mismas preferencias que la página /ajustes de la
//  web (idioma, formato de hora, tema, notificaciones y sonidos
//  predeterminados), guardadas en el servidor — así web y móvil comparten
//  la configuración. AjustesStore.shared las deja disponibles al resto del
//  app (sonidos por defecto, formato de hora, tema, avisos).
//

import SwiftUI

final class AjustesStore: ObservableObject {
    static let shared = AjustesStore()

    @Published var hora: String { didSet { cache() } }
    @Published var tema: String { didSet { cache() } }
    @Published var notificaciones: String { didSet { cache() } }
    @Published var sonidoPomodoro: String { didSet { cache() } }
    @Published var sonidoTemporizador: String { didSet { cache() } }
    @Published var sonidoAlarma: String { didSet { cache() } }

    var notificacionesActivas: Bool { notificaciones != "off" }

    /// Cambia cuando cualquier ajuste cambia — la pantalla lo usa para guardar.
    var signature: String {
        [hora, tema, notificaciones, sonidoPomodoro, sonidoTemporizador, sonidoAlarma].joined(separator: "|")
    }

    private static let key = "tomatito_ajustes_cache"

    // Se parte de lo último conocido (UserDefaults) para que el tema y los
    // sonidos sean correctos desde el arranque, antes de que llegue la red.
    // Los valores por defecto son los mismos que usa el servidor.
    private init() {
        let saved = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        hora = saved["hora"] ?? "24h"
        tema = saved["tema"] ?? "claro"
        notificaciones = saved["notificaciones"] ?? "on"
        sonidoPomodoro = saved["sonidoPomodoro"] ?? "clasico"
        sonidoTemporizador = saved["sonidoTemporizador"] ?? "digital"
        sonidoAlarma = saved["sonidoAlarma"] ?? "campana"
    }

    private func cache() {
        UserDefaults.standard.set([
            "hora": hora, "tema": tema, "notificaciones": notificaciones,
            "sonidoPomodoro": sonidoPomodoro, "sonidoTemporizador": sonidoTemporizador,
            "sonidoAlarma": sonidoAlarma,
        ], forKey: Self.key)
    }

    @MainActor
    func load(client: APIClient) async {
        guard let remote: AjustesInfo = try? await client.request("ajustes") else { return }
        hora = remote.hora
        tema = remote.tema
        notificaciones = remote.notificaciones
        sonidoPomodoro = remote.sonidoPomodoro
        sonidoTemporizador = remote.sonidoTemporizador
        sonidoAlarma = remote.sonidoAlarma
    }

    @MainActor
    func save(client: APIClient) async {
        let body: [String: Any] = [
            "hora": hora, "tema": tema, "notificaciones": notificaciones,
            "sonido_pomodoro": sonidoPomodoro,
            "sonido_temporizador": sonidoTemporizador,
            "sonido_alarma": sonidoAlarma,
        ]
        _ = try? await client.requestRaw("ajustes", method: "POST", body: body)
    }
}

/// "14:30" → "2:30 PM" si el usuario eligió formato 12h (igual que la web).
func formatHora(_ hhmm: String) -> String {
    guard AjustesStore.shared.hora == "12h" else { return hhmm }
    let parts = hhmm.split(separator: ":")
    guard parts.count >= 2, let hour = Int(parts[0]) else { return hhmm }
    let suffix = hour >= 12 ? "PM" : "AM"
    let h12 = hour % 12 == 0 ? 12 : hour % 12
    return "\(h12):\(parts[1]) \(suffix)"
}

struct AjustesView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var activeTimer: ActiveTimerStore
    @EnvironmentObject var activeTemporizadores: ActiveTemporizadoresStore
    @EnvironmentObject var alarmScheduler: AlarmScheduler
    @ObservedObject private var ajustes = AjustesStore.shared

    private let sonidos: [(key: String, label: String)] = [
        ("clasico", "Clásico"), ("campana", "Campana"), ("digital", "Digital"),
        ("suave", "Suave"), ("silent", "Silencio"),
    ]
    private let sonidosAlarma: [(key: String, label: String)] = [
        ("clasico", "Clásico"), ("campana", "Campana"), ("digital", "Digital"),
        ("suave", "Suave"), ("peeeem", "Alarma insistente"), ("silent", "Silencio"),
    ]

    var body: some View {
        Form {
            Section("Idioma y región") {
                LabeledContent("Idioma", value: "Español (España)")
                Picker("Formato de hora", selection: $ajustes.hora) {
                    Text("24h (14:30)").tag("24h")
                    Text("12h (2:30 PM)").tag("12h")
                }
            }

            Section("Apariencia") {
                Picker("Tema", selection: $ajustes.tema) {
                    Text("Claro").tag("claro")
                    Text("Oscuro").tag("oscuro")
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle("Notificaciones", isOn: Binding(
                    get: { ajustes.notificacionesActivas },
                    set: { ajustes.notificaciones = $0 ? "on" : "off" }
                ))
            } header: {
                Text("Notificaciones")
            } footer: {
                Text("Avisos cuando termina un pomodoro, un temporizador o suena una alarma.")
            }

            Section {
                soundPicker("Pomodoro", selection: $ajustes.sonidoPomodoro, options: sonidos)
                soundPicker("Temporizador", selection: $ajustes.sonidoTemporizador, options: sonidos)
                soundPicker("Alarma", selection: $ajustes.sonidoAlarma, options: sonidosAlarma)
            } header: {
                Text("Sonidos predeterminados")
            } footer: {
                Text("Se usan cuando un pomodoro, temporizador o alarma está en \"Predeterminado\".")
            }
        }
        .navigationTitle("Ajustes")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: ajustes.signature) { _, _ in
            Task { await persist() }
        }
    }

    private func soundPicker(_ title: String, selection: Binding<String>, options: [(key: String, label: String)]) -> some View {
        HStack {
            Picker(title, selection: selection) {
                ForEach(options, id: \.key) { Text($0.label).tag($0.key) }
            }
            Button {
                SoundPlayer.play(selection.wrappedValue, defaultSound: selection.wrappedValue)
            } label: {
                Image(systemName: "play.circle.fill").font(.title3).foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
    }

    private func persist() async {
        await ajustes.save(client: session.client)
        if ajustes.notificacionesActivas {
            // Se vuelven a programar los avisos que se habían quitado.
            await alarmScheduler.syncNotifications()
            await activeTimer.resyncFromServer()
            await activeTemporizadores.resyncFromServer()
        } else {
            NotificationManager.shared.cancelAll(prefix: "")
        }
    }
}
