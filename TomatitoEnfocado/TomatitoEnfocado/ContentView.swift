//
//  ContentView.swift
//  TomatitoEnfocado
//
//  Login con Application Password do WordPress + navegação por abas
//  (Mi cuenta / Ahora mismo / Alarmas / Temporizadores), seguindo a
//  especificação "13. Móvil" do Omkrom.
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

/// Datos de la cabecera de "Mi cuenta": email real + estado de conexión con
/// Omkrom (especificación "13. Móvil" — GET /mi-cuenta).
struct CuentaInfo: Decodable {
    var email: String
    var displayName: String
    var omkromConnected: Bool
    var omkromStatusLabel: String
}

/// Estado real de un pomodoro en marcha, tal como lo ve el servidor
/// (GET /pomodoros/active). Se usa para "escuchar estado" y corregir
/// cualquier desvío del contador local — el servidor es la fuente de verdad.
struct ActivePomodoroStatus: Decodable {
    @FlexibleInt var timerId: Int
    @FlexibleInt var pomodoroId: Int
    var name: String
    @FlexibleInt var remaining: Int
    @FlexibleInt var duration: Int
    var state: String
    var phase: String
    var phaseLabel: String
    @FlexibleInt var cycle: Int
    @FlexibleInt var cyclesTotal: Int
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

// MARK: - Estado global: pomodoro ativo ("Ahora mismo")
//
// Regla de la especificación "13. Móvil": solo puede haber UN pomodoro
// activo a la vez, y "Ahora mismo" es la única pantalla que lo controla.
// Por eso este estado vive a nivel de app (no dentro de una sola pantalla)
// y se comparte vía @EnvironmentObject.

@MainActor
final class ActiveTimerStore: ObservableObject {
    @Published private(set) var pomodoroId: Int?
    @Published private(set) var pomodoroName: String = ""
    @Published private(set) var timerId: Int?
    @Published private(set) var phase: String = "work"
    @Published private(set) var totalSeconds: Int = 0
    @Published private(set) var secondsLeft: Int = 0
    @Published private(set) var isPaused = false
    @Published private(set) var cycle: Int = 0
    @Published private(set) var cyclesTotal: Int = 1
    @Published var isFinished = false
    @Published var isBusy = false
    @Published var errorMessage: String?

    // Duraciones del pomodoro en marcha (minutos), guardadas al iniciar para
    // poder anunciar la fase siguiente sin depender de una llamada extra.
    private var workMinutes: Int = 25
    private var shortBreakMinutes: Int = 5
    private var longBreakMinutes: Int = 15

    private var client: APIClient?
    private var ticker: Timer?
    private var resyncTimer: Timer?

    var hasActive: Bool { pomodoroId != nil }

    var phaseLabel: String {
        switch phase {
        case "work": return "Trabajo"
        case "short_break": return "Descanso corto"
        case "long_break": return "Descanso largo"
        default: return phase
        }
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(secondsLeft) / Double(totalSeconds)
    }

    /// Etiqueta "Ciclo actual" (ej. "2/4"), como en el mockup de "Ahora mismo".
    var cycleLabel: String {
        "\(min(cycle + 1, cyclesTotal))/\(cyclesTotal)"
    }

    /// Texto contextual "Siguiente: 5 min descanso corto" — calculado en el
    /// cliente a partir de la fase actual, sin llamar a la API.
    var nextPhaseText: String {
        switch phase {
        case "work":
            let isLastCycle = cycle + 1 >= cyclesTotal
            let minutes = isLastCycle ? longBreakMinutes : shortBreakMinutes
            let label = isLastCycle ? "descanso largo" : "descanso corto"
            return "Siguiente: \(minutes) min \(label)"
        case "short_break":
            return "Siguiente: \(workMinutes) min trabajo"
        case "long_break":
            return "Siguiente: nueva repetición (\(workMinutes) min trabajo)"
        default:
            return ""
        }
    }

    /// Chamado a partir do root quando o login muda — sem client não há
    /// como falar com a API, então qualquer estado antigo é limpo.
    func configure(client: APIClient?) {
        self.client = client
        if client == nil {
            reset()
        }
    }

    func reset() {
        ticker?.invalidate()
        ticker = nil
        resyncTimer?.invalidate()
        resyncTimer = nil
        pomodoroId = nil
        pomodoroName = ""
        timerId = nil
        phase = "work"
        totalSeconds = 0
        secondsLeft = 0
        isPaused = false
        cycle = 0
        cyclesTotal = 1
        isFinished = false
        errorMessage = nil
    }

    private func intFromAny(_ value: Any?) -> Int {
        if let n = value as? Int { return n }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) ?? 0 }
        return 0
    }

    private func startTicking() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                guard !self.isPaused, self.secondsLeft > 0 else { return }
                self.secondsLeft -= 1
            }
        }
        ensureResyncing()
    }

    /// "El servidor es la fuente de verdad": cada 15s se contrasta el estado
    /// local con GET /pomodoros/active para corregir cualquier desvío del
    /// contador (o detectar que el pomodoro fue pausado/cancelado desde la web).
    private func ensureResyncing() {
        guard resyncTimer == nil else { return }
        resyncTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in await self.resyncFromServer() }
        }
    }

    /// Contrasta (o adopta) el estado del pomodoro activo con el servidor.
    /// Se usa tanto en el timer periódico como al abrir "Ahora mismo", para
    /// detectar un pomodoro iniciado desde la web mientras el móvil no miraba.
    func resyncFromServer() async {
        guard let client, !isFinished else { return }
        do {
            let active: [ActivePomodoroStatus] = try await client.request("pomodoros/active")
            guard let match = pomodoroId != nil
                ? active.first(where: { $0.pomodoroId == pomodoroId })
                : active.first
            else {
                // El servidor ya no tiene nada en marcha: si el móvil creía
                // que sí, es que fue cancelado/completado desde otro lado.
                if pomodoroId != nil { reset() }
                return
            }

            if pomodoroId != match.pomodoroId {
                pomodoroId = match.pomodoroId
                pomodoroName = match.name
            }
            timerId = match.timerId
            phase = match.phase
            totalSeconds = match.duration
            secondsLeft = match.remaining
            isPaused = (match.state == "paused")
            cycle = match.cycle
            cyclesTotal = max(1, match.cyclesTotal)
            if ticker == nil { startTicking() }
        } catch {
            // Silencioso: esto es una corrección de fondo, no debe interrumpir la UI.
        }
    }

    /// Regla: iniciar un pomodoro nuevo cancela el que estuviera activo.
    func start(pomodoro: Pomodoro) async {
        guard let client else { return }
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        if let currentId = pomodoroId, currentId != pomodoro.id {
            try? await client.requestRaw("pomodoros/\(currentId)/stop", method: "POST")
        }

        do {
            struct StartResult: Decodable {
                @FlexibleInt var timerId: Int
                var phase: String
                @FlexibleInt var duration: Int
            }
            let result: StartResult = try await client.request(
                "pomodoros/\(pomodoro.id)/start", method: "POST"
            )
            pomodoroId = pomodoro.id
            pomodoroName = pomodoro.name
            timerId = result.timerId
            phase = result.phase
            totalSeconds = result.duration
            secondsLeft = result.duration
            isPaused = false
            isFinished = false
            cycle = 0
            cyclesTotal = max(1, pomodoro.cycles)
            workMinutes = pomodoro.work
            shortBreakMinutes = pomodoro.shortBreak
            longBreakMinutes = pomodoro.longBreak
            startTicking()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePause() async {
        guard let client, let pomodoroId else { return }
        errorMessage = nil
        do {
            if isPaused {
                let json = try await client.requestRaw("pomodoros/\(pomodoroId)/resume", method: "POST")
                secondsLeft = intFromAny(json["time_left"])
                isPaused = false
            } else {
                let json = try await client.requestRaw("pomodoros/\(pomodoroId)/pause", method: "POST")
                secondsLeft = intFromAny(json["time_left"])
                isPaused = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() async {
        guard let client, let pomodoroId else { return }
        errorMessage = nil
        do {
            try await client.requestRaw("pomodoros/\(pomodoroId)/stop", method: "POST")
            reset()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func advancePhase() async {
        guard let client, let pomodoroId else { return }
        errorMessage = nil
        do {
            struct AdvancePhaseResult: Decodable {
                var isFinal: Bool
                var phase: String?
                @FlexibleOptionalInt var duration: Int?
                @FlexibleOptionalInt var cycle: Int?
                @FlexibleOptionalInt var cyclesTotal: Int?
            }
            let result: AdvancePhaseResult = try await client.request(
                "pomodoros/\(pomodoroId)/advance-phase", method: "POST"
            )
            if result.isFinal {
                if let timerId {
                    try? await client.requestRaw("complete?timer_id=\(timerId)", method: "POST")
                }
                ticker?.invalidate()
                resyncTimer?.invalidate()
                resyncTimer = nil
                isFinished = true
            } else {
                phase = result.phase ?? phase
                totalSeconds = result.duration ?? totalSeconds
                secondsLeft = result.duration ?? 0
                isPaused = false
                cycle = result.cycle ?? cycle
                cyclesTotal = result.cyclesTotal.map { max(1, $0) } ?? cyclesTotal
                startTicking()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
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

// MARK: - Raíz con navegación por abas

struct RootTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MiCuentaView(selectedTab: $selectedTab)
                .tabItem { Label("Mi cuenta", systemImage: "person.crop.circle") }
                .tag(0)

            AhoraMismoView()
                .tabItem { Label("Ahora mismo", systemImage: "timer") }
                .tag(1)

            AlarmasView()
                .tabItem { Label("Alarmas", systemImage: "alarm") }
                .tag(2)

            TemporizadoresView()
                .tabItem { Label("Temporizadores", systemImage: "hourglass") }
                .tag(3)
        }
    }
}

// MARK: - Tela: Mi cuenta (gestión y creación — no controla nada en marcha)

struct MiCuentaView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var activeTimer: ActiveTimerStore
    @Binding var selectedTab: Int

    @State private var pomodoros: [Pomodoro] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCreate = false
    @State private var cuenta: CuentaInfo?
    @State private var nextAlarma: UpcomingAlarma?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cuenta?.displayName.isEmpty == false ? cuenta!.displayName : session.username)
                                .font(.headline)
                            Text(cuenta?.email ?? session.username)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(cuenta?.omkromConnected == true ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                Text(cuenta?.omkromConnected == true ? "Conectado a Omkrom" : (cuenta?.omkromStatusLabel ?? "Comprobando..."))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Salir") { session.logout() }
                            .font(.footnote)
                    }
                    .padding(.vertical, 4)
                }

                Section("Pomodoros guardados") {
                    if isLoading && pomodoros.isEmpty {
                        ProgressView()
                    } else if let errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(errorMessage).foregroundStyle(.red).font(.footnote)
                            Button("Reintentar") { Task { await load() } }
                        }
                    } else if pomodoros.isEmpty {
                        Text("Todavía no has creado ningún pomodoro.")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    } else {
                        ForEach(pomodoros) { pomodoro in
                            Button {
                                Task {
                                    await activeTimer.start(pomodoro: pomodoro)
                                    selectedTab = 1
                                }
                            } label: {
                                HStack {
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
                                    Spacer()
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.red)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                        }
                        .onDelete(perform: delete)
                    }
                }

                Section {
                    Button {
                        showingCreate = true
                    } label: {
                        Label("Nuevo pomodoro", systemImage: "plus")
                    }
                }

                Section("Alarmas") {
                    if let nextAlarma {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(nextAlarma.name).font(.subheadline)
                                Text("Próxima: \(nextAlarma.time)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { true },
                                set: { _ in Task { await toggleNextAlarma() } }
                            ))
                            .labelsHidden()
                        }
                    } else {
                        Text("No tienes alarmas activas. Gestiónalas en la pestaña Alarmas.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Mi cuenta")
            .refreshable { await load() }
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
        cuenta = try? await session.client.request("mi-cuenta")
        let alarmas: [UpcomingAlarma]? = try? await session.client.request("alarmas/upcoming")
        nextAlarma = alarmas?.first
    }

    private func toggleNextAlarma() async {
        guard let nextAlarma else { return }
        try? await session.client.requestRaw("alarmas/\(nextAlarma.id)/toggle", method: "POST")
        let alarmas: [UpcomingAlarma]? = try? await session.client.request("alarmas/upcoming")
        self.nextAlarma = alarmas?.first
    }

    private func delete(at offsets: IndexSet) {
        let idsToDelete = offsets.map { pomodoros[$0].id }
        pomodoros.remove(atOffsets: offsets)
        Task {
            for id in idsToDelete {
                try? await session.client.requestRaw("pomodoros/\(id)", method: "DELETE")
            }
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
    @State private var repetitionsText: String = ""
    @State private var showingAdvanced = false
    @State private var autoStart = false
    @State private var pauseOnEnd = true
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
                }

                Section {
                    Stepper("Cada \(cycles) ciclos → descanso largo", value: $cycles, in: 1...12)
                    Stepper("Descanso largo: \(longBreak) min", value: $longBreak, in: 1...60)
                }

                DisclosureGroup("Opciones avanzadas", isExpanded: $showingAdvanced) {
                    HStack {
                        Text("Repetir secuencia")
                        Spacer()
                        TextField("∞", text: $repetitionsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                    Text("Vacío = en bucle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Auto-iniciar siguiente fase", isOn: $autoStart)
                    Toggle("Pausar al finalizar sesión", isOn: $pauseOnEnd)
                }

                Section {
                    Text("Ejemplo: \(work) min trabajo → \(shortBreak) min descanso corto → cada \(cycles) ciclos, \(longBreak) min descanso largo\(repetitionsText.trimmingCharacters(in: .whitespaces).isEmpty ? " (en bucle)" : "")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
            var body: [String: Any] = [
                "name": name,
                "work": work,
                "short_break": shortBreak,
                "long_break": longBreak,
                "cycles": cycles,
                "auto_start": autoStart ? 1 : 0,
                "pause_on_end": pauseOnEnd ? 1 : 0,
            ]
            // Vacío = en bucle: se omite "repetitions" para que el servidor
            // lo guarde como null, en vez de forzar un número de vueltas.
            if let repetitions = Int(repetitionsText.trimmingCharacters(in: .whitespaces)), repetitions > 0 {
                body["repetitions"] = repetitions
            }
            let _: Pomodoro = try await session.client.request(
                "pomodoros",
                method: "POST",
                body: body
            )
            onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Tela: Ahora mismo (control en vivo — la pantalla más importante)

struct CircularTimerRing: View {
    var progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.15), lineWidth: 16)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(Color.red, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.9), value: progress)
        }
    }
}

struct UpcomingAlarma: Decodable, Identifiable {
    @FlexibleInt var id: Int
    var name: String
    var time: String
    var sound: String?
}

struct AhoraMismoView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var activeTimer: ActiveTimerStore
    @EnvironmentObject var activeTemporizadores: ActiveTemporizadoresStore

    @State private var upcomingAlarmas: [UpcomingAlarma] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    if activeTimer.isFinished {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.green)
                            Text("¡Pomodoro completo!")
                                .font(.title2.bold())
                            Button("Cerrar") { activeTimer.reset() }
                                .buttonStyle(.bordered)
                        }
                        .padding(.top, 40)
                    } else if activeTimer.hasActive {
                        VStack(spacing: 16) {
                            Text(activeTimer.pomodoroName)
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            ZStack {
                                CircularTimerRing(progress: activeTimer.progress)
                                    .frame(width: 220, height: 220)
                                VStack(spacing: 6) {
                                    Text(activeTimer.phaseLabel)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(timeString(activeTimer.secondsLeft))
                                        .font(.system(size: 44, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                    Text("Ciclo \(activeTimer.cycleLabel)")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.top, 12)

                            if !activeTimer.nextPhaseText.isEmpty {
                                Text(activeTimer.nextPhaseText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            if activeTimer.secondsLeft <= 0 {
                                Button("Avanzar fase") {
                                    Task { await activeTimer.advancePhase() }
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                HStack(spacing: 16) {
                                    Button(activeTimer.isPaused ? "Reanudar" : "Pausar") {
                                        Task { await activeTimer.togglePause() }
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Cancelar") {
                                        Task { await activeTimer.stop() }
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                }
                            }

                            if let errorMessage = activeTimer.errorMessage {
                                Text(errorMessage)
                                    .foregroundStyle(.red)
                                    .font(.footnote)
                            }
                        }
                        .padding()
                    } else {
                        ContentUnavailableView(
                            "Nada en marcha",
                            systemImage: "timer",
                            description: Text("Inicia un pomodoro desde Mi cuenta para verlo aquí.")
                        )
                        .padding(.top, 40)
                    }

                    Divider().padding(.horizontal)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Temporizadores activos").font(.headline)
                        if activeTemporizadores.items.isEmpty {
                            Text("Ninguno en marcha.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(activeTemporizadores.items) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).font(.subheadline.weight(.medium))
                                        HStack(spacing: 6) {
                                            Text(timeString(item.secondsLeft))
                                                .monospacedDigit()
                                            Text(item.isPaused ? "· Pausado" : "· En marcha")
                                                .foregroundStyle(item.isPaused ? .orange : .green)
                                        }
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        Task { await activeTemporizadores.togglePause(item) }
                                    } label: {
                                        Image(systemName: item.isPaused ? "play.fill" : "pause.fill")
                                    }
                                    .buttonStyle(.bordered)
                                    Button {
                                        Task { await activeTemporizadores.stop(item) }
                                    } label: {
                                        Image(systemName: "stop.fill")
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Próximas alarmas").font(.headline)
                        if upcomingAlarmas.isEmpty {
                            Text("Ninguna programada.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(upcomingAlarmas) { alarma in
                                HStack {
                                    Text(alarma.name).font(.subheadline)
                                    Spacer()
                                    Text(alarma.time)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                    Text("Activada")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Ahora mismo")
            .task { await loadUpcomingAlarmas() }
            .task { await resyncLoop() }
            .refreshable {
                await loadUpcomingAlarmas()
                await activeTimer.resyncFromServer()
                await activeTemporizadores.resyncFromServer()
            }
        }
    }

    private func loadUpcomingAlarmas() async {
        do {
            upcomingAlarmas = try await session.client.request("alarmas/upcoming")
        } catch {
            // Silencioso: esta sección es solo un preview, no bloquea la pantalla.
        }
    }

    /// "El móvil escucha estado, el servidor es la fuente de verdad": mientras
    /// esta pantalla está visible, se contrasta el estado local con el
    /// servidor cada 15s (y también al abrir la pantalla).
    private func resyncLoop() async {
        while !Task.isCancelled {
            await activeTimer.resyncFromServer()
            await activeTemporizadores.resyncFromServer()
            try? await Task.sleep(nanoseconds: 15_000_000_000)
        }
    }

    private func timeString(_ seconds: Int) -> String {
        let total = max(0, seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - Tela: Alarmas (todavía no conectada a la API)

struct Alarma: Decodable, Identifiable {
    @FlexibleInt var id: Int
    var name: String
    var time: String // "HH:MM:SS"
    @FlexibleInt var isActive: Int
    var repeatMode: String
    var startDate: String?
    var endDate: String?
    var sound: String?
    @FlexibleInt var mon: Int
    @FlexibleInt var tue: Int
    @FlexibleInt var wed: Int
    @FlexibleInt var thu: Int
    @FlexibleInt var fri: Int
    @FlexibleInt var sat: Int
    @FlexibleInt var sun: Int
    var timeLabel: String?
    var repeatLabel: String?

    var isOn: Bool { isActive != 0 }
}

struct AlarmasView: View {
    @EnvironmentObject var session: SessionStore

    @State private var alarmas: [Alarma] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCreate = false
    @State private var editingAlarma: Alarma?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && alarmas.isEmpty {
                    ProgressView("Cargando...")
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage).foregroundStyle(.red)
                        Button("Reintentar") { Task { await load() } }
                    }
                } else if alarmas.isEmpty {
                    ContentUnavailableView(
                        "Sin alarmas",
                        systemImage: "alarm",
                        description: Text("Todavía no has creado ninguna alarma.")
                    )
                } else {
                    List {
                        ForEach(alarmas) { alarma in
                            Button {
                                editingAlarma = alarma
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(alarma.name).font(.headline)
                                        Text(alarma.timeLabel ?? alarma.time)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Text(alarma.repeatLabel ?? alarma.repeatMode)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { alarma.isOn },
                                        set: { _ in Task { await toggle(alarma) } }
                                    ))
                                    .labelsHidden()
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                        }
                        .onDelete(perform: delete)
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Alarmas")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreate) {
                AlarmaFormView(existing: nil, onSaved: { Task { await load() } })
                    .environmentObject(session)
            }
            .sheet(item: $editingAlarma) { alarma in
                AlarmaFormView(existing: alarma, onSaved: { Task { await load() } })
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
            alarmas = try await session.client.request("alarmas")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggle(_ alarma: Alarma) async {
        do {
            try await session.client.requestRaw("alarmas/\(alarma.id)/toggle", method: "POST")
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        let idsToDelete = offsets.map { alarmas[$0].id }
        alarmas.remove(atOffsets: offsets)
        Task {
            for id in idsToDelete {
                try? await session.client.requestRaw("alarmas/\(id)", method: "DELETE")
            }
        }
    }
}

// MARK: - Tela: Crear/Editar Alarma

struct AlarmaFormView: View {
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    var existing: Alarma?
    var onSaved: () -> Void

    @State private var name: String = ""
    @State private var time: Date = Date()
    @State private var repeatMode: String = "none"
    @State private var days: Set<String> = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let repeatOptions: [(key: String, label: String)] = [
        ("none", "Sin repetición"),
        ("daily", "Diariamente"),
        ("weekdays", "Lunes a Viernes"),
        ("custom", "Personalizado"),
    ]

    private let dayOptions: [(key: String, label: String)] = [
        ("mon", "L"), ("tue", "M"), ("wed", "X"), ("thu", "J"),
        ("fri", "V"), ("sat", "S"), ("sun", "D"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("Ej: Despertador", text: $name)
                }

                Section("Hora") {
                    DatePicker("Hora", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }

                Section("Repetición") {
                    Picker("Repetición", selection: $repeatMode) {
                        ForEach(repeatOptions, id: \.key) { option in
                            Text(option.label).tag(option.key)
                        }
                    }
                    .pickerStyle(.segmented)

                    if repeatMode == "custom" {
                        HStack {
                            ForEach(dayOptions, id: \.key) { day in
                                Button {
                                    if days.contains(day.key) {
                                        days.remove(day.key)
                                    } else {
                                        days.insert(day.key)
                                    }
                                } label: {
                                    Text(day.label)
                                        .frame(width: 32, height: 32)
                                        .background(days.contains(day.key) ? Color.red : Color.gray.opacity(0.15))
                                        .foregroundStyle(days.contains(day.key) ? .white : .primary)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .navigationTitle(existing == nil ? "Nueva alarma" : "Editar alarma")
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
        .onAppear { populateFromExisting() }
    }

    private func populateFromExisting() {
        guard let existing else { return }
        name = existing.name
        repeatMode = existing.repeatMode
        days = Set(dayOptions.map(\.key).filter { key in
            switch key {
            case "mon": return existing.mon != 0
            case "tue": return existing.tue != 0
            case "wed": return existing.wed != 0
            case "thu": return existing.thu != 0
            case "fri": return existing.fri != 0
            case "sat": return existing.sat != 0
            case "sun": return existing.sun != 0
            default: return false
            }
        })
        let parts = existing.time.split(separator: ":")
        if parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour = hour
            components.minute = minute
            time = Calendar.current.date(from: components) ?? Date()
        }
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let timeString = String(format: "%02d:%02d:00", components.hour ?? 0, components.minute ?? 0)

        var body: [String: Any] = [
            "name": name,
            "time": timeString,
            "repeat_mode": repeatMode,
            "is_active": existing?.isActive ?? 1,
        ]
        for day in dayOptions {
            body[day.key] = days.contains(day.key) ? 1 : 0
        }

        do {
            if let existing {
                let _: Alarma = try await session.client.request(
                    "alarmas/\(existing.id)", method: "PUT", body: body
                )
            } else {
                let _: Alarma = try await session.client.request(
                    "alarmas", method: "POST", body: body
                )
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Tela: Temporizadores (todavía no conectada a la API)

struct Temporizador: Decodable, Identifiable {
    @FlexibleInt var id: Int
    var name: String
    @FlexibleInt var duration: Int
    var sound: String?
    var durationLabel: String?
    var lastUsedLabel: String?
}

/// Una instancia en marcha de un temporizador. A diferencia de los pomodoros,
/// varios pueden coexistir — por eso este estado es una lista, no un único
/// pomodoro activo.
struct ActiveTemporizadorItem: Identifiable {
    let timerId: Int
    let name: String
    var secondsLeft: Int
    var isPaused: Bool
    var id: Int { timerId }
}

@MainActor
final class ActiveTemporizadoresStore: ObservableObject {
    @Published var items: [ActiveTemporizadorItem] = []
    @Published var errorMessage: String?

    private var client: APIClient?
    private var ticker: Timer?

    func configure(client: APIClient?) {
        self.client = client
        if client == nil {
            ticker?.invalidate()
            ticker = nil
            items = []
        }
    }

    private func intFromAny(_ value: Any?) -> Int {
        if let n = value as? Int { return n }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) ?? 0 }
        return 0
    }

    private func ensureTicking() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                for index in self.items.indices {
                    if !self.items[index].isPaused && self.items[index].secondsLeft > 0 {
                        self.items[index].secondsLeft -= 1
                    }
                }
            }
        }
    }

    func start(temporizador: Temporizador) async {
        guard let client else { return }
        errorMessage = nil
        do {
            let json = try await client.requestRaw("temporizadores/\(temporizador.id)/start", method: "POST")
            let timerId = intFromAny(json["timer_id"])
            let duration = intFromAny(json["duration"])
            items.append(ActiveTemporizadorItem(timerId: timerId, name: temporizador.name, secondsLeft: duration, isPaused: false))
            ensureTicking()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePause(_ item: ActiveTemporizadorItem) async {
        guard let client, let index = items.firstIndex(where: { $0.timerId == item.timerId }) else { return }
        errorMessage = nil
        do {
            if items[index].isPaused {
                let json = try await client.requestRaw("temporizadores/\(item.timerId)/resume", method: "POST")
                items[index].secondsLeft = intFromAny(json["time_left"])
                items[index].isPaused = false
            } else {
                let json = try await client.requestRaw("temporizadores/\(item.timerId)/pause", method: "POST")
                items[index].secondsLeft = intFromAny(json["time_left"])
                items[index].isPaused = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop(_ item: ActiveTemporizadorItem) async {
        guard let client else { return }
        errorMessage = nil
        do {
            try await client.requestRaw("temporizadores/\(item.timerId)/stop", method: "POST")
            items.removeAll { $0.timerId == item.timerId }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// "El servidor es la fuente de verdad": reemplaza la lista local por lo
    /// que devuelve GET /temporizadores/dashboard, para corregir desvíos del
    /// contador y detectar temporizadores lanzados desde la web.
    func resyncFromServer() async {
        guard let client else { return }
        struct DashboardEntry: Decodable {
            @FlexibleOptionalInt var timerId: Int?
            var name: String
            @FlexibleInt var remaining: Int
            var state: String
        }
        struct DashboardResponse: Decodable {
            var mode: String
            var data: [DashboardEntry]
        }
        do {
            let json = try await client.requestRaw("temporizadores/dashboard", method: "GET")
            let data = try JSONSerialization.data(withJSONObject: json)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(DashboardResponse.self, from: data)

            guard response.mode == "running" else {
                items = []
                return
            }
            items = response.data.compactMap { entry in
                guard let timerId = entry.timerId else { return nil }
                return ActiveTemporizadorItem(
                    timerId: timerId,
                    name: entry.name,
                    secondsLeft: entry.remaining,
                    isPaused: entry.state == "paused"
                )
            }
            ensureTicking()
        } catch {
            // Silencioso: corrección de fondo, no debe interrumpir la UI.
        }
    }
}

struct TemporizadoresView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var activeTemporizadores: ActiveTemporizadoresStore

    @State private var temporizadores: [Temporizador] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCreate = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && temporizadores.isEmpty {
                    ProgressView("Cargando...")
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage).foregroundStyle(.red)
                        Button("Reintentar") { Task { await load() } }
                    }
                } else if temporizadores.isEmpty {
                    ContentUnavailableView(
                        "Sin temporizadores",
                        systemImage: "hourglass",
                        description: Text("Todavía no has creado ningún temporizador.")
                    )
                } else {
                    List {
                        ForEach(temporizadores) { temporizador in
                            Button {
                                Task { await activeTemporizadores.start(temporizador: temporizador) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(temporizador.name).font(.headline)
                                        Text(temporizador.durationLabel ?? "\(temporizador.duration) s")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        if let lastUsed = temporizador.lastUsedLabel {
                                            Text("Último uso: \(lastUsed)")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.red)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                        }
                        .onDelete(perform: delete)
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Temporizadores")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreate) {
                CreateTemporizadorView(onCreated: { Task { await load() } })
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
            temporizadores = try await session.client.request("temporizadores")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        let idsToDelete = offsets.map { temporizadores[$0].id }
        temporizadores.remove(atOffsets: offsets)
        Task {
            for id in idsToDelete {
                try? await session.client.requestRaw("temporizadores/\(id)", method: "DELETE")
            }
        }
    }
}

// MARK: - Tela: Crear Temporizador

struct CreateTemporizadorView: View {
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    var onCreated: () -> Void

    @State private var name: String = ""
    @State private var minutes: Int = 10
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("Ej: Ejercicio, Descanso...", text: $name)
                }
                Section("Duración") {
                    Stepper("\(minutes) min", value: $minutes, in: 1...180)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("Nuevo temporizador")
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
            let _: Temporizador = try await session.client.request(
                "temporizadores",
                method: "POST",
                body: ["name": name, "duration": minutes * 60]
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
    @StateObject private var activeTimer = ActiveTimerStore()
    @StateObject private var activeTemporizadores = ActiveTemporizadoresStore()

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
        .onAppear {
            configureStores(loggedIn: session.isLoggedIn)
        }
        .onChange(of: session.isLoggedIn) { _, isLoggedIn in
            configureStores(loggedIn: isLoggedIn)
        }
    }

    private func configureStores(loggedIn: Bool) {
        let client = loggedIn ? session.client : nil
        activeTimer.configure(client: client)
        activeTemporizadores.configure(client: client)
    }
}

#Preview {
    ContentView()
}
