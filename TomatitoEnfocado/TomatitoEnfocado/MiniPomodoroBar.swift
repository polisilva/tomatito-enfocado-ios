//
//  MiniPomodoroBar.swift
//  TomatitoEnfocado
//
//  Barra roja fija sobre la barra de pestañas mientras hay un pomodoro activo,
//  como el mini reproductor de Música: recuerda al usuario que tiene uno en
//  marcha en cualquier pestaña. Al tocarla se abre el mismo cartón grande de
//  siempre (ActivePomodoroCard + lista de activos), sin perder ninguna acción.
//

import SwiftUI

struct MiniPomodoroBar: View {
    @EnvironmentObject var activeTimer: ActiveTimerStore
    var onTap: () -> Void

    var body: some View {
        if let item = activeTimer.featured {
            content(item)
        }
    }

    private func subtitle(_ item: ActivePomodoroItem) -> String {
        var text = "\(item.phaseLabel) · Ciclo \(item.cycleLabel)"
        if item.isPaused { text += " · Pausado" }
        return text
    }

    private func content(_ item: ActivePomodoroItem) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: item.isFinished ? "checkmark.circle.fill" : "timer")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.isFinished ? "¡\(item.name) completo!" : item.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(item.isFinished ? "Toca para cerrar" : subtitle(item))
                        .font(.caption)
                        .opacity(0.85)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if activeTimer.items.count > 1 {
                    Text("+\(activeTimer.items.count - 1)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.white, in: Capsule())
                        .foregroundStyle(Color(red: 0.95, green: 0.28, blue: 0.32))
                }
                if !item.isFinished {
                    Text(timeString(item.secondsLeft))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Abre el pomodoro")

            if !item.isFinished {
                actionButton(item)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.41, blue: 0.41), Color(red: 0.95, green: 0.28, blue: 0.32)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .bottom) {
            if !item.isFinished {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.white.opacity(0.3))
                        Rectangle().fill(.white).frame(width: geo.size.width * item.progress)
                    }
                }
                .frame(height: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }

    @ViewBuilder
    private func actionButton(_ item: ActivePomodoroItem) -> some View {
        if item.secondsLeft <= 0 {
            // Con auto_start y sin pausa al final la fase avanza sola (igual que la web).
            if !(item.autoStart && !item.pauseOnEnd) {
                roundButton("forward.fill", label: "Avanzar fase") {
                    Task { await activeTimer.advancePhase(item) }
                }
            }
        } else {
            roundButton(item.isPaused ? "play.fill" : "pause.fill", label: item.isPaused ? "Reanudar" : "Pausar") {
                Task { await activeTimer.togglePause(item) }
            }
        }
    }

    private func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.25), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Pantalla que abre la barra: el mismo cartón rojo y la lista de activos
/// que ya existían en Inicio.
struct PomodoroDetailSheet: View {
    @EnvironmentObject var activeTimer: ActiveTimerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let featured = activeTimer.featured {
                        ActivePomodoroCard(item: featured)
                    }
                    if activeTimer.items.count > 1 {
                        PomodoroSwitcherList()
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pomodoro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .onChange(of: activeTimer.items.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
    }
}

/// Coloca la barra sobre la barra de pestañas (el contenido de la pestaña
/// recibe el espacio extra automáticamente, así no tapa el final de la lista).
struct MiniPomodoroBarInset: ViewModifier {
    @EnvironmentObject var activeTimer: ActiveTimerStore
    var hidden: Bool
    var onTap: () -> Void

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if !hidden && activeTimer.hasActive {
                MiniPomodoroBar(onTap: onTap)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
    }
}

extension View {
    func miniPomodoroBar(hidden: Bool = false, onTap: @escaping () -> Void) -> some View {
        modifier(MiniPomodoroBarInset(hidden: hidden, onTap: onTap))
    }
}
