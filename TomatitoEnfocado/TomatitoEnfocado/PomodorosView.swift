//
//  PomodorosView.swift
//  TomatitoEnfocado
//
//  Pestaña "Pomodoros": los mismos datos que la página Pomodoros de la web —
//  búsqueda, filtros, orden, filas con tiempo restante / duración / último uso,
//  acciones (iniciar, editar, eliminar o pausar, detener, reiniciar), detalles
//  desplegables y el contador "Mostrando X de Y". En el móvil la paginación de
//  la tabla se sustituye por una lista que se desplaza.
//

import SwiftUI

private enum PomodoroFilter: String, CaseIterable, Identifiable {
    case todos, recientes, nunca
    var id: String { rawValue }
    var label: String {
        switch self {
        case .todos: return "Todos"
        case .recientes: return "Recientes"
        case .nunca: return "Nunca usados"
        }
    }
}

private enum PomodoroSort: String, CaseIterable, Identifiable {
    case recientes, nombre, duracion
    var id: String { rawValue }
    var label: String {
        switch self {
        case .recientes: return "Recientes"
        case .nombre: return "Nombre"
        case .duracion: return "Duración"
        }
    }
}

struct PomodorosView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var activeTimer: ActiveTimerStore

    @State private var pomodoros: [Pomodoro] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var search = ""
    @State private var filter: PomodoroFilter = .todos
    @State private var sort: PomodoroSort = .recientes
    @State private var expanded: Set<Int> = []
    @State private var showingCreate = false
    @State private var editingPomodoro: Pomodoro?
    @State private var pendingDelete: Pomodoro?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private func lastUsedDate(_ p: Pomodoro) -> Date? {
        guard let raw = p.lastUsedAt, !raw.isEmpty else { return nil }
        return Self.dateFormatter.date(from: raw)
    }

    /// Búsqueda + filtro + orden, igual que `renderPomodoros()` en la web.
    private var filtered: [Pomodoro] {
        var list = pomodoros.filter {
            search.trimmingCharacters(in: .whitespaces).isEmpty
                || $0.name.localizedCaseInsensitiveContains(search.trimmingCharacters(in: .whitespaces))
        }
        switch filter {
        case .todos: break
        case .recientes:
            list = list.filter {
                guard let date = lastUsedDate($0) else { return false }
                return Date().timeIntervalSince(date) <= 7 * 24 * 3600
            }
        case .nunca:
            list = list.filter { lastUsedDate($0) == nil }
        }
        switch sort {
        case .nombre: list.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .duracion: list.sort { $0.work > $1.work }
        case .recientes: list.sort { (lastUsedDate($0) ?? .distantPast) > (lastUsedDate($1) ?? .distantPast) }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Picker("Filtro", selection: $filter) {
                            ForEach(PomodoroFilter.allCases) { Text($0.label).tag($0) }
                        }
                        Spacer()
                        Picker("Orden", selection: $sort) {
                            ForEach(PomodoroSort.allCases) { Text("Ordenar: \($0.label)").tag($0) }
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Section {
                    if isLoading && pomodoros.isEmpty {
                        ProgressView()
                    } else if let errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(errorMessage).foregroundStyle(.red).font(.footnote)
                            Button("Reintentar") { Task { await load() } }
                        }
                    } else if filtered.isEmpty {
                        Text("No se han encontrado pomodoros.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filtered) { pomodoro in
                            PomodoroRow(
                                pomodoro: pomodoro,
                                active: activeTimer.items.first { $0.pomodoroId == pomodoro.id },
                                isExpanded: expanded.contains(pomodoro.id),
                                onToggleExpand: {
                                    if expanded.contains(pomodoro.id) { expanded.remove(pomodoro.id) }
                                    else { expanded.insert(pomodoro.id) }
                                },
                                onEdit: { editingPomodoro = pomodoro },
                                onDelete: { pendingDelete = pomodoro }
                            )
                        }
                    }
                } footer: {
                    Text("Mostrando \(filtered.count) de \(pomodoros.count) pomodoros guardados")
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
            }
            .navigationTitle("Pomodoros")
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar...")
            .refreshable {
                await load()
                await activeTimer.resyncFromServer()
            }
            .task { await load() }
            .task { await resyncLoop() }
            // Al iniciar/terminar un pomodoro cambia "último uso": se recarga la lista.
            .onChange(of: activeTimer.items.count) { _, _ in Task { await load() } }
            .sheet(isPresented: $showingCreate) {
                CreatePomodoroView(
                    pomodoros: pomodoros,
                    onCreated: { Task { await load() } },
                    onStart: { pomodoro in
                        showingCreate = false
                        Task { await activeTimer.start(pomodoro: pomodoro) }
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
            .confirmationDialog(
                "¿Eliminar este pomodoro?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { pomodoro in
                Button("Eliminar \"\(pomodoro.name)\"", role: .destructive) { delete(pomodoro) }
                Button("Cancelar", role: .cancel) {}
            }
        }
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
    }

    private func delete(_ pomodoro: Pomodoro) {
        pomodoros.removeAll { $0.id == pomodoro.id }
        Task { try? await session.client.requestRaw("pomodoros/\(pomodoro.id)", method: "DELETE") }
    }

    /// Mientras la pestaña está visible, se contrasta con el servidor cada 15 s.
    private func resyncLoop() async {
        while !Task.isCancelled {
            await activeTimer.resyncFromServer()
            try? await Task.sleep(nanoseconds: 15_000_000_000)
        }
    }
}

private struct PomodoroRow: View {
    @EnvironmentObject var activeTimer: ActiveTimerStore
    var pomodoro: Pomodoro
    var active: ActivePomodoroItem?
    var isExpanded: Bool
    var onToggleExpand: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    private let soundLabels = [
        "clasico": "Clásico", "campana": "Campana", "digital": "Digital", "suave": "Suave",
        "vibracion": "Solo vibración", "silent": "Silencioso", "peeeem": "Alarma insistente",
    ]

    /// La fase terminó y hay que avanzarla a mano (no hay auto-avance).
    private func awaitingAdvance(_ item: ActivePomodoroItem) -> Bool {
        item.secondsLeft <= 0 && !(item.autoStart && !item.pauseOnEnd)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(Color.red.opacity(active == nil ? 0.12 : 0.25))
                    Text("🍅").font(.system(size: 18))
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(pomodoro.name).font(.headline)
                    if let active {
                        Text("\(active.phaseLabel) · Ciclo \(active.cycleLabel)\(active.isPaused ? " · En pausa" : "")")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(active.isPaused ? .orange : .red)
                    }
                    Text(pomodoro.durationLabel ?? "\(pomodoro.work) / \(pomodoro.shortBreak) / \(pomodoro.longBreak) min")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let lastUsed = pomodoro.lastUsedLabel {
                        Text("Último uso: \(lastUsed)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 4)
                Text(active.map { timeString($0.secondsLeft) } ?? "--:--")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(active == nil ? .secondary : .primary)
            }

            HStack(spacing: 10) {
                if let active {
                    if awaitingAdvance(active) {
                        Button {
                            Task { await activeTimer.advancePhase(active) }
                        } label: {
                            Label(active.phase == "work" ? "¿Empezar descanso?" : "¿Volver al trabajo?", systemImage: "play.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else {
                        iconButton(active.isPaused ? "play.fill" : "pause.fill") {
                            Task { await activeTimer.togglePause(active) }
                        }
                        iconButton("stop.fill") { Task { await activeTimer.stop(active) } }
                        iconButton("arrow.clockwise") { Task { await activeTimer.restart(active) } }
                    }
                } else {
                    iconButton("play.fill", tint: .red) { Task { await activeTimer.start(pomodoro: pomodoro) } }
                    iconButton("pencil", tint: .blue, action: onEdit)
                    iconButton("trash", tint: .gray, action: onDelete)
                }
                Spacer()
                Button(action: onToggleExpand) {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Ocultar detalles" : "Ver detalles")
            }

            if isExpanded {
                VStack(spacing: 6) {
                    detail("Trabajo", "\(pomodoro.work) min")
                    detail("Descanso corto", "\(pomodoro.shortBreak) min")
                    detail("Descanso largo", "\(pomodoro.longBreak) min (cada \(pomodoro.cycles) ciclos)")
                    detail("Repeticiones", pomodoro.repetitions.map(String.init) ?? "∞ (en bucle)")
                    detail("Auto-iniciar", pomodoro.autoStart == 1 ? "Sí" : "No")
                    detail("Sonido", soundLabels[pomodoro.sound ?? ""] ?? "Predeterminado")
                }
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.vertical, 6)
        .contextMenu {
            if active == nil {
                Button(action: onEdit) { Label("Editar", systemImage: "pencil") }
                Button(role: .destructive, action: onDelete) { Label("Eliminar", systemImage: "trash") }
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.footnote)
    }

    private func iconButton(_ systemName: String, tint: Color = .gray, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint == .gray ? Color.primary : tint)
                .frame(width: 38, height: 38)
                .background((tint == .gray ? Color.gray : tint).opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
    }
}
