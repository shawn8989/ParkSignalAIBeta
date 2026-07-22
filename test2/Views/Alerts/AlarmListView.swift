// AlarmListView.swift
import SwiftUI
import SwiftData

struct AlarmListView: View {
    @StateObject private var alarmService = AlarmService.shared
    @Environment(\.modelContext) private var modelContext
    @State private var alarms: [AlarmService.SimpleAlarm] = []
    @Query private var cars: [Car]
    @Query private var spots: [ParkingSpot]

    var body: some View {
        List {
            if alarms.isEmpty {
                ContentUnavailableView(
                    "No Active Alarms",
                    systemImage: "alarm",
                    description: Text("Alarms and reminders you schedule for parking restrictions will appear here.")
                )
            } else {
                ForEach(alarms) { alarm in
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: alarm.source == .alarmKit ? "alarm.fill" : "bell.fill")
                            .foregroundStyle(alarm.source == .alarmKit ? .orange : .blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(alarm.title)
                                .font(.headline)
                            HStack(spacing: 6) {
                                Text(timerInterval: Date.now...max(Date.now, alarm.endDate), countsDown: true)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if let name = contextName(for: alarm) {
                                    Text("•")
                                    Text(name)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Text(alarm.source == .alarmKit ? "System alarm" : "Notification")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            Task { await cancel(alarm) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Cancel alarm")
                    }
                }
                .onDelete { indexSet in
                    Task {
                        for index in indexSet where index < alarms.count {
                            await cancel(alarms[index], refreshAfter: false)
                        }
                        await refresh()
                    }
                }
            }
        }
        .navigationTitle("Alarms")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button("Cancel All", role: .destructive) {
                    Task {
                        await alarmService.cancelAll()
                        await refresh()
                    }
                }
                .disabled(alarms.isEmpty)
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    @MainActor
    private func refresh() async {
        alarms = await alarmService.allAlarms()
    }

    /// Best-effort "CarName @ SpotLocation" label from the alarm's metadata.
    private func contextName(for alarm: AlarmService.SimpleAlarm) -> String? {
        let carName = alarm.carID.flatMap { id in cars.first(where: { $0.id == id })?.nickname }
        let spotName = alarm.spotID.flatMap { id in spots.first(where: { $0.id == id })?.location }
        switch (carName, spotName) {
        case let (car?, spot?): return "\(car) @ \(spot)"
        case let (car?, nil): return car
        case let (nil, spot?): return spot
        default: return nil
        }
    }

    private func cancel(_ alarm: AlarmService.SimpleAlarm, refreshAfter: Bool = true) async {
        switch alarm.source {
        case .alarmKit:
            await alarmService.cancel(id: alarm.id)
        case .notification:
            if let ident = alarm.notificationIdentifier {
                await alarmService.cancelNotification(identifier: ident)
            }
        }
        if refreshAfter {
            await refresh()
        }
    }
}
