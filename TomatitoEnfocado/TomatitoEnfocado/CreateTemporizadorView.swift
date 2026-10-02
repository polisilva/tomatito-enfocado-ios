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

    var existing: Temporizador?
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
            .navigationTitle(existing == nil ? "Nuevo temporizador" : "Editar temporizador")
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
        .onAppear { populateFromExisting() }
    }

    private func populateFromExisting() {
        guard let existing else { return }
        name = existing.name
        minutes = max(1, min(180, existing.duration / 60))
        sound = existing.sound ?? "default"
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        let body: [String: Any] = ["name": name, "duration": minutes * 60, "sound": sound]
        do {
            if let existing {
                let _: Temporizador = try await session.client.request(
                    "temporizadores/\(existing.id)", method: "PUT", body: body
                )
            } else {
                let _: Temporizador = try await session.client.request(
                    "temporizadores", method: "POST", body: body
                )
            }
            onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
