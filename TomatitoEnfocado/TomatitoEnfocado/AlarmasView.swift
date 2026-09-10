//
//  AlarmasView.swift
//  TomatitoEnfocado
//
//  Tela "Alarmas": gestión completa (listar, activar/desactivar, editar,
//  eliminar, crear).
//

import SwiftUI

struct AlarmasView: View {
    @EnvironmentObject var session: SessionStore

    @State private var alarmas: [Alarma] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCreate = false
    @State private var editingAlarma: Alarma?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && alarmas.isEmpty {
                    ProgressView("Cargando...")
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage).foregroundStyle(.red)
                        Button("Reintentar") { Task { await load() } }
                    }
                } else if alarmas.isEmpty {
                    ContentUnavailableView(
                        "Sin alarmas",
                        systemImage: "alarm",
                        description: Text("Todavía no has creado ninguna alarma.")
                    )
                } else {
                    List {
                        ForEach(alarmas) { alarma in
                            Button {
                                editingAlarma = alarma
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(alarma.name).font(.headline)
                                        Text(alarma.timeLabel ?? alarma.time)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Text(alarma.repeatLabel ?? alarma.repeatMode)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { alarma.isOn },
                                        set: { _ in Task { await toggle(alarma) } }
                                    ))
                                    .labelsHidden()
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                        }
                        .onDelete(perform: delete)
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Alarmas")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreate) {
                AlarmaFormView(existing: nil, onSaved: { Task { await load() } })
                    .environmentObject(session)
            }
            .sheet(item: $editingAlarma) { alarma in
                AlarmaFormView(existing: alarma, onSaved: { Task { await load() } })
                    .environmentObject(session)
            }
        }
        .task { await load() }
    }

    private func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            alarmas = try await session.client.request("alarmas")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggle(_ alarma: Alarma) async {
        do {
            try await session.client.requestRaw("alarmas/\(alarma.id)/toggle", method: "POST")
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        let idsToDelete = offsets.map { alarmas[$0].id }
        alarmas.remove(atOffsets: offsets)
        Task {
            for id in idsToDelete {
                try? await session.client.requestRaw("alarmas/\(id)", method: "DELETE")
            }
        }
    }
}
