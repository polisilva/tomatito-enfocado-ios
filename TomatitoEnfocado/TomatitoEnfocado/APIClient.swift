//
//  APIClient.swift
//  TomatitoEnfocado
//
//  Cliente HTTP para /wp-json/tomatito/v1/... con Basic Auth (Application
//  Password de WordPress).
//

import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case httpStatus(Int)
    case decoding
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL inválida."
        case .httpStatus(let code): return "El servidor respondió con error \(code)."
        case .decoding: return "No se pudo interpretar la respuesta del servidor."
        case .server(let message): return message
        }
    }
}

struct APIClient {
    var baseURL: String   // ex.: "https://focus.omkrom.com"
    var username: String
    var appPassword: String

    private var authHeaderValue: String {
        let raw = "\(username):\(appPassword)"
        let data = raw.data(using: .utf8) ?? Data()
        return "Basic \(data.base64EncodedString())"
    }

    private func buildRequest(_ path: String, method: String, body: [String: Any]?) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL) else { throw APIError.invalidURL }
        // Alguns endpoints (ex.: "complete?timer_id=42") levam query string no path.
        let parts = path.split(separator: "?", maxSplits: 1)
        components.path = "/wp-json/tomatito/v1/" + parts[0]
        if parts.count > 1 {
            components.query = String(parts[1])
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(authHeaderValue, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    private func send(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.httpStatus(-1) }
        // A API do Tomatito devolve 200 mesmo em erros de negócio (success:false),
        // e usa Basic Auth para autenticar — um 401 aqui normalmente é usuário/senha errados.
        guard (200..<300).contains(http.statusCode) else { throw APIError.httpStatus(http.statusCode) }
        return data
    }

    /// Faz uma chamada a /wp-json/tomatito/v1/{path} e devolve o campo "data" já decodificado.
    func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        let data = try await send(try buildRequest(path, method: method, body: body))

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let envelope = try decoder.decode(APIEnvelope<T>.self, from: data)
        guard envelope.success else {
            throw APIError.server(envelope.message ?? "No autorizado")
        }
        guard let payload = envelope.data else {
            throw APIError.decoding
        }
        return payload
    }

    /// Para endpoints cuja resposta vem "solta" junto a "success" (sem "data"):
    /// pause/resume/stop/complete/delete. Devolve o JSON cru.
    @discardableResult
    func requestRaw(_ path: String, method: String = "POST", body: [String: Any]? = nil) async throws -> [String: Any] {
        let data = try await send(try buildRequest(path, method: method, body: body))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decoding
        }
        guard (json["success"] as? Bool) == true else {
            throw APIError.server((json["message"] as? String) ?? "No autorizado")
        }
        return json
    }
}

/// Formato padrão de toda resposta da API: { success, data, message }
struct APIEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let message: String?
}
