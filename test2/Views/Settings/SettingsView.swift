// SettingsView
// - Keeps only user-facing toggles that affect the Dashboard and Map.
// - Removes History/Session-related toggles since sessions are internal now.

import SwiftUI
import UserNotifications

struct SettingsView: View {
    @AppStorage("alertLeadMinutes") private var leadMinutes: Int = 15
    @AppStorage("useAIParsing") private var useAIParsing: Bool = true
    @AppStorage("showScansOnDashboard") private var showScansOnDashboard: Bool = false
    @AppStorage("autoCenterOnLaunch") private var autoCenterOnLaunch: Bool = true
    @AppStorage("map.showAvailabilityOverlay") private var mapShowAvailabilityOverlay: Bool = true
    @AppStorage("map.showLegend") private var mapShowLegend: Bool = true
    @AppStorage("map.showCityZoneOverlay") private var mapShowCityZoneOverlay: Bool = true
    @AppStorage("feature.liveScannerBeta") private var liveScannerBeta: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Notifications")) {
                    Stepper(value: $leadMinutes, in: 0...120, step: 5) {
                        Text("Alert lead time: \(leadMinutes) minute\(leadMinutes == 1 ? "" : "s")")
                    }
                    Text("You will be alerted this many minutes before a restriction starts.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("AI & Parsing")) {
                    Toggle("Use AI to parse scanned text", isOn: $useAIParsing)
                    Text("If off, the app uses a basic on-device parser to extract days and times.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Dashboard")) {
                    Toggle("Show Scans Preview on Dashboard", isOn: $showScansOnDashboard)
                }
                
                Section(header: Text("Map Overlays")) {
                    Toggle("Show Availability Overlays", isOn: $mapShowAvailabilityOverlay)
                    Toggle("Show Legend", isOn: $mapShowLegend)
                    Toggle("Show City Zone Overlays", isOn: $mapShowCityZoneOverlay)
                }

                Section(header: Text("Alerts")) {
                    NavigationLink {
                        AlertsHubView()
                    } label: {
                        Label("Alerts & Alarms", systemImage: "alarm")
                    }
                }

                Section(header: Text("Diagnostics")) {
                    Button {
                        // Schedule a local notification in 5 seconds
                        let center = UNUserNotificationCenter.current()
                        let content = UNMutableNotificationContent()
                        content.title = "Test Notification"
                        content.body = "If you see this, notifications are working."
                        content.sound = .default
                        if #available(iOS 15.0, *) {
                            content.interruptionLevel = .timeSensitive
                        }
                        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                        let req = UNNotificationRequest(identifier: "test.local.notification", content: content, trigger: trigger)
                        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                            if granted { center.add(req) }
                        }
                    } label: {
                        Label("Test Local Notification (5s)", systemImage: "bell.badge")
                    }

                    Button {
                        Task {
                            let ok = await AlarmService.shared.requestAuthorization()
                            if ok {
                                do {
                                    let _ = try await AlarmService.shared.scheduleCountdown(seconds: 10, title: LocalizedStringResource("Test Alarm"))
                                } catch {
                                    // Fallback: local notification alarm if AlarmKit unsupported
                                    let center = UNUserNotificationCenter.current()
                                    let content = UNMutableNotificationContent()
                                    content.title = "Test Alarm"
                                    content.body = "Alarm finished."
                                    content.sound = .default
                                    if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
                                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
                                    let req = UNNotificationRequest(identifier: "alarm.fallback.test.10s", content: content, trigger: trigger)
                                    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                                        if granted { center.add(req) }
                                    }
                                }
                            } else {
                                // No AlarmKit authorization; fallback to local notification
                                let center = UNUserNotificationCenter.current()
                                let content = UNMutableNotificationContent()
                                content.title = "Test Alarm"
                                content.body = "Alarm finished."
                                content.sound = .default
                                if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
                                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
                                let req = UNNotificationRequest(identifier: "alarm.fallback.test.10s", content: content, trigger: trigger)
                                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                                    if granted { center.add(req) }
                                }
                            }
                        }
                    } label: {
                        Label("Test Alarm (10s)", systemImage: "alarm")
                    }
                }

                Section(header: Text("Beta")) {
                    Toggle("Enable Live Scanner (beta)", isOn: $liveScannerBeta)
                    if liveScannerBeta {
                        if #available(iOS 16.0, *) {
                            NavigationLink {
                                LiveScannerBetaView()
                            } label: {
                                Label("Try Live Scanner (Beta)", systemImage: "camera.viewfinder")
                            }
                        } else {
                            Text("Live scanner requires iOS 16+")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

@available(iOS 16.0, *)
private struct LiveScannerBetaView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ParkingSignScannerView(onResult: { _, _ in
            // Beta: dismiss on result; photo-based flow remains the primary path
            dismiss()
        }, onCancel: {
            dismiss()
        }, onRequestQuickScan: nil)
        .navigationTitle("Live Scanner (Beta)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
