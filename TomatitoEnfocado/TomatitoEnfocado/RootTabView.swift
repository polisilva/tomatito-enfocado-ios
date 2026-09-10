//
//  RootTabView.swift
//  TomatitoEnfocado
//
//  Navegación raíz por abas: Mi cuenta / Ahora mismo / Alarmas / Temporizadores
//  (especificación "13. Móvil").
//

import SwiftUI

struct RootTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MiCuentaView(selectedTab: $selectedTab)
                .tabItem { Label("Mi cuenta", systemImage: "person.crop.circle") }
                .tag(0)

            AhoraMismoView()
                .tabItem { Label("Ahora mismo", systemImage: "timer") }
                .tag(1)

            AlarmasView()
                .tabItem { Label("Alarmas", systemImage: "alarm") }
                .tag(2)

            TemporizadoresView()
                .tabItem { Label("Temporizadores", systemImage: "hourglass") }
                .tag(3)
        }
    }
}
