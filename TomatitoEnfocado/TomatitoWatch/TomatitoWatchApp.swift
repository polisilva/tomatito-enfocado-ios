//
//  TomatitoWatchApp.swift
//  TomatitoWatch
//
//  App del Apple Watch. Versión 1: depende del iPhone solo para recibir la
//  sesión (WatchConnectivity); después habla con la API del sitio por su cuenta.
//

import SwiftUI

@main
struct TomatitoWatchApp: App {
    @StateObject private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(store)
        }
    }
}
