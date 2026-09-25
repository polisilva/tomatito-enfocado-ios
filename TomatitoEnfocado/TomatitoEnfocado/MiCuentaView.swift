//
//  MiCuentaView.swift
//  TomatitoEnfocado
//
//  Tela "Mi cuenta": gestión y creación — no controla nada en marcha
//  (eso vive en AhoraMismoView).
//

import SwiftUI
import CryptoKit

/// El backend todavía no manda una foto de perfil, pero WordPress usa Gravatar
/// por convención — un hash del email alcanza para pedir la imagen real (o un
/// avatar identicon si la persona no tiene Gravatar configurado), sin tocar la API.
private func gravatarURL(for email: String, size: Int = 160) -> URL? {
    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return nil }
    let digest = Insecure.MD5.hash(data: Data(trimmed.utf8))
    let hash = digest.map { String(format: "%02x", $0) }.joined()
    return URL(string: "https://www.gravatar.com/avatar/\(hash)?s=\(size)&d=identicon")
}

struct MiCuentaView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var activeTimer: ActiveTimerStore
    @Binding var selectedTab: Int

    @State private var pomodoros: [Pomodoro] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCreate = false
    @State private var editingPomodoro: Pomodoro?
    @State private var cuenta: CuentaInfo?
    @State private var nextAlarma: UpcomingAlarma?
    @State private var showingPerfil = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Button {
                            showingPerfil = true
                        } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: URL(string: cuenta?.avatarURL ?? "") ?? gravatarURL(for: cuenta?.email ?? session.username)) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        Image(systemName: "person.crop.circle.fill")
                                            .resizable()
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
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
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture { showingPerfil = true }
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
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(Color.red.opacity(0.12))
                                        Text("🍅").font(.system(size: 18))
                                    }
                                    .frame(width: 36, height: 36)

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
                            .swipeActions(edge: .leading) {
                                Button {
                                    editingPomodoro = pomodoro
                                } label: {
                                    Label("Editar", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }

                Section {
                    Button {
                        showingCreate = true
                    } label: {
                        Label("Nuevo pomodoro", systemImage: "plus")
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        Text("🍅")
                        Text("Tomatito").fontWeight(.bold).foregroundStyle(.red)
                        Text("Enfocado").fontWeight(.bold).foregroundStyle(.primary)
                    }
                    .font(.title3)
                }
            }
            .refreshable { await load() }
            .sheet(isPresented: $showingCreate) {
                CreatePomodoroView(
                    pomodoros: pomodoros,
                    onCreated: { Task { await load() } },
                    onStart: { pomodoro in
                        showingCreate = false
                        Task {
                            await activeTimer.start(pomodoro: pomodoro)
                            selectedTab = 1
                        }
                    }
                )
                .environmentObject(session)
            }
            .sheet(item: $editingPomodoro) { pomodoro in
                CreatePomodoroView(
                    existing: pomodoro,
                    onCreated: { Task { await load() } }
                )
                .environmentObject(session)
            }
            .sheet(isPresented: $showingPerfil) {
                PerfilView()
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
