//
//  RootTabView.swift
//  TomatitoEnfocado
//
//  Navegación raíz por abas: Mi cuenta / Ahora mismo / Alarmas / Temporizadores
//  (especificación "13. Móvil").
//

import SwiftUI
import UIKit

/// Renderiza el emoji 🍅 real a una imagen de alta resolución para usarlo
/// como ícono de tabItem manteniendo su color — igual que en el mockup,
/// donde el tomate se ve igual (colorido) en todos lados, incluida la barra
/// de abas. Clave: el modo de render se fija en el UIImage con
/// withRenderingMode(.alwaysOriginal) — fijarlo con el modifier .renderingMode
/// de SwiftUI en el Image no sobrevive la conversión a UITabBarItem y el
/// ícono termina gris cuando la pestaña no está seleccionada.
private func tomatoTabIcon(pointSize: CGFloat = 27) -> Image {
    // El tamaño del renderer va en POINTS — UIGraphicsImageRenderer ya usa la
    // escala de pantalla (Retina) automáticamente para la nitidez, y así el
    // UIImage resultante declara su tamaño correctamente (27x27pt), no
    // gigante como pasaba al pre-multiplicar por la escala a mano.
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: pointSize, height: pointSize))
    let uiImage = renderer.image { _ in
        let font = UIFont.systemFont(ofSize: pointSize * 0.9)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let text = "🍅" as NSString
        let textSize = text.size(withAttributes: attributes)
        let origin = CGPoint(x: (pointSize - textSize.width) / 2, y: (pointSize - textSize.height) / 2)
        text.draw(at: origin, withAttributes: attributes)
    }
    return Image(uiImage: uiImage.withRenderingMode(.alwaysOriginal))
}

struct RootTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MiCuentaView(selectedTab: $selectedTab)
                .tabItem {
                    Label {
                        Text("Mi cuenta")
                    } icon: {
                        tomatoTabIcon()
                    }
                }
                .tag(0)

            AhoraMismoView()
                .tabItem { Label("Ahora mismo", systemImage: "timer") }
                .tag(1)

            AlarmasView()
                .tabItem { Label("Alarmas", systemImage: "alarm") }
                .tag(2)

            TemporizadoresView(selectedTab: $selectedTab)
                .tabItem { Label("Temporizadores", systemImage: "hourglass") }
                .tag(3)
        }
    }
}
