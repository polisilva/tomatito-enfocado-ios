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
    @FlexibleInt var work: Int
    @FlexibleInt var shortBreak: Int
    @FlexibleInt var longBreak: Int
}

/// Un pomodoro en marcha, tal como lo ve el móvil. Ahora es un elemento de
/// lista (no un único activo global) porque, igual que en la web, pueden
/// correr varios pomodoros distintos al mismo tiempo — "20260914": la regla
/// vieja de "solo uno a la vez" quedó obsoleta cuando la web pasó a permitir
/// varios en paralelo.
struct ActivePomodoroItem: Identifiable {
    let timerId: Int
    let pomodoroId: Int
    var name: String
    var phase: String
    var totalSeconds: Int
    var secondsLeft: Int
    var isPaused: Bool
    var cycle: Int
    var cyclesTotal: Int
    var workMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    var isFinished: Bool = false
    var id: Int { timerId }

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

    var cycleLabel: String {
        "\(min(cycle + 1, cyclesTotal))/\(cyclesTotal)"
    }

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
