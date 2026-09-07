//
//  ContentView.swift
//  TomatitoEnfocado
//
//  Primeira versão: login com Application Password do WordPress +
//  lista de pomodoros vindos da API real (tomatito/v1).
//
//  NOTA DE ORGANIZAÇÃO: por enquanto todo o código está neste único
//  arquivo (Keychain, API client, modelos, telas) para evitar ter que
//  editar o project.pbxproj na mão — arriscado de corromper o projeto.
//  Quando quiser separar em vários arquivos, usa o Xcode: seleciona o
//  bloco de código → botão direito → "Refactor" → "Extract to New File"
//  (ele mesmo registra o arquivo novo no projeto, sem risco).
//

import SwiftUI
import Security

// MARK: - Keychain (guarda usuário + senha de aplicativo com segurança)

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

// MARK: - API Client

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

    /// Faz uma chamada a /wp-json/tomatito/v1/{path} e devolve o campo "data" já decodificado.
    func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        guard var components = URLComponents(string: baseURL) else { throw APIError.invalidURL }
        components.path = "/wp-json/tomatito/v1/" + path
        guard let url = components.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(authHeaderValue, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse else { throw APIError.httpStatus(-1) }
        // A API do Tomatito devolve 200 mesmo em erros de negócio (success:false),
        // e usa Basic Auth para autenticar — um 401 aqui normalmente é usuário/senha errados.
        guard (200..<300).contains(http.statusCode) else { throw APIError.httpStatus(http.statusCode) }

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
}

/// Formato padrão de toda resposta da API: { success, data, message }
struct APIEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let message: String?
}

// MARK: - Modelos

/// Decodifica um Int mesmo que o JSON venha como string ("25") — o wpdb
/// às vezes devolve números como texto, então isto evita crashes de decode.
@propertyWrapper
struct FlexibleInt: Decodable {
    var wrappedValue: Int

    init(wrappedValue: Int) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            wrappedValue = intVal
        } else if let strVal = try? container.decode(String.self), let parsed = Int(strVal) {
            wrappedValue = parsed
        } else {
            wrappedValue = 0
        }
    }
}

@propertyWrapper
struct FlexibleOptionalInt: Decodable {
    var wrappedValue: Int?

    init(wrappedValue: Int?) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            wrappedValue = nil
        } else if let intVal = try? container.decode(Int.self) {
            wrappedValue = intVal
        } else if let strVal = try? container.decode(String.self) {
            wrappedValue = Int(strVal)
        } else {
            wrappedValue = nil
        }
    }
}

struct Pomodoro: Decodable, Identifiable {
    @FlexibleInt var id: Int
    var name: String
    @FlexibleInt var work: Int
    @FlexibleInt var shortBreak: Int
    @FlexibleInt var longBreak: Int
    @FlexibleInt var cycles: Int
    @FlexibleOptionalInt var repetitions: Int?
    var sound: String?
    var durationLabel: String?
    var lastUsedLabel: String?
}

// MARK: - Sessão (estado de login, guardado no Keychain)

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

// MARK: - Tela de Login

struct LoginView: View {
    @EnvironmentObject var session: SessionStore

    @State private var baseURL: String = "https://focus.omkrom.com"
    @State private var username: String = ""
    @State private var appPassword: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Servidor") {
                    Picker("Entorno", selection: $baseURL) {
                        Text("Producción").tag("https://focus.omkrom.com")
                        Text("Local").tag("http://tomatito-local.local")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Credenciales") {
                    TextField("Usuario de WordPress", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Application Password", text: $appPassword)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                Section {
                    Button {
                        Task { await doLogin() }
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Entrar")
                        }
                    }
                    .disabled(username.isEmpty || appPassword.isEmpty || isLoading)
                }
            }
            .navigationTitle("🍅 Tomatito Enfocado")
        }
    }

    private func doLogin() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await session.login(baseURL: baseURL, username: username, appPassword: appPassword)
        } catch {
            errorMessage = "No se pudo iniciar sesión: \(error.localizedDescription)"
        }
    }
}

// MARK: - Tela: Lista de Pomodoros

struct PomodorosListView: View {
    @EnvironmentObject var session: SessionStore

    @State private var pomodoros: [Pomodoro] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCreate = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && pomodoros.isEmpty {
                    ProgressView("Cargando...")
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage).foregroundStyle(.red)
                        Button("Reintentar") { Task { await load() } }
                    }
                } else if pomodoros.isEmpty {
                    ContentUnavailableView(
                        "Sin pomodoros",
                        systemImage: "timer",
                        description: Text("Todavía no has creado ningún pomodoro.")
                    )
                } else {
                    List(pomodoros) { pomodoro in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pomodoro.name).font(.headline)
                            Text("\(pomodoro.work) / \(pomodoro.shortBreak) / \(pomodoro.longBreak) min")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let lastUsed = pomodoro.lastUsedLabel {
                                Text("Último uso: \(lastUsed)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Pomodoros")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Salir") { session.logout() }
                }
            }
            .sheet(isPresented: $showingCreate) {
                CreatePomodoroView(onCreated: { Task { await load() } })
                    .environmentObject(session)
            }
        }
        .task { await load() }
    }

    private func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            pomodoros = try await session.client.request("pomodoros")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Tela: Crear Pomodoro

struct CreatePomodoroView: View {
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    var onCreated: () -> Void

    @State private var name: String = ""
    @State private var work: Int = 25
    @State private var shortBreak: Int = 5
    @State private var longBreak: Int = 15
    @State private var cycles: Int = 4
    @State private var repetitions: Int = 1
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("Ej: Estudio, Trabajo...", text: $name)
                }

                Section("Duración (minutos)") {
                    Stepper("Trabajo: \(work) min", value: $work, in: 1...120)
                    Stepper("Descanso corto: \(shortBreak) min", value: $shortBreak, in: 1...60)
                    Stepper("Descanso largo: \(longBreak) min", value: $longBreak, in: 1...60)
                }

                Section("Ciclos y repeticiones") {
                    Stepper("Ciclos antes del descanso largo: \(cycles)", value: $cycles, in: 1...12)
                    Stepper("Repeticiones: \(repetitions)", value: $repetitions, in: 1...20)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .navigationTitle("Nuevo pomodoro")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Guardar")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            let _: Pomodoro = try await session.client.request(
                "pomodoros",
                method: "POST",
                body: [
                    "name": name,
                    "work": work,
                    "short_break": shortBreak,
                    "long_break": longBreak,
                    "cycles": cycles,
                    "repetitions": repetitions,
                ]
            )
            onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Root

struct ContentView: View {
    @StateObject private var session = SessionStore()

    var body: some View {
        Group {
            if session.isLoggedIn {
                PomodorosListView()
            } else {
                LoginView()
            }
        }
        .environmentObject(session)
    }
}

#Preview {
    ContentView()
}
