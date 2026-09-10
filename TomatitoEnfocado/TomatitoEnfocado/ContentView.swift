//
//  ContentView.swift
//  TomatitoEnfocado
//
//  Raíz del app: decide entre LoginView y RootTabView, y crea los tres
//  estados compartidos (@StateObject) que el resto de las pantallas leen
//  vía @EnvironmentObject.
//
//  El resto del código vive en archivos separados por responsabilidad:
//    KeychainHelper.swift, APIClient.swift, Models.swift — infraestructura
//    SessionStore.swift, ActiveTimerStore.swift, ActiveTemporizadoresStore.swift — estado
//    LoginView.swift, RootTabView.swift — navegación
//    MiCuentaView.swift, CreatePomodoroView.swift — pantalla "Mi cuenta"
//    AhoraMismoView.swift — pantalla "Ahora mismo"
//    AlarmasView.swift, AlarmaFormView.swift — pantalla "Alarmas"
//    TemporizadoresView.swift, CreateTemporizadorView.swift — pantalla "Temporizadores"
//

import SwiftUI

struct ContentView: View {
    @StateObject private var session = SessionStore()
    @StateObject private var activeTimer = ActiveTimerStore()
    @StateObject private var activeTemporizadores = ActiveTemporizadoresStore()

    var body: some View {
        Group {
            if session.isLoggedIn {
                RootTabView()
            } else {
                LoginView()
            }
        }
        .environmentObject(session)
        .environmentObject(activeTimer)
        .environmentObject(activeTemporizadores)
        .onAppear {
            configureStores(loggedIn: session.isLoggedIn)
        }
        .onChange(of: session.isLoggedIn) { _, isLoggedIn in
            configureStores(loggedIn: isLoggedIn)
        }
    }

    private func configureStores(loggedIn: Bool) {
        let client = loggedIn ? session.client : nil
        activeTimer.configure(client: client)
        activeTemporizadores.configure(client: client)
    }
}

#Preview {
    ContentView()
}
