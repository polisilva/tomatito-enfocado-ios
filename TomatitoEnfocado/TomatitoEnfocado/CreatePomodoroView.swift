//
//  CreatePomodoroView.swift
//  TomatitoEnfocado
//
//  Formulario "Nuevo pomodoro" (abierto como sheet desde MiCuentaView).
//

import SwiftUI

private extension View {
    /// Caja redondeada gris clara para cada campo — mismo lenguaje visual
    /// que el mockup de referencia, en vez del Form nativo del sistema.
    func cardFieldStyle() -> some View {
        self.padding(12)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

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
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider().frame(width: 18)
            Button {
                if value > range.lowerBound { value -= 1 }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 15)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Color(.systemGray4))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

/// Campo numérico editable (se puede tocar y escribir) + CompactStepper al lado.
/// Mantiene su propio texto para no sufrir el problema de SwiftUI donde un
/// TextField(value:formatter:) se queda en blanco mientras se está borrando.
private struct MinutesField: View {
    var icon: String? = nil
    var label: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...600

    @State private var text: String = ""

    var body: some View {
        HStack {
            if let icon {
                Image(systemName: icon).foregroundStyle(.secondary)
            }
            Text(label)
            Spacer()
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 40)
                .onChange(of: text) { _, newValue in
                    // Filtra cualquier carácter que no sea dígito — el teclado
                    // numérico ya bloquea letras en un dispositivo real, pero un
                    // teclado físico (ej. en el Simulador) puede escribir cualquier
                    // cosa, así que también se sanea aquí.
                    let digitsOnly = newValue.filter(\.isNumber)
                    if digitsOnly != newValue {
                        text = digitsOnly
                        return
                    }
                    if let parsed = Int(digitsOnly), range.contains(parsed) {
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

/// Checkbox cuadrado, como en el mockup — en vez del Toggle/switch nativo.
private struct CheckboxRow: View {
    var label: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn ? .red : .secondary)
                Text(label).foregroundStyle(.primary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

struct CreatePomodoroView: View {
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    /// Si viene un pomodoro existente, el formulario edita (PUT) en vez de
    /// crear (POST) — especificación "Crear / Editar Pomodoro".
    var existing: Pomodoro? = nil
    var pomodoros: [Pomodoro] = []
    var onCreated: () -> Void
    /// Tocar un resultado de la búsqueda inicia ese pomodoro directamente —
    /// mismo comportamiento que el ▶ en "Mi cuenta" — y cierra esta hoja.
    var onStart: ((Pomodoro) -> Void)? = nil

    @State private var searchText: String = ""
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

    private func populateFromExisting() {
        guard let existing else { return }
        name = existing.name
        work = existing.work
        shortBreak = existing.shortBreak
        longBreak = existing.longBreak
        cycles = existing.cycles
        repetitionsText = existing.repetitions.map(String.init) ?? ""
        autoStart = existing.autoStart != 0
        pauseOnEnd = existing.pauseOnEnd != 0
        sound = existing.sound ?? "default"
        vibration = existing.vibration != 0
    }

    private let soundOptions: [(key: String, label: String)] = [
        ("default", "Predeterminado (según Ajustes)"),
        ("clasico", "Clásico"),
        ("campana", "Campana"),
        ("digital", "Digital"),
        ("suave", "Suave"),
        ("silent", "Silencioso"),
    ]

    private var filteredPomodoros: [Pomodoro] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        return pomodoros.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if existing == nil {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Buscar entre tus pomodoros guardados...", text: $searchText)
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .cardFieldStyle()

                        if !filteredPomodoros.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(Array(filteredPomodoros.enumerated()), id: \.element.id) { index, pomodoro in
                                    if index > 0 { Divider().padding(.leading) }
                                    Button {
                                        onStart?(pomodoro)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(pomodoro.name).font(.subheadline.weight(.medium))
                                                Text("\(pomodoro.work) / \(pomodoro.shortBreak) / \(pomodoro.longBreak) min")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "play.circle.fill")
                                                .foregroundStyle(.red)
                                        }
                                        .padding(12)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(onStart == nil)
                                }
                            }
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    Text(existing == nil ? "Crear pomodoro" : "Editar pomodoro")
                        .font(.title3.bold())

                    TextField("Ej: Estudio, Trabajo...", text: $name)
                        .cardFieldStyle()

                    MinutesField(icon: "clock", label: "Trabajo", value: $work, range: 1...180)
                        .cardFieldStyle()
                    MinutesField(icon: "clock", label: "Descanso corto", value: $shortBreak, range: 1...60)
                        .cardFieldStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Cada")
                            CompactStepper(value: $cycles, range: 1...12)
                            Text("ciclos → Descanso largo")
                            Spacer()
                        }
                        Divider()
                        MinutesField(label: "Descanso largo", value: $longBreak, range: 1...120)
                    }
                    .cardFieldStyle()

                    DisclosureGroup(isExpanded: $showingAdvanced) {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
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
                            }
                            CheckboxRow(label: "Auto-iniciar siguiente fase", isOn: $autoStart)
                            CheckboxRow(label: "Pausar al finalizar sesión", isOn: $pauseOnEnd)
                            HStack {
                                Text("Sonido")
                                Spacer()
                                Picker("", selection: $sound) {
                                    ForEach(soundOptions, id: \.key) { option in
                                        Text(option.label).tag(option.key)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                            CheckboxRow(label: "Vibración", isOn: $vibration)
                        }
                        .padding(.top, 10)
                    } label: {
                        Text("Opciones avanzadas").fontWeight(.medium)
                    }
                    .tint(.primary)
                    .cardFieldStyle()

                    HStack(spacing: 12) {
                        Button {
                            Task { await save() }
                        } label: {
                            HStack {
                                if isSaving {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(existing == nil ? "Guardar pomodoro" : "Guardar cambios").fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .foregroundStyle(.white)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)

                        Button("Cancelar") { dismiss() }
                            .buttonStyle(.bordered)
                            .tint(.gray)
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)

                    Text("Ejemplo: \(work) min trabajo → \(shortBreak) min descanso corto → cada \(cycles) ciclos, \(longBreak) min descanso largo\(repetitionsText.trimmingCharacters(in: .whitespaces).isEmpty ? " (en bucle)" : "")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardFieldStyle()

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { populateFromExisting() }
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
            if let existing {
                let _: Pomodoro = try await session.client.request(
                    "pomodoros/\(existing.id)",
                    method: "PUT",
                    body: body
                )
            } else {
                let _: Pomodoro = try await session.client.request(
                    "pomodoros",
                    method: "POST",
                    body: body
                )
            }
            onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
