import SwiftUI
import UserNotifications

/// AlertsHubView
/// A single place to manage alert permissions, quick tests, and navigation to alarm/notification lists.
/// - Shows current authorization status for Notifications and AlarmKit (best-effort).
/// - Lets the user request permissions, adjust lead time, and trigger test alerts.
/// - Keeps navigation links to the detailed Alarms and Notifications screens.
struct AlertsHubView: View {
    // Lead time for restriction reminders (shared with NotificationManager via @AppStorage)
    @AppStorage("alertLeadMinutes") private var leadMinutes: Int = 15

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var alarmAuthorized: Bool = false
    @State private var isRequesting = false
    @State private var lastTestError: String? = nil

    var body: some View {
        List {
                // Status section: show current permission state for notifications and alarms
                Section("Status") {
                    HStack {
                        Label("Notifications", systemImage: "bell")
                        Spacer()
                        Text(statusText(notificationStatus))
                            .foregroundStyle(statusColor(notificationStatus))
                    }
                    HStack {
                        Label("AlarmKit", systemImage: "alarm")
                        Spacer()
                        Text(alarmAuthorized ? "Authorized" : "Not Authorized")
                            .foregroundStyle(alarmAuthorized ? .green : .secondary)
                    }
                }

                // Configuration for lead time (what NotificationManager uses to schedule weekly reminders)
                Section("Configuration") {
                    Stepper(value: $leadMinutes, in: 0...120, step: 5) {
                        Text("Alert lead time: \(leadMinutes) minute\(leadMinutes == 1 ? "" : "s")")
                    }
                    Text("Alerts will fire this many minutes before a restriction starts.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // Permission & test actions
                Section("Actions") {
                    Button {
                        Task { await requestNotificationPermission() }
                    } label: {
                        Label("Request Notification Permission", systemImage: "bell.badge")
                    }
                    .disabled(isRequesting)

                    Button {
                        Task {
                            // Schedule a simple local notification after 5 seconds
                            await NotificationManager.shared.scheduleTestNotification(seconds: 5)
                        }
                    } label: {
                        Label("Test Notification (5s)", systemImage: "bell")
                    }

                    Button {
                        Task {
                            // Best-effort AlarmKit test; fallback to a local notification if not available
                            let ok = await AlarmService.shared.requestAuthorization()
                            if ok {
                                do {
                                    let _ = try await AlarmService.shared.scheduleCountdown(seconds: 10, title: LocalizedStringResource("Test Alarm"))
                                } catch {
                                    lastTestError = error.localizedDescription
                                }
                            } else {
                                await NotificationManager.shared.scheduleTestNotification(seconds: 10)
                            }
                            await refreshStatuses()
                        }
                    } label: {
                        Label("Test Alarm (10s)", systemImage: "alarm")
                    }
                }

                // Navigation to detailed lists
                Section("Lists") {
                    NavigationLink(destination: AlarmListView()) {
                        Label("Alarms", systemImage: "alarm")
                    }
                    NavigationLink(destination: NotificationsView()) {
                        Label("Notifications", systemImage: "bell")
                    }
                }

            if let err = lastTestError {
                Section("Last Error") {
                    Text(err).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Alerts")
        .task { await refreshStatuses() }
    }

    // MARK: - Helpers

    private func statusText(_ s: UNAuthorizationStatus) -> String {
        switch s {
        case .authorized: return "Allowed"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        case .denied: return "Denied"
        case .notDetermined: return "Ask Me"
        @unknown default: return "Unknown"
        }
    }

    private func statusColor(_ s: UNAuthorizationStatus) -> Color {
        switch s {
        case .authorized: return .green
        case .provisional, .ephemeral: return .orange
        case .denied: return .red
        case .notDetermined: return .secondary
        @unknown default: return .secondary
        }
    }

    private func refreshStatuses() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        notificationStatus = settings.authorizationStatus
        // Avoid prompting the user when refreshing status. AlarmKit currently lacks a non-interactive status API in our wrapper,
        // so we do not call requestAuthorization() here. Instead, we use a cached value to avoid prompting.
        alarmAuthorized = AlarmService.shared.isAuthorizedCached()
    }

    private func requestNotificationPermission() async {
        isRequesting = true
        defer { isRequesting = false }
        _ = await NotificationManager.shared.requestAuthorizationIfNeeded()
        await refreshStatuses()
    }
}
