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

    private let omkromAuth = OmkromAuth()
    @State private var showingManual = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                        HStack(spacing: 6) {
                            Text("Tomatito").foregroundStyle(.red)
                            Text("Enfocado").foregroundStyle(.primary)
                        }
                        .font(.system(size: 30, weight: .bold))
                        Text("Inicia sesión con tu cuenta Omkrom, la misma de la web.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)

                    Button {
                        Task { await doOmkromLogin() }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Entrar con Omkrom").font(.headline)
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                    .disabled(isLoading)

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }

                    DisclosureGroup(isExpanded: $showingManual) {
                        VStack(alignment: .leading, spacing: 16) {
                            Picker("Entorno", selection: $baseURL) {
                                Text("Producción").tag("https://focus.omkrom.com")
                                Text("Local").tag("http://tomatito-local.local")
                            }
                            .pickerStyle(.segmented)

                            TextField("Usuario de WordPress", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(14)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            SecureField("Contraseña de aplicación", text: $appPassword)
                                .padding(14)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            Button {
                                showingHelp = true
                            } label: {
                                Label("¿Qué es una contraseña de aplicación?", systemImage: "questionmark.circle")
                                    .font(.footnote)
                            }

                            Button {
                                Task { await doLogin() }
                            } label: {
                                Text("Entrar con contraseña de aplicación")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(username.isEmpty || appPassword.isEmpty || isLoading)
                        }
                        .padding(.top, 14)
                    } label: {
                        Text("Otras opciones de acceso").font(.subheadline)
                    }
                    .tint(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .sheet(isPresented: $showingHelp) { AppPasswordHelpView() }
        }
    }

    /// Login con Omkrom, igual que la web.
    private func doOmkromLogin() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            // El acceso Omkrom (OAuth) solo está configurado en producción.
            let site = "https://focus.omkrom.com"
            let creds = try await omkromAuth.authorize(baseURL: site)
            try await session.login(baseURL: site, username: creds.username, appPassword: creds.password)
        } catch OmkromAuthError.cancelled {
            // La persona cerró la hoja: no es un error.
        } catch {
            errorMessage = "No se pudo iniciar sesión: \(error.localizedDescription)"
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
