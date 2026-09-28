//
//  CreateTemporizadorView.swift
//  TomatitoEnfocado
//
//  Formulario "Nuevo temporizador" (sheet desde TemporizadoresView).
//

import SwiftUI

struct CreateTemporizadorView: View {
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    var onCreated: () -> Void

    @State private var name: String = ""
    @State private var minutes: Int = 10
    @State private var sound: String = "default"
    @State private var isSaving = false
    @State private var errorMessage: String?

    // Mismas opciones que el picker de temporizadores en la web.
    private let soundOptions: [(key: String, label: String)] = [
        ("default", "Predeterminado"),
        ("clasico", "Clásico"),
        ("campana", "Campana"),
        ("digital", "Digital"),
        ("suave", "Suave"),
        ("vibracion", "Solo vibración"),
        ("silent", "Silencio"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("Ej: Ejercicio, Descanso...", text: $name)
                }
                Section("Duración") {
                    Stepper("\(minutes) min", value: $minutes, in: 1...180)
                }
                Section("Sonido") {
                    Picker("Sonido", selection: $sound) {
                        ForEach(soundOptions, id: \.key) { option in
                            Text(option.label).tag(option.key)
                        }
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("Nuevo temporizador")
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
            let _: Temporizador = try await session.client.request(
                "temporizadores",
                method: "POST",
                body: ["name": name, "duration": minutes * 60, "sound": sound]
            )
            onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
