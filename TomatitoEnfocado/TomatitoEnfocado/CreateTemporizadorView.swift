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
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("Ej: Ejercicio, Descanso...", text: $name)
                }
                Section("Duración") {
                    Stepper("\(minutes) min", value: $minutes, in: 1...180)
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
                body: ["name": name, "duration": minutes * 60]
            )
            onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
