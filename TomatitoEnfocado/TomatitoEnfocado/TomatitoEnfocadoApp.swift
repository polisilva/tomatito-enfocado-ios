//
//  TomatitoEnfocadoApp.swift
//  TomatitoEnfocado
//
//  Created by Poliany on 03/09/26.
//

import SwiftUI

@main
struct TomatitoEnfocadoApp: App {
    init() {
        NotificationManager.shared.setup()
        WatchBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
