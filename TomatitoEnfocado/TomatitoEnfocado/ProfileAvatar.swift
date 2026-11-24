//
//  ProfileAvatar.swift
//  TomatitoEnfocado
//
//  Foto de perfil redonda (propia o Gravatar), usada en Inicio, Ajustes y Perfil.
//

import SwiftUI
import CryptoKit

/// El backend todavía no manda una foto de perfil, pero WordPress usa Gravatar
/// por convención — un hash del email alcanza para pedir la imagen real (o un
/// avatar identicon si la persona no tiene Gravatar configurado), sin tocar la API.
func gravatarURL(for email: String, size: Int = 160) -> URL? {
    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return nil }
    let digest = Insecure.MD5.hash(data: Data(trimmed.utf8))
    let hash = digest.map { String(format: "%02x", $0) }.joined()
    return URL(string: "https://www.gravatar.com/avatar/\(hash)?s=\(size)&d=identicon")
}

/// Foto de perfil redonda: la propia si existe, si no el Gravatar del email.
struct ProfileAvatar: View {
    var url: String?
    var email: String
    var size: CGFloat

    var body: some View {
        AsyncImage(url: URL(string: url ?? "") ?? gravatarURL(for: email)) { phase in
            if let image = phase.image {
                // Recorte desde arriba: en fotos verticales mantiene el rostro entero.
                image.resizable().scaledToFill()
                    .frame(width: size, height: size, alignment: .top)
                    .clipped()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
