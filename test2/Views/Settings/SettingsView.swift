// SettingsView
// - User-facing toggles that affect the Dashboard and Map.
// - Developer diagnostics and the beta live scanner are DEBUG-only.

import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var storage = StorageStatus.shared
    @ObservedObject private var reminders = ReminderCoordinator.shared
    @AppStorage("parkingRemindersEnabledOnDevice") private var remindersEnabled = false
    @AppStorage("alertLeadMinutes") private var leadMinutes: Int = 15
    @AppStorage("showScansOnDashboard") private var showScansOnDashboard: Bool = false
    @AppStorage("autoCenterOnLaunch") private var autoCenterOnLaunch: Bool = true
    @AppStorage("map.showAvailabilityOverlay") private var mapShowAvailabilityOverlay: Bool = true
    @AppStorage("map.showLegend") private var mapShowLegend: Bool = true
    @AppStorage("map.showCityZoneOverlay") private var mapShowCityZoneOverlay: Bool = true
    #if DEBUG
    @AppStorage("feature.liveScannerBeta") private var liveScannerBeta: Bool = false
    #endif

    private var appVersionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Storage & Sync") {
                    Text(storage.summary)
                    Text(storage.detail).font(.footnote)
                    Button("Check iCloud Status") { Task { await storage.refreshAccount() } }
                }
                Section(header: Text("Notifications")) {
                    Toggle("Parking reminders on this device", isOn: $remindersEnabled)
                        .onChange(of: remindersEnabled) { _, enabled in
                            Task {
                                if enabled { await reminders.enable(context: context) }
                                else { await reminders.reconcile(context: context) }
                            }
                        }
                    Text("Reminders are scheduled only on devices where you enable them. They do not sync through iCloud. Open the app at least every two weeks to extend the schedule; at most 48 upcoming reminders are kept.").font(.footnote)
                    if remindersEnabled {
                        Button("Restore Cancelled Parking Reminders") { Task { await reminders.resumeCancelled(context: context) } }
                    }
                    if let message = reminders.statusMessage { Text(message).font(.footnote) }
                    Stepper(value: $leadMinutes, in: 0...120, step: 5) {
                        Text("Alert lead time: \(leadMinutes) minute\(leadMinutes == 1 ? "" : "s")")
                    }
                    Text("You will be alerted this many minutes before a restriction starts.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Dashboard")) {
                    Toggle("Show Scans Preview on Dashboard", isOn: $showScansOnDashboard)
                }

                Section(header: Text("Map Overlays")) {
                    Toggle("Show Availability Overlays", isOn: $mapShowAvailabilityOverlay)
                    Toggle("Show Legend", isOn: $mapShowLegend)
                    #if DEBUG
                    Toggle("Show Sample City Zones (Debug)", isOn: $mapShowCityZoneOverlay)
                    #endif
                }

                Section(header: Text("Alerts")) {
                    NavigationLink {
                        AlertsHubView()
                    } label: {
                        Label("Alerts & Alarms", systemImage: "alarm")
                    }
                }

                Section(header: Text("About")) {
                    Link(destination: LegalLinks.privacy) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Link(destination: LegalLinks.support) {
                        Label("Support", systemImage: "questionmark.circle")
                    }
                    LabeledContent("Version", value: appVersionString)
                        .accessibilityLabel("Version \(appVersionString)")
                }

                #if DEBUG
                Section(header: Text("Diagnostics (Debug)")) {
                    Button {
                        let center = UNUserNotificationCenter.current()
                        let content = UNMutableNotificationContent()
                        content.title = "Test Notification"
                        content.body = "If you see this, notifications are working."
                        content.sound = .default
                        content.interruptionLevel = .timeSensitive
                        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                        let req = UNNotificationRequest(identifier: "test.local.notification", content: content, trigger: trigger)
                        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                            if granted { center.add(req) }
                        }
                    } label: {
                        Label("Test Local Notification (5s)", systemImage: "bell.badge")
                    }

                    Button {
                        Task { _ = try? await AlarmService.shared.scheduleCountdown(seconds: 10, title: LocalizedStringResource("Test Alarm")) }
                    } label: {
                        Label("Test Alarm (10s)", systemImage: "alarm")
                    }
                }

                Section(header: Text("Beta (Debug)")) {
                    Toggle("Enable Live Scanner (beta)", isOn: $liveScannerBeta)
                    if liveScannerBeta {
                        NavigationLink {
                            LiveScannerBetaView()
                        } label: {
                            Label("Try Live Scanner (Beta)", systemImage: "camera.viewfinder")
                        }
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
        }
    }
}

// Published from the gh-pages branch; source copies live in docs/legal/.
private enum LegalLinks {
    static let privacy = URL(string: "https://shawn8989.github.io/ParkSignalAIBeta/legal/privacy.html")!
    static let support = URL(string: "https://shawn8989.github.io/ParkSignalAIBeta/legal/support.html")!
}

#if DEBUG
private struct LiveScannerBetaView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ParkingSignScannerView(onResult: { _, _ in
            dismiss()
        }, onCancel: {
            dismiss()
        }, onRequestQuickScan: nil)
        .navigationTitle("Live Scanner (Beta)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
