//
//  PerfilView.swift
//  TomatitoEnfocado
//
//  Tela "Mi perfil": foto, datos de cuenta, plan Omkrom y gestión de
//  Application Passwords. El "cambiar contraseña" del móvil se resuelve
//  gestionando Application Passwords (crear una nueva / revocar viejas) en
//  vez de tocar la contraseña principal de la cuenta — el app nunca la usa
//  para nada, así que exponerla aquí sería una superficie de riesgo inútil.
//

import SwiftUI
import PhotosUI
import UIKit

private func formattedDate(_ iso: String?) -> String? {
    guard let iso, !iso.isEmpty else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    return iso
}

struct PerfilView: View {
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var perfil: PerfilInfo?
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var avatarErrorMessage: String?

    @State private var appPasswords: [ApplicationPasswordInfo] = []
    @State private var isLoadingPasswords = false
    @State private var newPasswordName = ""
    @State private var showingCreatePassword = false
    @State private var createdPassword: CreatedApplicationPassword?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        ZStack(alignment: .bottomTrailing) {
                            AsyncImage(url: URL(string: perfil?.avatarURL ?? "")) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                            .opacity(isUploadingAvatar ? 0.4 : 1)
                            .overlay {
                                if isUploadingAvatar { ProgressView() }
                            }

                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.system(size: 26))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .red)
                                    .background(Circle().fill(.white))
                            }
                            .disabled(isUploadingAvatar)
                        }

                        Text(perfil?.displayName ?? session.username).font(.headline)
                        Text(perfil?.email ?? session.username).font(.footnote).foregroundStyle(.secondary)

                        if let avatarErrorMessage {
                            Text(avatarErrorMessage).font(.caption).foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section("Plan") {
                    if let perfil {
                        LabeledContent("Plan", value: perfil.plan)
                        LabeledContent("Estado", value: perfil.status)
                        LabeledContent("Vencimiento", value: perfil.expires)
                        LabeledContent("Pomodoros", value: perfil.pomodorosLimit.label)
                        LabeledContent("Temporizadores", value: perfil.temporizadoresLimit.label)
                        LabeledContent("Alarmas", value: perfil.alarmasLimit.label)
                    } else if isLoading {
                        ProgressView()
                    } else if let errorMessage {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(errorMessage).foregroundStyle(.red).font(.footnote)
                            Button("Reintentar") { Task { await load() } }
                        }
                    }
                }

                Section {
                    if isLoadingPasswords && appPasswords.isEmpty {
                        ProgressView()
                    } else if appPasswords.isEmpty {
                        Text("Ninguna contraseña de aplicación creada todavía.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appPasswords) { pw in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pw.name).font(.subheadline.weight(.medium))
                                if let created = formattedDate(pw.created) {
                                    Text("Creada: \(created)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await revoke(pw) }
                                } label: {
                                    Label("Revocar", systemImage: "trash")
                                }
                            }
                        }
                    }
                    Button {
                        newPasswordName = ""
                        showingCreatePassword = true
                    } label: {
                        Label("Nueva contraseña de aplicación", systemImage: "plus")
                    }
                } header: {
                    Text("Contraseñas de aplicación")
                } footer: {
                    Text("El app usa una de estas para iniciar sesión, no tu contraseña principal. Crea una para cada dispositivo y revoca las que ya no uses.")
                }

                Section {
                    Button("Salir", role: .destructive) {
                        session.logout()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Mi perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .task { await load() }
            .onChange(of: selectedPhoto) { _, newItem in
                Task { await uploadPickedPhoto(newItem) }
            }
            .alert("Nueva contraseña de aplicación", isPresented: $showingCreatePassword) {
                TextField("Nombre (ej: iPhone de Poliany)", text: $newPasswordName)
                Button("Cancelar", role: .cancel) {}
                Button("Crear") { Task { await createPassword() } }
            } message: {
                Text("Dale un nombre para identificarla luego.")
            }
            .sheet(item: $createdPassword) { created in
                NavigationStack {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text("Contraseña creada").font(.headline)
                        Text("Guárdala ahora — WordPress no la vuelve a mostrar.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Text(created.password)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = created.password
                        } label: {
                            Label("Copiar", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    .padding()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Listo") { createdPassword = nil }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    private func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            perfil = try await session.client.request("mi-perfil")
        } catch {
            errorMessage = error.localizedDescription
        }
        await loadPasswords()
    }

    private func loadPasswords() async {
        isLoadingPasswords = true
        defer { isLoadingPasswords = false }
        do {
            appPasswords = try await session.client.requestWordPress("/wp-json/wp/v2/users/me/application-passwords")
        } catch {
            // Silencioso: sección secundaria, no debe bloquear el resto del perfil.
        }
    }

    private func createPassword() async {
        let name = newPasswordName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            let created: CreatedApplicationPassword = try await session.client.requestWordPress(
                "/wp-json/wp/v2/users/me/application-passwords",
                method: "POST",
                body: ["name": name]
            )
            createdPassword = created
            await loadPasswords()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revoke(_ password: ApplicationPasswordInfo) async {
        appPasswords.removeAll { $0.id == password.id }
        try? await session.client.deleteWordPress("/wp-json/wp/v2/users/me/application-passwords/\(password.uuid)")
    }

    private func uploadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        avatarErrorMessage = nil
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }

        // Se reencoda siempre a JPEG: la foto puede venir en HEIC (formato
        // por defecto del iPhone), y el Content-Type que declaramos abajo
        // es fijo "image/jpeg" — reencodar evita el desajuste.
        let data: Data
        do {
            guard let loaded = try await item.loadTransferable(type: Data.self) else {
                avatarErrorMessage = "Lectura: sin datos (loadTransferable devolvió nil)."
                return
            }
            data = loaded
        } catch {
            let nsError = error as NSError
            avatarErrorMessage = "Lectura: \(nsError.domain) #\(nsError.code) — \(nsError.localizedDescription)"
            return
        }

        guard let uiImage = UIImage(data: data), let jpegData = uiImage.jpegData(compressionQuality: 0.85) else {
            avatarErrorMessage = "Conversión: no se pudo decodificar la imagen (\(data.count) bytes recibidos)."
            return
        }

        do {
            let avatarURL = try await session.client.uploadAvatar(
                imageData: jpegData, filename: "avatar.jpg", mimeType: "image/jpeg"
            )
            perfil?.avatarURL = avatarURL
        } catch {
            let nsError = error as NSError
            avatarErrorMessage = "Subida: \(nsError.domain) #\(nsError.code) — \(nsError.localizedDescription)"
        }
    }
}
