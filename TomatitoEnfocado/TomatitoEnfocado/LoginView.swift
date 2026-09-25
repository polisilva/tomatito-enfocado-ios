//
//  LoginView.swift
//  TomatitoEnfocado
//
//  Tela de login: entorno (producción/local) + usuario + Application Password.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: SessionStore

    // Precargados desde DevCredentials.swift (solo existe en este Mac,
    // nunca va a GitHub) para no escribir la contraseña cada vez que se
    // reinstala el app durante el desarrollo.
    @State private var baseURL: String = DevCredentials.baseURL
    @State private var username: String = DevCredentials.username
    @State private var appPassword: String = DevCredentials.appPassword
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
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(username.isEmpty || appPassword.isEmpty || isLoading)
                    .listRowInsets(EdgeInsets())
                }
                .listRowBackground(Color.clear)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        Text("🍅")
                        Text("Tomatito").fontWeight(.bold).foregroundStyle(.red)
                        Text("Enfocado").fontWeight(.bold).foregroundStyle(.primary)
                    }
                    .font(.title3)
                }
            }
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
