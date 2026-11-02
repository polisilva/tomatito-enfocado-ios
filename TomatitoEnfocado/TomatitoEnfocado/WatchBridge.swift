//
//  WatchBridge.swift
//  TomatitoEnfocado
//
//  Envía la sesión (servidor + usuario + clave de aplicación) al Apple Watch
//  con WatchConnectivity, para que el reloj no pida iniciar sesión otra vez.
//

import Foundation
import WatchConnectivity

final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private var pending: [String: Any]?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Manda la sesión actual; con valores vacíos el reloj cierra sesión.
    func send(baseURL: String, username: String, appPassword: String) {
        let context: [String: Any] = ["baseURL": baseURL, "username": username, "appPassword": appPassword]
        pending = context
        push()
    }

    private func push() {
        guard WCSession.isSupported(), let context = pending else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired else { return }
        do {
            try session.updateApplicationContext(context)
        } catch {
            NSLog("WatchBridge: no se pudo enviar la sesión al reloj: \(error.localizedDescription)")
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        push()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        push()
    }
}
