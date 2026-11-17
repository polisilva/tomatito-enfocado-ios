//
//  FitnessTheme.swift
//  TomatitoEnfocado
//
//  Lenguaje visual inspirado en la app Fitness de Apple: fondo negro en modo
//  oscuro, tarjetas grandes y redondeadas, colores vivos y anillos de progreso.
//

import SwiftUI
import UIKit

extension Color {
    /// Rojo-rosa vivo del anillo "Mover" de Fitness; es el color de marca del app.
    static let fitRed = Color(red: 0.98, green: 0.07, blue: 0.31)
    /// Verde lima del anillo "Ejercicio".
    static let fitGreen = Color(red: 0.57, green: 0.91, blue: 0.16)
    /// Cian del anillo "Pararse".
    static let fitCyan = Color(red: 0.12, green: 0.92, blue: 0.94)

    /// Fondo de pantalla: negro en oscuro, gris agrupado en claro.
    static let fitBackground = Color(UIColor { $0.userInterfaceStyle == .dark ? .black : .systemGroupedBackground })
    /// Tarjetas: gris casi negro en oscuro, blanco en claro.
    static let fitCard = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.11, alpha: 1) : .white })

    static let fitGradientTop = Color(red: 1.0, green: 0.30, blue: 0.45)
}

extension LinearGradient {
    /// Degradado de las tarjetas rojas (pomodoro activo / en espera).
    static let fitRed = LinearGradient(
        colors: [.fitGradientTop, .fitRed],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// Radio estándar de las tarjetas.
let fitCornerRadius: CGFloat = 20

extension View {
    /// Tarjeta Fitness: fondo de tarjeta, esquinas grandes y continuas.
    func fitCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(Color.fitCard)
            .clipShape(RoundedRectangle(cornerRadius: fitCornerRadius, style: .continuous))
    }
}

/// Anillos concéntricos como los de Actividad: cada uno con su color y progreso (0…1+).
struct ActivityRings: View {
    struct Ring { var progress: Double; var color: Color }
    var rings: [Ring]
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.offset) { index, ring in
                let inset = CGFloat(index) * (lineWidth + 3)
                Circle()
                    .stroke(ring.color.opacity(0.22), lineWidth: lineWidth)
                    .padding(inset)
                Circle()
                    .trim(from: 0, to: min(max(ring.progress, 0.001), 1))
                    .stroke(ring.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(inset)
            }
        }
    }
}

/// Tarjeta "Hoy" del Inicio: anillos de foco del día + cifras, como el resumen de Fitness.
struct ActivitySummaryCard: View {
    var minutes: Int
    var completed: Int
    var goalMinutes: Int

    private var goalPomodoros: Int { max(1, goalMinutes / 25) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Hoy").font(.title2.bold())
                Spacer()
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(Locale(identifier: "es_ES"))))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 22) {
                ActivityRings(rings: [
                    .init(progress: Double(minutes) / Double(max(1, goalMinutes)), color: .fitRed),
                    .init(progress: Double(completed) / Double(goalPomodoros), color: .fitGreen),
                ], lineWidth: 16)
                .frame(width: 118, height: 118)

                VStack(alignment: .leading, spacing: 12) {
                    stat("Foco", value: "\(minutes)/\(goalMinutes) min", color: .fitRed)
                    stat("Pomodoros", value: "\(completed)/\(goalPomodoros)", color: .fitGreen)
                }
                Spacer(minLength: 0)
            }
        }
        .fitCard(padding: 18)
    }

    private func stat(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
    }
}
