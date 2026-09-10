//
//  SessionStore.swift
//  TomatitoEnfocado
//
//  Estado de login (guardado no Keychain) compartilhado por todo o app
//  via @EnvironmentObject.
//

import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var baseURL: String = "https://focus.omkrom.com"
    @Published var username: String = ""
    @Published var appPassword: String = ""

    init() {
        if let saved = KeychainHelper.load() {
            baseURL = saved.baseURL
            username = saved.username
            appPassword = saved.appPassword
            isLoggedIn = true
        }
    }

    var client: APIClient {
        APIClient(baseURL: baseURL, username: username, appPassword: appPassword)
    }

    /// Testa as credenciais com uma chamada real (GET /ajustes) antes de considerar "logado".
    func login(baseURL: String, username: String, appPassword: String) async throws {
        let testClient = APIClient(baseURL: baseURL, username: username, appPassword: appPassword)
        struct Ajustes: Decodable {}
        let _: Ajustes = try await testClient.request("ajustes")

        self.baseURL = baseURL
        self.username = username
        self.appPassword = appPassword
        KeychainHelper.save(username: username, appPassword: appPassword, baseURL: baseURL)
        self.isLoggedIn = true
    }

    func logout() {
        KeychainHelper.clear()
        username = ""
        appPassword = ""
        isLoggedIn = false
    }
}
