//
//  WatchRootView.swift
//  TomatitoWatch
//
//  Tres páginas verticales: Ahora / Iniciar / Alarma.
//

import SwiftUI

private func clock(_ seconds: Int) -> String {
    String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
}

struct WatchRootView: View {
    @EnvironmentObject var store: WatchStore
    @State private var page = 0

    var body: some View {
        if store.isLoggedIn {
            TabView(selection: $page) {
                NowView(page: $page).tag(0)
                StartView(page: $page).tag(1)
                AlarmView().tag(2)
            }
            .tabViewStyle(.verticalPage)
        } else {
            VStack(spacing: 8) {
                Text("🍅").font(.largeTitle)
                Text("Abre Tomatito en tu iPhone e inicia sesión.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

private struct NowView: View {
    @EnvironmentObject var store: WatchStore
    @Binding var page: Int

    var body: some View {
        if store.active.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "timer").font(.title2).foregroundStyle(.secondary)
                Text("Nada en marcha").font(.headline)
                Button("Iniciar uno") { page = 1 }
                    .tint(.red)
            }
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(store.active) { item in
                        VStack(spacing: 6) {
                            ZStack {
                                Circle().stroke(Color.red.opacity(0.25), lineWidth: 8)
                                Circle()
                                    .trim(from: 0, to: item.progress)
                                    .stroke(Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                VStack(spacing: 0) {
                                    Text(clock(item.remaining))
                                        .font(.system(size: 30, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                    Text(item.isPaused ? "En pausa" : item.phaseLabel)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 130, height: 130)
                            Text(item.name).font(.footnote).lineLimit(1)
                            HStack {
                                Button {
                                    Task { await store.togglePause(item) }
                                } label: {
                                    Image(systemName: item.isPaused ? "play.fill" : "pause.fill")
                                }
                                Button(role: .destructive) {
                                    Task { await store.stop(item) }
                                } label: {
                                    Image(systemName: "stop.fill")
                                }
                            }
                        }
                    }
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pomodoro.name).font(.headline)
                        Text("\(pomodoro.work) / \(pomodoro.shortBreak) / \(pomodoro.longBreak) min")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Iniciar")
    }
}

private struct AlarmView: View {
    @EnvironmentObject var store: WatchStore

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "alarm").font(.title2).foregroundStyle(.red)
            if let alarma = store.nextAlarma {
                Text(alarma.name).font(.headline).lineLimit(1)
                Text(alarma.time).font(.title3).monospacedDigit()
            } else {
                Text("Sin alarmas próximas")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = store.errorMessage {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
        }
    }
}
