//
//  MiCuentaView.swift
//  TomatitoEnfocado
//
//  Tela "Mi cuenta": gestión y creación — no controla nada en marcha
//  (eso vive en AhoraMismoView).
//

import SwiftUI

struct MiCuentaView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var activeTimer: ActiveTimerStore
    @Binding var selectedTab: Int

    @State private var pomodoros: [Pomodoro] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCreate = false
    @State private var cuenta: CuentaInfo?
    @State private var nextAlarma: UpcomingAlarma?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cuenta?.displayName.isEmpty == false ? cuenta!.displayName : session.username)
                                .font(.headline)
                            Text(cuenta?.email ?? session.username)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(cuenta?.omkromConnected == true ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                Text(cuenta?.omkromConnected == true ? "Conectado a Omkrom" : (cuenta?.omkromStatusLabel ?? "Comprobando..."))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Salir") { session.logout() }
                            .font(.footnote)
                    }
                    .padding(.vertical, 4)
                }

                Section("Pomodoros guardados") {
                    if isLoading && pomodoros.isEmpty {
                        ProgressView()
                    } else if let errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(errorMessage).foregroundStyle(.red).font(.footnote)
                            Button("Reintentar") { Task { await load() } }
                        }
                    } else if pomodoros.isEmpty {
                        Text("Todavía no has creado ningún pomodoro.")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    } else {
                        ForEach(pomodoros) { pomodoro in
                            Button {
                                Task {
                                    await activeTimer.start(pomodoro: pomodoro)
                                    selectedTab = 1
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(pomodoro.name).font(.headline)
                                        Text("\(pomodoro.work) / \(pomodoro.shortBreak) / \(pomodoro.longBreak) min")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        if let lastUsed = pomodoro.lastUsedLabel {
                                            Text("Último uso: \(lastUsed)")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.red)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                        }
                        .onDelete(perform: delete)
                    }
                }

                Section {
                    Button {
                        showingCreate = true
                    } label: {
                        Label("Nuevo pomodoro", systemImage: "plus")
                    }
                }

                Section("Alarmas") {
                    if let nextAlarma {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(nextAlarma.name).font(.subheadline)
                                Text("Próxima: \(nextAlarma.time)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { true },
                                set: { _ in Task { await toggleNextAlarma() } }
                            ))
                            .labelsHidden()
                        }
                    } else {
                        Text("No tienes alarmas activas. Gestiónalas en la pestaña Alarmas.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Mi cuenta")
            .refreshable { await load() }
            .sheet(isPresented: $showingCreate) {
                CreatePomodoroView(onCreated: { Task { await load() } })
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
            pomodoros = try await session.client.request("pomodoros")
        } catch {
            errorMessage = error.localizedDescription
        }
        cuenta = try? await session.client.request("mi-cuenta")
        let alarmas: [UpcomingAlarma]? = try? await session.client.request("alarmas/upcoming")
        nextAlarma = alarmas?.first
    }

    private func toggleNextAlarma() async {
        guard let nextAlarma else { return }
        try? await session.client.requestRaw("alarmas/\(nextAlarma.id)/toggle", method: "POST")
        let alarmas: [UpcomingAlarma]? = try? await session.client.request("alarmas/upcoming")
        self.nextAlarma = alarmas?.first
    }

    private func delete(at offsets: IndexSet) {
        let idsToDelete = offsets.map { pomodoros[$0].id }
        pomodoros.remove(atOffsets: offsets)
        Task {
            for id in idsToDelete {
                try? await session.client.requestRaw("pomodoros/\(id)", method: "DELETE")
            }
        }
    }
}
