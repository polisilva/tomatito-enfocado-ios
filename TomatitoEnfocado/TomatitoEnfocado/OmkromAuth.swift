//
//  OmkromAuth.swift
//  TomatitoEnfocado
//
//  Inicio de sesión con Omkrom, igual que la web: se abre la página de acceso
//  del sitio (/acceder) en una hoja del sistema y, ya con la sesión iniciada,
//  se usa el flujo estándar de WordPress para autorizar aplicaciones
//  (wp-admin/authorize-application.php). Al aprobar, WordPress devuelve al app
//  un usuario + una contraseña de aplicación por el esquema tomatitoenfocado://,
//  así la persona nunca escribe ni ve esa clave.
//

import AuthenticationServices
import UIKit

enum OmkromAuthError: LocalizedError {
    case cancelled
    case missingCredentials
    case rejected

    var errorDescription: String? {
        switch self {
        case .cancelled: return nil
        case .missingCredentials: return "El sitio no devolvió las credenciales. Inténtalo de nuevo."
        case .rejected: return "Se canceló la autorización."
        }
    }
}

@MainActor
final class OmkromAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static let scheme = "tomatitoenfocado"
    private static let appID = "6f1c0d52-8f43-4b0a-9e0e-5a7c2b3d9e11"
    private var session: ASWebAuthenticationSession?

    /// Devuelve (usuario, contraseña de aplicación) tras iniciar sesión y aprobar.
    func authorize(baseURL: String) async throws -> (username: String, password: String) {
        let authorizeURL = "\(baseURL)/wp-admin/authorize-application.php"
            + "?app_name=\(Self.encode("Tomatito Enfocado"))"
            + "&app_id=\(Self.appID)"
            + "&success_url=\(Self.encode("\(Self.scheme)://auth"))"
            + "&reject_url=\(Self.encode("\(Self.scheme)://auth?success=false"))"
        // El portal Omkrom recibe la dirección de vuelta ya codificada entera.
        let startURL = "\(baseURL)/acceder/?redirect_to=\(Self.encode(authorizeURL))"
        guard let url = URL(string: startURL) else { throw OmkromAuthError.missingCredentials }

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.scheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
                    continuation.resume(throwing: OmkromAuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? OmkromAuthError.missingCredentials)
                }
            }
            session.presentationContextProvider = self
            self.session = session
            session.start()
        }

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if items.first(where: { $0.name == "success" })?.value == "false" { throw OmkromAuthError.rejected }
        guard let user = items.first(where: { $0.name == "user_login" })?.value,
              let password = items.first(where: { $0.name == "password" })?.value,
              !user.isEmpty, !password.isEmpty else { throw OmkromAuthError.missingCredentials }
        return (user, password)
    }

    private static func encode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}
