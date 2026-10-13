//
//  HistorialView.swift
//  TomatitoEnfocado
//
//  "Historial completo": mismo comportamiento que la página
//  29-tomatito-historial-completo.php de la web — búsqueda por día / semana /
//  mes / año con flechas anterior-siguiente, resumen del período, lista
//  paginada de 8 en 8 y eliminación con confirmación.
//

import SwiftUI

enum HistorialGranularidad: String, CaseIterable, Identifiable {
    case day, week, month, year
    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: return "Día"
        case .week: return "Semana"
        case .month: return "Mes"
        case .year: return "Año"
        }
    }
}

struct HistorialView: View {
    @EnvironmentObject var session: SessionStore

    @State private var baseDate = Calendar.current.startOfDay(for: Date())
    @State private var granularidad: HistorialGranularidad = .day
    @State private var page = 1
    @State private var result: HistorialPage?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var sesionToDelete: SesionHistorial?

    // La semana de la web empieza en lunes.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    private var range: (from: Date, to: Date) {
        switch granularidad {
        case .day:
            return (baseDate, baseDate)
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: baseDate)?.start ?? baseDate
            return (start, calendar.date(byAdding: .day, value: 6, to: start) ?? start)
        case .month:
            let interval = calendar.dateInterval(of: .month, for: baseDate)
            let start = interval?.start ?? baseDate
            let end = interval.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) } ?? baseDate
            return (start, end)
        case .year:
            let interval = calendar.dateInterval(of: .year, for: baseDate)
            let start = interval?.start ?? baseDate
            let end = interval.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) } ?? baseDate
            return (start, end)
        }
    }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var rangeLabel: String {
        let from = Self.isoDay.string(from: range.from)
        let to = Self.isoDay.string(from: range.to)
        return granularidad == .day ? "Mostrando: \(from)" : "Mostrando: \(from)  →  \(to)"
    }

    var body: some View {
        List {
            Section {
                Picker("Período", selection: $granularidad) {
                    ForEach(HistorialGranularidad.allCases) { g in
                        Text(g.label).tag(g)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.borderless)
                    Spacer()
                    DatePicker(
                        "Fecha",
                        selection: Binding(
                            get: { baseDate },
                            set: { baseDate = calendar.startOfDay(for: $0); page = 1; reload() }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "es"))
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.borderless)
                }
            }

            if let result {
                Section {
                    HStack(spacing: 12) {
                        summaryCard("Sesiones completadas", "\(result.summary.completadas)", accent: false)
                        summaryCard("Minutos enfocado", "\(result.summary.minutos) min", accent: true)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                if let errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                        Button("Reintentar") { reload() }
                    }
                } else if isLoading && result == nil {
                    ProgressView()
                } else if let result, result.data.isEmpty {
                    Text("No hay sesiones en este período.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let result {
                    ForEach(result.data) { sesion in
                        row(sesion)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    sesionToDelete = sesion
                                } label: {
                                    Label("Eliminar", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    sesionToDelete = sesion
                                } label: {
                                    Label("Eliminar", systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                Text(rangeLabel)
            }

            if let pagination = result?.pagination, pagination.totalPages > 1 {
                Section {
                    HStack {
                        Button { goTo(page - 1) } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(.borderless)
                            .disabled(page <= 1)
                        Spacer()
                        Text("Página \(pagination.page) de \(pagination.totalPages)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button { goTo(page + 1) } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(.borderless)
                            .disabled(page >= pagination.totalPages)
                    }
                }
            }
        }
        .navigationTitle("Historial completo")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: granularidad) { _, _ in
            page = 1
            reload()
        }
        .confirmationDialog(
            "¿Estás seguro de que quieres eliminar \"\(sesionToDelete?.name ?? "esta sesión")\"?",
            isPresented: Binding(
                get: { sesionToDelete != nil },
                set: { if !$0 { sesionToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: sesionToDelete
        ) { sesion in
            Button("Eliminar", role: .destructive) {
                Task { await delete(sesion) }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func summaryCard(_ label: String, _ value: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(accent ? Color.red : Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ sesion: SesionHistorial) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(sesion.name).font(.headline)
                Spacer()
                Text(sesion.stateLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(for: sesion.state))
            }
            if let detail = sesion.detailLabel {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Text("\(sesion.dateLabel) · \(sesion.timeLabel) · \(sesion.durationLabel)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func color(for state: String) -> Color {
        switch state {
        case "completed": return .green
        case "cancelled": return .red
        default: return .orange
        }
    }

    private func shift(_ direction: Int) {
        let unit: Calendar.Component
        var value = direction
        switch granularidad {
        case .day: unit = .day
        case .week: unit = .day; value = 7 * direction
        case .month: unit = .month
        case .year: unit = .year
        }
        baseDate = calendar.date(byAdding: unit, value: value, to: baseDate) ?? baseDate
        page = 1
        reload()
    }

    private func goTo(_ newPage: Int) {
        page = newPage
        reload()
    }

    private func reload() {
        Task { await load() }
    }

    private func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        let from = Self.isoDay.string(from: range.from)
        let to = Self.isoDay.string(from: range.to)
        do {
            let loaded: HistorialPage = try await session.client.requestFull(
                "history-sesiones?date_from=\(from)&date_to=\(to)&page=\(page)&per_page=8"
            )
            // Si se borró la última sesión de una página que ya no existe, retrocede.
            if loaded.data.isEmpty, page > 1 {
                page -= 1
                await load()
                return
            }
            result = loaded
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ sesion: SesionHistorial) async {
        do {
            try await session.client.requestRaw("sesiones/\(sesion.id)", method: "DELETE")
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
