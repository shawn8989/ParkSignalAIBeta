// AlarmListView.swift
import SwiftUI

struct AlarmListView: View {
    @StateObject private var alarmService = AlarmService.shared
    @State private var alarms: [AlarmService.SimpleAlarm] = []
    @State private var isAuthorized = false

    var body: some View {
        NavigationStack {
            List {
                if alarms.isEmpty {
                    Text("No alarms scheduled.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(alarms) { alarm in
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: alarm.source == .alarmKit ? "alarm" : "bell")
                                        .foregroundStyle(alarm.source == .alarmKit ? .orange : .blue)
                                    Text(alarm.title)
                                        .font(.headline)
                                }
                                HStack(spacing: 6) {
                                    Text(timerInterval: Date.now...max(Date.now, alarm.endDate), countsDown: true)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if let carID = alarm.carID, let car = carName(for: carID) {
                                        Text("•")
                                        Text(car)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            Toggle(isOn: Binding(get: {
                                // On if in list; turning off cancels
                                true
                            }, set: { on in
                                if !on {
                                    Task { await cancel(alarm) }
                                }
                            })) {
                                EmptyView()
                            }
                            .labelsHidden()
                        }
                    }
                    .onDelete { indexSet in
                        Task {
                            for index in indexSet {
                                await alarmService.cancel(id: alarms[index].id)
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
                        Task {
                            let ok = await alarmService.requestAuthorization()
                            isAuthorized = ok
                            await refresh()
                        }
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
                }
            }
            .task { await refresh() }
        }
    }

    @MainActor
    private func refresh() async {
        alarms = await alarmService.allAlarms()
    }

    private func carName(for id: UUID) -> String? {
        // Best-effort lookup from UserDefaults or a cache; if you have SwiftData context here, you could query Cars.
        // For now, return nil.
        return nil
    }

    private func cancel(_ alarm: AlarmService.SimpleAlarm) async {
        switch alarm.source {
        case .alarmKit:
            await alarmService.cancel(id: alarm.id)
        case .notification:
            if let ident = alarm.notificationIdentifier {
                await alarmService.cancelNotification(identifier: ident)
            }
        }
        await refresh()
    }
}
