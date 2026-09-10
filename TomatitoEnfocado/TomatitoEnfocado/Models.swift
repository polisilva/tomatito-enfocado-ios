//
//  Models.swift
//  TomatitoEnfocado
//
//  Todos los modelos de datos (Decodable) que representan las respuestas
//  de la API, más los property wrappers auxiliares para decodificarlos.
//

import Foundation

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

// MARK: - Pomodoros

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

// MARK: - Cuenta

/// Datos de la cabecera de "Mi cuenta": email real + estado de conexión con
/// Omkrom (especificación "13. Móvil" — GET /mi-cuenta).
struct CuentaInfo: Decodable {
    var email: String
    var displayName: String
    var omkromConnected: Bool
    var omkromStatusLabel: String
}

// MARK: - Alarmas

struct UpcomingAlarma: Decodable, Identifiable {
    @FlexibleInt var id: Int
    var name: String
    var time: String
    var sound: String?
}

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

// MARK: - Temporizadores

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
