// AlarmListView.swift
import SwiftUI

struct AlarmListView: View {
    @StateObject private var alarmService = AlarmService.shared
    @State private var alarms: [AlarmService.SimpleAlarm] = []

    var body: some View {
        List {
            if alarms.isEmpty {
                Text("No alarms scheduled.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(alarms) { alarm in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(alarm.title)
                                .font(.headline)
                            Text(timerInterval: Date.now...max(alarm.endDate, .now), countsDown: true)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            Task {
                                await alarmService.cancel(id: alarm.id)
                                await refresh()
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Alarms")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        _ = await alarmService.requestAuthorization()
                        await refresh()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .task { await refresh() }
    }

    @MainActor
    private func refresh() async {
        alarms = await alarmService.allAlarms()
    }
}
