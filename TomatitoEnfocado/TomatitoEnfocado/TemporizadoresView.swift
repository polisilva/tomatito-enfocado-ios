//
//  TemporizadoresView.swift
//  TomatitoEnfocado
//
//  Tela "Temporizadores": plantillas de cuentas atrás. Se pueden lanzar
//  varios a la vez, sin cancelarse entre sí ni afectar al Pomodoro.
//

import SwiftUI

struct TemporizadoresView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var activeTemporizadores: ActiveTemporizadoresStore
    @Binding var selectedTab: Int

    @State private var temporizadores: [Temporizador] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCreate = false
    @State private var editingTemporizador: Temporizador?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && temporizadores.isEmpty {
                    ProgressView("Cargando...")
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage).foregroundStyle(.red)
                        Button("Reintentar") { Task { await load() } }
                    }
                } else {
                    List {
                        if temporizadores.isEmpty {
                            Section {
                                ContentUnavailableView(
                                    "Sin temporizadores",
                                    systemImage: "hourglass",
                                    description: Text("Todavía no has creado ningún temporizador.")
                                )
                            }
                            .listRowInsets(EdgeInsets())
                        } else {
                        Section {
                            ForEach(temporizadores) { temporizador in
                                HStack(spacing: 12) {
                                    Button {
                                        Task {
                                            await activeTemporizadores.start(temporizador: temporizador)
                                            selectedTab = 1
                                        }
                                    } label: {
                                        HStack(spacing: 12) {
                                            ZStack {
                                                Circle().fill(Color.red.opacity(0.12))
                                                Image(systemName: "hourglass")
                                                    .font(.system(size: 16))
                                                    .foregroundStyle(.red)
                                            }
                                            .frame(width: 36, height: 36)

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(temporizador.name).font(.headline)
                                                Text(temporizador.durationLabel ?? "\(temporizador.duration) s")
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                if let lastUsed = temporizador.lastUsedLabel {
                                                    Text("Último uso: \(lastUsed)")
                                                        .font(.caption)
                                                        .foregroundStyle(.tertiary)
                                                }
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.primary)

                                    Spacer()

                                    Button {
                                        editingTemporizador = temporizador
                                    } label: {
                                        Image(systemName: "pencil.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(.blue)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        Task {
                                            await activeTemporizadores.start(temporizador: temporizador)
                                            selectedTab = 1
                                        }
                                    } label: {
                                        Image(systemName: "play.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 4)
                                .contextMenu {
                                    Button {
                                        editingTemporizador = temporizador
                                    } label: {
                                        Label("Editar", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        delete(temporizador)
                                    } label: {
                                        Label("Eliminar", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        editingTemporizador = temporizador
                                    } label: {
                                        Label("Editar", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                            }
                            .onDelete(perform: delete)
                        }
                        }

                        // Botón fijo "+ Nuevo temporizador" — misma especificación
                        // que "+ Nuevo Pomodoro" en Mi cuenta.
                        Section {
                            Button {
                                showingCreate = true
                            } label: {
                                Label("Nuevo temporizador", systemImage: "plus")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .listRowInsets(EdgeInsets())
                        }
                        .listRowBackground(Color.clear)
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Temporizadores")
            .sheet(isPresented: $showingCreate) {
                CreateTemporizadorView(onCreated: { Task { await load() } })
                    .environmentObject(session)
            }
            .sheet(item: $editingTemporizador) { temporizador in
                CreateTemporizadorView(existing: temporizador, onCreated: { Task { await load() } })
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
            temporizadores = try await session.client.request("temporizadores")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        let idsToDelete = offsets.map { temporizadores[$0].id }
        temporizadores.remove(atOffsets: offsets)
        Task {
            for id in idsToDelete {
                try? await session.client.requestRaw("temporizadores/\(id)", method: "DELETE")
            }
        }
    }

    private func delete(_ temporizador: Temporizador) {
        temporizadores.removeAll { $0.id == temporizador.id }
        Task {
            try? await session.client.requestRaw("temporizadores/\(temporizador.id)", method: "DELETE")
        }
    }
}
