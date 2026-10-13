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

    // MARK: - Alarmas
    //
    // En la web las alarmas suenan ~45 s hasta que se pulsa "Detener alarma"
    // (playFinishSound('alarma') en 21-tomatito-notifications.php): "campana"
    // es una sirena sintetizada, no el .mp3, y cualquier otro sonido se repite
    // en bucle durante 45 s.

    private static let alarmDuration: TimeInterval = 45
    private static var alarmPlayer: AVAudioPlayer?
    private static var alarmStopWork: DispatchWorkItem?
    private static var cachedSiren: Data?

    static func playAlarm(_ sound: String?, defaultSound: String = "campana") {
        stopAlarm()
        let key = (sound?.isEmpty ?? true) || sound == "default" ? defaultSound : sound!
        switch key {
        case "silent":
            return
        case "vibracion":
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            return
        case "campana":
            let data = cachedSiren ?? makeSirenWAV()
            cachedSiren = data
            startAlarmPlayer { try AVAudioPlayer(data: data) }
        default:
            guard let url = Bundle.main.url(forResource: key, withExtension: "mp3", subdirectory: "Sounds")
                ?? Bundle.main.url(forResource: key, withExtension: "mp3") else { return }
            startAlarmPlayer { try AVAudioPlayer(contentsOf: url) }
        }
    }

    static func stopAlarm() {
        alarmStopWork?.cancel()
        alarmStopWork = nil
        alarmPlayer?.stop()
        alarmPlayer = nil
    }

    private static func startAlarmPlayer(_ make: () throws -> AVAudioPlayer) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try make()
            p.numberOfLoops = -1
            p.play()
            alarmPlayer = p
            let work = DispatchWorkItem { stopAlarm() }
            alarmStopWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + alarmDuration, execute: work)
        } catch {
            // El sonido es un plus, no algo crítico.
        }
    }

    /// Misma sirena que playAlarmSiren() en la web: onda cuadrada alternando
    /// 880/1320 Hz, un pulso cada 0.75 s (60 pulsos ≈ 45 s), con la misma
    /// envolvente de volumen (subida a 0.22 en 30 ms, caída hasta 620 ms).
    private static func makeSirenWAV() -> Data {
        let rate = 44100
        let pulses = 60
        let total = Int(Double(pulses) * 0.75 * Double(rate)) + Int(0.65 * Double(rate))
        var samples = [Int16](repeating: 0, count: total)
        for i in 0..<pulses {
            let freq = (i % 2 == 0) ? 880.0 : 1320.0
            let startSample = Int(Double(i) * 0.75 * Double(rate))
            let pulseLength = Int(0.65 * Double(rate))
            for n in 0..<pulseLength {
                let t = Double(n) / Double(rate)
                let gain: Double
                if t < 0.03 {
                    gain = 0.0001 * pow(0.22 / 0.0001, t / 0.03)
                } else if t < 0.62 {
                    gain = 0.22 * pow(0.0001 / 0.22, (t - 0.03) / 0.59)
                } else {
                    gain = 0
                }
                let square: Double = sin(2 * .pi * freq * t) >= 0 ? 1 : -1
                samples[startSample + n] = Int16(max(-1, min(1, square * gain)) * Double(Int16.max))
            }
        }
        return wavData(samples: samples, sampleRate: rate)
    }

    private static func wavData(samples: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        let byteCount = samples.count * 2
        data.append("RIFF".data(using: .ascii)!)
        append(UInt32(36 + byteCount))
        data.append("WAVEfmt ".data(using: .ascii)!)
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append("data".data(using: .ascii)!)
        append(UInt32(byteCount))
        for s in samples { append(s) }
        return data
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
