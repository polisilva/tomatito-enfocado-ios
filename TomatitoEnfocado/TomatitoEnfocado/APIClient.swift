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

    // MARK: - Endpoints nativos de WordPress (fuera de /wp-json/tomatito/v1/)
    //
    // Usados para gestionar Application Passwords: WordPress ya expone su
    // propio endpoint para eso (habilitado para este plugin en
    // 30-habilitar-application-passwords.php), así que no hace falta
    // duplicar esa lógica en el plugin — solo llamarla con las mismas
    // credenciales Basic Auth que ya usa el resto del app.

    private func buildAbsoluteRequest(_ absolutePath: String, method: String, body: [String: Any]?) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL) else { throw APIError.invalidURL }
        components.path = absolutePath
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

    /// Llama a un endpoint nativo de WordPress (respuesta "pelada", sin el
    /// envelope {success,data} propio de /wp-json/tomatito/v1/).
    func requestWordPress<T: Decodable>(_ absolutePath: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        let data = try await send(try buildAbsoluteRequest(absolutePath, method: method, body: body))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    func deleteWordPress(_ absolutePath: String) async throws {
        _ = try await send(try buildAbsoluteRequest(absolutePath, method: "DELETE", body: nil))
    }

    /// Sube la foto de perfil como multipart/form-data — el único endpoint
    /// que no habla JSON, así que arma su propia petición en vez de usar
    /// buildRequest().
    func uploadAvatar(imageData: Data, filename: String, mimeType: String) async throws -> String {
        guard var components = URLComponents(string: baseURL) else { throw APIError.invalidURL }
        components.path = "/wp-json/tomatito/v1/mi-perfil/avatar"
        guard let url = components.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(authHeaderValue, forHTTPHeaderField: "Authorization")
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"avatar\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let data = try await send(req)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        struct AvatarPayload: Decodable { var avatarURL: String }
        let envelope = try decoder.decode(APIEnvelope<AvatarPayload>.self, from: data)
        guard envelope.success, let payload = envelope.data else {
            throw APIError.server(envelope.message ?? "No se pudo subir la foto")
        }
        return payload.avatarURL
    }
}

/// Formato padrão de toda resposta da API: { success, data, message }
struct APIEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let message: String?
}
