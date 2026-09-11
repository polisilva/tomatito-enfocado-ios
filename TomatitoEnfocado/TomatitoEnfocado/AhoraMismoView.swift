//
//  AhoraMismoView.swift
//  TomatitoEnfocado
//
//  Tela "Ahora mismo": control en vivo — la pantalla más importante.
//  Muestra el pomodoro activo, los temporizadores activos y las próximas
//  alarmas, y se resincroniza con el servidor cada 15s.
//

import SwiftUI

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
                    if activeTimer.isFinished {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.green)
                            Text("¡Pomodoro completo!")
                                .font(.title2.bold())
                            Button("Cerrar") { activeTimer.reset() }
                                .buttonStyle(.bordered)
                        }
                        .padding(.top, 40)
                    } else if activeTimer.hasActive {
                        VStack(spacing: 16) {
                            Text(activeTimer.pomodoroName)
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            ZStack {
                                CircularTimerRing(progress: activeTimer.progress)
                                    .frame(width: 220, height: 220)
                                VStack(spacing: 6) {
                                    Text(activeTimer.phaseLabel)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(timeString(activeTimer.secondsLeft))
                                        .font(.system(size: 44, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                    Text("Ciclo \(activeTimer.cycleLabel)")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.top, 12)

                            if !activeTimer.nextPhaseText.isEmpty {
                                Text(activeTimer.nextPhaseText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            if activeTimer.secondsLeft <= 0 {
                                Button("Avanzar fase") {
                                    Task { await activeTimer.advancePhase() }
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                HStack(spacing: 16) {
                                    Button(activeTimer.isPaused ? "Reanudar" : "Pausar") {
                                        Task { await activeTimer.togglePause() }
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Cancelar") {
                                        Task { await activeTimer.stop() }
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                }
                            }

                            if let errorMessage = activeTimer.errorMessage {
                                Text(errorMessage)
                                    .foregroundStyle(.red)
                                    .font(.footnote)
                            }
                        }
                        .padding()
                    } else {
                        ContentUnavailableView(
                            "Nada en marcha",
                            systemImage: "timer",
                            description: Text("Inicia un pomodoro desde Mi cuenta para verlo aquí.")
                        )
                        .padding(.top, 40)
                    }

                    Divider().padding(.horizontal)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Temporizadores activos").font(.headline)
                        if activeTemporizadores.items.isEmpty {
                            Text("Ninguno en marcha.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(activeTemporizadores.items) { item in
                                HStack {
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
                                    .tint(.red)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Próximas alarmas").font(.headline)
                        if upcomingAlarmas.isEmpty {
                            Text("Ninguna programada.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(upcomingAlarmas) { alarma in
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
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }
                .padding(.bottom, 48)
            }
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

    private func timeString(_ seconds: Int) -> String {
        let total = max(0, seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
