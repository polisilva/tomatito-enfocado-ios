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
                            // Botones explícitos al deslizar la fila — igual
                            // que Editar/Eliminar en Recordatorios o Mail,
                            // para no depender de tocar la fila entera.
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(alarma)
                                } label: {
                                    Label("Eliminar", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    editingAlarma = alarma
                                } label: {
                                    Label("Editar", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
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

    private func delete(_ alarma: Alarma) {
        alarmas.removeAll { $0.id == alarma.id }
        Task {
            try? await session.client.requestRaw("alarmas/\(alarma.id)", method: "DELETE")
        }
    }
}
