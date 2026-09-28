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
    @StateObject private var alarmScheduler = AlarmScheduler()

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
        .environmentObject(alarmScheduler)
        .onAppear {
            configureStores(loggedIn: session.isLoggedIn)
        }
        .onChange(of: session.isLoggedIn) { _, isLoggedIn in
            configureStores(loggedIn: isLoggedIn)
        }
        // Vigía de alarmas global: debe poder avisar sin importar qué aba esté abierta.
        .alert(item: $alarmScheduler.firing) { firing in
            Alert(
                title: Text("⏰ \(firing.name)"),
                message: Text(firing.time),
                dismissButton: .default(Text("Detener alarma")) {
                    alarmScheduler.stopFiring()
                }
            )
        }
    }

    private func configureStores(loggedIn: Bool) {
        let client = loggedIn ? session.client : nil
        activeTimer.configure(client: client)
        activeTemporizadores.configure(client: client)
        alarmScheduler.configure(client: client)
    }
}

#Preview {
    ContentView()
}
