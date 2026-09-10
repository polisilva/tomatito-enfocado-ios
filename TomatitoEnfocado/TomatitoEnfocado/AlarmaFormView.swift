//
//  AlarmaFormView.swift
//  TomatitoEnfocado
//
//  Formulario "Nueva alarma" / "Editar alarma" (sheet desde AlarmasView).
//

import SwiftUI

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
