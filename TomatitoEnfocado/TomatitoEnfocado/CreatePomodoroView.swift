//
//  CreatePomodoroView.swift
//  TomatitoEnfocado
//
//  Formulario "Nuevo pomodoro" (abierto como sheet desde MiCuentaView).
//

import SwiftUI

struct CreatePomodoroView: View {
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    var onCreated: () -> Void

    @State private var name: String = ""
    @State private var work: Int = 25
    @State private var shortBreak: Int = 5
    @State private var longBreak: Int = 15
    @State private var cycles: Int = 4
    @State private var repetitionsText: String = ""
    @State private var showingAdvanced = false
    @State private var autoStart = false
    @State private var pauseOnEnd = true
    @State private var sound: String = "default"
    @State private var vibration = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let soundOptions: [(key: String, label: String)] = [
        ("default", "Predeterminado (según Ajustes)"),
        ("clasico", "Clásico"),
        ("campana", "Campana"),
        ("digital", "Digital"),
        ("suave", "Suave"),
        ("silent", "Silencioso"),
    ]

    private static let minutesFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        return formatter
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("Ej: Estudio, Trabajo...", text: $name)
                }

                Section("Duración (minutos)") {
                    minutesRow("Trabajo", value: $work)
                    minutesRow("Descanso corto", value: $shortBreak)
                }

                Section {
                    HStack {
                        Text("Cada")
                        TextField("", value: $cycles, formatter: Self.minutesFormatter)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 40)
                        Text("ciclos → descanso largo")
                        Spacer()
                    }
                    minutesRow("Descanso largo", value: $longBreak)
                }

                DisclosureGroup("Opciones avanzadas", isExpanded: $showingAdvanced) {
                    HStack {
                        Text("Repetir secuencia")
                        Spacer()
                        TextField("∞", text: $repetitionsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                    Text("Vacío = en bucle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Auto-iniciar siguiente fase", isOn: $autoStart)
                    Toggle("Pausar al finalizar sesión", isOn: $pauseOnEnd)

                    Picker("Sonido", selection: $sound) {
                        ForEach(soundOptions, id: \.key) { option in
                            Text(option.label).tag(option.key)
                        }
                    }
                    Toggle("Vibración", isOn: $vibration)
                }

                Section {
                    Text("Ejemplo: \(work) min trabajo → \(shortBreak) min descanso corto → cada \(cycles) ciclos, \(longBreak) min descanso largo\(repetitionsText.trimmingCharacters(in: .whitespaces).isEmpty ? " (en bucle)" : "")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .navigationTitle("Nuevo pomodoro")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Guardar")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func minutesRow(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", value: value, formatter: Self.minutesFormatter)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 50)
            Text("min").foregroundStyle(.secondary)
        }
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            var body: [String: Any] = [
                "name": name,
                "work": work,
                "short_break": shortBreak,
                "long_break": longBreak,
                "cycles": cycles,
                "auto_start": autoStart ? 1 : 0,
                "pause_on_end": pauseOnEnd ? 1 : 0,
                "sound": sound,
                "vibration": vibration ? 1 : 0,
            ]
            // Vacío = en bucle: se omite "repetitions" para que el servidor
            // lo guarde como null, en vez de forzar un número de vueltas.
            if let repetitions = Int(repetitionsText.trimmingCharacters(in: .whitespaces)), repetitions > 0 {
                body["repetitions"] = repetitions
            }
            let _: Pomodoro = try await session.client.request(
                "pomodoros",
                method: "POST",
                body: body
            )
            onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
