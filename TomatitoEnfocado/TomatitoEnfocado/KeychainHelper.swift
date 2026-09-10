//
//  KeychainHelper.swift
//  TomatitoEnfocado
//
//  Guarda usuário + senha de aplicativo (Application Password do WordPress)
//  com segurança no Keychain do iOS, em vez de UserDefaults.
//

import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.tomatito.credentials"

    static func save(username: String, appPassword: String, baseURL: String) {
        let account = "tomatito_credentials"
        let payload: [String: String] = [
            "username": username,
            "appPassword": appPassword,
            "baseURL": baseURL,
        ]
        guard let data = try? JSONEncoder().encode(payload) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load() -> (username: String, appPassword: String, baseURL: String)? {
        let account = "tomatito_credentials"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let payload = try? JSONDecoder().decode([String: String].self, from: data),
              let username = payload["username"],
              let appPassword = payload["appPassword"],
              let baseURL = payload["baseURL"]
        else {
            return nil
        }
        return (username, appPassword, baseURL)
    }

    static func clear() {
        let account = "tomatito_credentials"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
