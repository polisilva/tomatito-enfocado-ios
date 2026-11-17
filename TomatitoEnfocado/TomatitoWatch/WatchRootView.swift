//
//  WatchRootView.swift
//  TomatitoWatch
//
//  Cuatro páginas verticales: Ahora / Hoy / Iniciar / Alarma, con el estilo de
//  Fitness: fondo negro, anillos y cifras grandes de colores.
//

import SwiftUI

private func clock(_ seconds: Int) -> String {
    String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
}

/// Color de cada fase: trabajo en rojo, descansos en verde y cian.
private func phaseColor(_ phase: String) -> Color {
    switch phase {
    case "short_break": return .fitGreen
    case "long_break": return .fitCyan
    default: return .fitRed
    }
}

struct WatchRootView: View {
    @EnvironmentObject var store: WatchStore
    @State private var page: Int = {
        #if DEBUG
        // Solo desarrollo: `-page N` abre en esa página (para capturas).
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-page"), i + 1 < args.count, let n = Int(args[i + 1]) { return n }
        #endif
        return 0
    }()

    var body: some View {
        if store.isLoggedIn {
            TabView(selection: $page) {
                NowView(page: $page).tag(0)
                TodayView().tag(1)
                StartView(page: $page).tag(2)
                AlarmView().tag(3)
            }
            .tabViewStyle(.verticalPage)
            .fontDesign(.rounded)
            .tint(Color.fitRed)
        } else {
            VStack(spacing: 8) {
                Text("🍅").font(.largeTitle)
                Text("Abre Tomatito en tu iPhone e inicia sesión.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .fontDesign(.rounded)
        }
    }
}

private struct NowView: View {
    @EnvironmentObject var store: WatchStore
    @Binding var page: Int

    var body: some View {
        if store.active.isEmpty {
            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(Color.fitRed.opacity(0.25), lineWidth: 10)
                    Image(systemName: "timer")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.fitRed)
                }
                .frame(width: 72, height: 72)
                Text("Nada en marcha").font(.headline)
                Button("Iniciar uno") { page = 2 }
                    .tint(Color.fitRed)
            }
        } else {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(store.active) { item in
                        let color = phaseColor(item.phase)
                        VStack(spacing: 6) {
                            ZStack {
                                ActivityRings(rings: [.init(progress: item.progress, color: color)], lineWidth: 12)
                                VStack(spacing: 0) {
                                    Text(clock(item.remaining))
                                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                    Text(item.isPaused ? "En pausa" : item.phaseLabel)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(color)
                                }
                            }
                            .frame(width: 140, height: 140)
                            Text(item.name).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            HStack(spacing: 14) {
                                RoundControl(systemName: item.isPaused ? "play.fill" : "pause.fill", color: .yellow) {
                                    Task { await store.togglePause(item) }
                                }
                                RoundControl(systemName: "stop.fill", color: .fitRed) {
                                    Task { await store.stop(item) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Resumen del día, como la pantalla de anillos de Actividad.
private struct TodayView: View {
    @EnvironmentObject var store: WatchStore

    private var goalPomodoros: Int { max(1, store.goalMinutes / 25) }

    var body: some View {
        HStack(spacing: 10) {
            ActivityRings(rings: [
                .init(progress: Double(store.todayMinutes) / Double(max(1, store.goalMinutes)), color: .fitRed),
                .init(progress: Double(store.todayCompleted) / Double(goalPomodoros), color: .fitGreen),
            ], lineWidth: 11)
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 8) {
                stat("FOCO", "\(store.todayMinutes)/\(store.goalMinutes)", "MIN", .fitRed)
                stat("POMODOROS", "\(store.todayCompleted)/\(goalPomodoros)", "", .fitGreen)
            }
        }
        .padding(.horizontal, 6)
    }

    private func stat(_ title: String, _ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
                }
            }
        }
    }
}

private struct StartView: View {
    @EnvironmentObject var store: WatchStore
    @Binding var page: Int

    var body: some View {
        List {
            if store.pomodoros.isEmpty {
                Text(store.isLoading ? "Cargando…" : "Sin pomodoros guardados.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(store.pomodoros) { pomodoro in
                Button {
                    page = 0
                    Task { await store.start(pomodoro) }
                } label: {
                    HStack(spacing: 10) {
                        Text("🍅")
                            .frame(width: 34, height: 34)
                            .background(Color.fitRed.opacity(0.25), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(pomodoro.name).font(.headline).lineLimit(1)
                            Text("\(pomodoro.work) / \(pomodoro.shortBreak) / \(pomodoro.longBreak) min")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listRowBackground(Color.white.opacity(0.12).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
            }
        }
        .navigationTitle("Iniciar")
    }
}

private struct AlarmView: View {
    @EnvironmentObject var store: WatchStore

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.fitRed.opacity(0.25), lineWidth: 8)
                Image(systemName: "alarm.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.fitRed)
            }
            .frame(width: 56, height: 56)
            if let alarma = store.nextAlarma {
                Text(alarma.name).font(.headline).lineLimit(1)
                Text(alarma.time)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.fitRed)
                    .monospacedDigit()
            } else {
                Text("Sin alarmas próximas")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = store.errorMessage {
                Text(error).font(.caption2).foregroundStyle(Color.fitRed)
            }
        }
    }
}
