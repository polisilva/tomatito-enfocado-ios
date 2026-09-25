//
//  AhoraMismoView.swift
//  TomatitoEnfocado
//
//  Tela "Ahora mismo": control en vivo — la pantalla más importante.
//  Muestra el pomodoro activo, los temporizadores activos y las próximas
//  alarmas, y se resincroniza con el servidor cada 15s.
//

import SwiftUI

func timeString(_ seconds: Int) -> String {
    let total = max(0, seconds)
    return String(format: "%02d:%02d", total / 60, total % 60)
}

struct CircularTimerRing: View {
    var progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.15), lineWidth: 16)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(Color.red, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.9), value: progress)
        }
    }
}

struct AhoraMismoView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var activeTimer: ActiveTimerStore
    @EnvironmentObject var activeTemporizadores: ActiveTemporizadoresStore

    @State private var upcomingAlarmas: [UpcomingAlarma] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    if activeTimer.items.isEmpty {
                        ContentUnavailableView(
                            "Nada en marcha",
                            systemImage: "timer",
                            description: Text("Inicia un pomodoro desde Mi cuenta para verlo aquí.")
                        )
                        .padding(.top, 40)
                    } else {
                        VStack(spacing: 16) {
                            // Un solo anel grande — el pomodoro "principal" (⭐), igual
                            // que en la web: persiste en el servidor y se puede elegir
                            // desde la lista de abajo. Los demás siguen corriendo detrás.
                            if let featured = activeTimer.featured {
                                ActivePomodoroCard(item: featured)
                            }

                            if activeTimer.items.count > 1 {
                                PomodoroSwitcherList()
                            }
                        }
                        .padding(.horizontal)

                        if let errorMessage = activeTimer.errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Temporizadores activos").font(.headline)
                        VStack(spacing: 0) {
                            if activeTemporizadores.items.isEmpty {
                                Text("Ninguno en marcha.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                            } else {
                                ForEach(Array(activeTemporizadores.items.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 { Divider().padding(.leading) }
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle().fill(Color.red.opacity(0.12))
                                            Image(systemName: "hourglass")
                                                .font(.system(size: 14))
                                                .foregroundStyle(.red)
                                        }
                                        .frame(width: 32, height: 32)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name).font(.subheadline.weight(.medium))
                                            HStack(spacing: 6) {
                                                Text(timeString(item.secondsLeft))
                                                    .monospacedDigit()
                                                Text(item.isPaused ? "· Pausado" : "· En marcha")
                                                    .foregroundStyle(item.isPaused ? .orange : .green)
                                            }
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button {
                                            Task { await activeTemporizadores.togglePause(item) }
                                        } label: {
                                            Image(systemName: item.isPaused ? "play.fill" : "pause.fill")
                                        }
                                        .buttonStyle(.bordered)
                                        Button {
                                            Task { await activeTemporizadores.stop(item) }
                                        } label: {
                                            Image(systemName: "stop.fill")
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(.gray)
                                    }
                                    .padding()
                                }
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Próximas alarmas").font(.headline)
                        VStack(spacing: 0) {
                            if upcomingAlarmas.isEmpty {
                                Text("Ninguna programada.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                            } else {
                                ForEach(Array(upcomingAlarmas.enumerated()), id: \.element.id) { index, alarma in
                                    if index > 0 { Divider().padding(.leading) }
                                    HStack {
                                        Text(alarma.name).font(.subheadline)
                                        Spacer()
                                        Text(alarma.time)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                        Text("Activada")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    }
                                    .padding()
                                }
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }
                .padding(.top, 8)
                .padding(.bottom, 48)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ahora mismo")
            .task { await loadUpcomingAlarmas() }
            .task { await resyncLoop() }
            .refreshable {
                await loadUpcomingAlarmas()
                await activeTimer.resyncFromServer()
                await activeTemporizadores.resyncFromServer()
            }
        }
    }

    private func loadUpcomingAlarmas() async {
        do {
            upcomingAlarmas = try await session.client.request("alarmas/upcoming")
        } catch {
            // Silencioso: esta sección es solo un preview, no bloquea la pantalla.
        }
    }

    /// "El móvil escucha estado, el servidor es la fuente de verdad": mientras
    /// esta pantalla está visible, se contrasta el estado local con el
    /// servidor cada 15s (y también al abrir la pantalla).
    private func resyncLoop() async {
        while !Task.isCancelled {
            await activeTimer.resyncFromServer()
            await activeTemporizadores.resyncFromServer()
            try? await Task.sleep(nanoseconds: 15_000_000_000)
        }
    }

}

/// Lista compacta de todos los pomodoros activos, con una estrella para
/// elegir cuál se destaca arriba en el anel grande — igual que la lista
/// "Pomodoros activos" + el switcher ⭐ de la web.
struct PomodoroSwitcherList: View {
    @EnvironmentObject var activeTimer: ActiveTimerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pomodoros activos").font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(activeTimer.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading) }
                    HStack(spacing: 12) {
                        Button {
                            Task { await activeTimer.setPrincipal(pomodoroId: item.pomodoroId) }
                        } label: {
                            Image(systemName: item.pomodoroId == activeTimer.principalPomodoroId ? "star.fill" : "star")
                                .foregroundStyle(item.pomodoroId == activeTimer.principalPomodoroId ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.subheadline.weight(.medium))
                            HStack(spacing: 6) {
                                Text(item.phaseLabel)
                                Text("·")
                                Text(timeString(item.secondsLeft)).monospacedDigit()
                                if item.isPaused {
                                    Text("· Pausado").foregroundStyle(.orange)
                                }
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { await activeTimer.togglePause(item) }
                        } label: {
                            Image(systemName: item.isPaused ? "play.fill" : "pause.fill")
                        }
                        .buttonStyle(.bordered)
                        Button {
                            Task { await activeTimer.stop(item) }
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.gray)
                        Button {
                            Task { await activeTimer.restart(item) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .tint(.gray)
                    }
                    .padding()
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Una tarjeta por pomodoro activo. Varias pueden aparecer a la vez en
/// "Ahora mismo" — cada una controla solo su propio timer_id.
struct ActivePomodoroCard: View {
    @EnvironmentObject var activeTimer: ActiveTimerStore
    var item: ActivePomodoroItem

    var body: some View {
        VStack(spacing: 14) {
            if item.isFinished {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                    Text("¡\(item.name) completo!")
                        .font(.headline)
                    Button("Cerrar") { activeTimer.dismissFinished(item) }
                        .buttonStyle(.bordered)
                }
                .padding(.vertical, 8)
            } else {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ZStack {
                    CircularTimerRing(progress: item.progress)
                        .frame(width: 140, height: 140)
                    VStack(spacing: 4) {
                        Text(item.phaseLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(timeString(item.secondsLeft))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("Ciclo \(item.cycleLabel)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if !item.nextPhaseText.isEmpty {
                    Text(item.nextPhaseText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if item.secondsLeft <= 0 {
                    Button("Avanzar fase") {
                        Task { await activeTimer.advancePhase(item) }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    HStack(spacing: 16) {
                        Button(item.isPaused ? "Reanudar" : "Pausar") {
                            Task { await activeTimer.togglePause(item) }
                        }
                        .buttonStyle(.bordered)

                        Button("Cancelar") {
                            Task { await activeTimer.stop(item) }
                        }
                        .buttonStyle(.bordered)
                        .tint(.gray)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
