//
//  CreatePomodoroView.swift
//  TomatitoEnfocado
//
//  Formulario "Nuevo pomodoro" (abierto como sheet desde MiCuentaView).
//

import SwiftUI

/// Flechas compactas de subir/bajar pegadas al campo, como el <input type="number">
/// del sitio web — más discretas que un Stepper normal de SwiftUI.
private struct CompactStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int>

    var body: some View {
        VStack(spacing: 0) {
            Button {
                if value < range.upperBound { value += 1 }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 15)
            }
            Divider().frame(width: 18)
            Button {
                if value > range.lowerBound { value -= 1 }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 15)
            }
        }
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

/// Campo numérico editable (se puede tocar y escribir) + CompactStepper al lado.
/// Mantiene su propio texto para no sufrir el problema de SwiftUI donde un
/// TextField(value:formatter:) se queda en blanco mientras se está borrando.
private struct MinutesField: View {
    var label: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...600

    @State private var text: String = ""

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 40)
                .onChange(of: text) { _, newValue in
                    if let parsed = Int(newValue), range.contains(parsed) {
                        value = parsed
                    }
                }
            CompactStepper(value: $value, range: range)
            Text("min").foregroundStyle(.secondary)
        }
        .onAppear { text = String(value) }
        .onChange(of: value) { _, newValue in
            if text != String(newValue) { text = String(newValue) }
        }
    }
}

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

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("Ej: Estudio, Trabajo...", text: $name)
                }

                Section("Duración (minutos)") {
                    MinutesField(label: "Trabajo", value: $work, range: 1...180)
                    MinutesField(label: "Descanso corto", value: $shortBreak, range: 1...60)
                }

                Section {
                    HStack {
                        Text("Cada")
                        Spacer()
                        CompactStepper(value: $cycles, range: 1...12)
                            .padding(.trailing, 4)
                        Text("\(cycles) ciclos → descanso largo")
                    }
                    MinutesField(label: "Descanso largo", value: $longBreak, range: 1...120)
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
