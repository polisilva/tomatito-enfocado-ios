//
//  SoundPlayer.swift
//  TomatitoEnfocado
//
//  Reproduce los mismos sonidos que la web (playFinishSound() en
//  21-tomatito-notifications.php) cuando termina una fase de pomodoro, un
//  temporizador, o suena una alarma. Los .mp3 en Sounds/ son los mismos
//  archivos que usa la web (wp-content/uploads/2026/07/*.mp3).
//

import AVFoundation

enum SoundPlayer {
    private static var player: AVAudioPlayer?

    /// `sound` es el valor guardado en el pomodoro/temporizador/alarma
    /// ("clasico", "campana", "digital", "suave", "silent", "vibracion", o
    /// "default"/nil). `defaultSound` es el que se usa para "default" — la
    /// web lo saca de Ajustes (sonido_pomodoro/temporizador/alarma), acá se
    /// usa el mismo valor por defecto porque el móvil no tiene esa pantalla.
    static func play(_ sound: String?, defaultSound: String) {
        let key = (sound?.isEmpty ?? true) || sound == "default" ? defaultSound : sound!
        switch key {
        case "silent":
            return
        case "vibracion":
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        default:
            playFile(named: key)
        }
    }

    private static func playFile(named name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: name, withExtension: "mp3") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            // El sonido es un plus, no algo crítico — si falla, no interrumpe el flujo.
        }
    }
}
