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
    @State private var showingHelp = false

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

                Section {
                    TextField("Usuario de WordPress", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.vertical, 8)
                    SecureField("Contraseña de aplicación", text: $appPassword)
                        .padding(.vertical, 8)
                    Button {
                        showingHelp = true
                    } label: {
                        Label("¿Qué es una contraseña de aplicación?", systemImage: "questionmark.circle")
                            .font(.footnote)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Credenciales")
                } footer: {
                    Text("No es tu contraseña normal: es una clave especial que genera tu cuenta solo para este app.")
                        .padding(.top, 4)
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
            .sheet(isPresented: $showingHelp) { AppPasswordHelpView() }
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

/// Explica qué es una contraseña de aplicación y cómo conseguir una.
private struct AppPasswordHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Contraseña de aplicación")
                        .font(.title2.bold())
                    Text("Es una clave que tu cuenta de Tomatito Enfocado crea especialmente para este app. Así el app puede entrar sin que tengas que darle tu contraseña normal, y puedes anularla cuando quieras sin cambiar la principal.")

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Cómo conseguirla").font(.headline)
                        step(1, "Entra en la web de Tomatito Enfocado con tu cuenta.")
                        step(2, "Abre tu perfil y busca «Contraseñas de aplicación».")
                        step(3, "Escribe un nombre (por ejemplo «Mi iPhone») y pulsa «Crear».")
                        step(4, "Copia la clave que aparece y pégala aquí. Solo se muestra una vez.")
                    }
                }
                .padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.red))
            Text(text)
        }
    }
}
