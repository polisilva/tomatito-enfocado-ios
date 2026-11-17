//
//  WatchTheme.swift
//  TomatitoWatch
//
//  Estilo de la app Fitness/Actividad de Apple Watch: fondo negro, anillos
//  concéntricos, colores vivos y números grandes en tipografía redondeada.
//

import SwiftUI

extension Color {
    /// Rojo-rosa vivo del anillo "Mover"; color de marca.
    static let fitRed = Color(red: 0.98, green: 0.07, blue: 0.31)
    /// Verde lima del anillo "Ejercicio".
    static let fitGreen = Color(red: 0.57, green: 0.91, blue: 0.16)
    /// Cian del anillo "Pararse".
    static let fitCyan = Color(red: 0.12, green: 0.92, blue: 0.94)
}

/// Anillos concéntricos como los de Actividad; progreso 0…1.
struct ActivityRings: View {
    struct Ring { var progress: Double; var color: Color }
    var rings: [Ring]
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.offset) { index, ring in
                let inset = CGFloat(index) * (lineWidth + 2)
                Circle()
                    .stroke(ring.color.opacity(0.25), lineWidth: lineWidth)
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

/// Botón redondo de color, como los controles de un entrenamiento.
struct RoundControl: View {
    var systemName: String
    var color: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 52, height: 52)
                .background(color.opacity(0.25), in: Circle())
        }
        .buttonStyle(.plain)
    }
}
