// SettingsView
// - User-facing toggles that affect the Dashboard and Map.
// - Developer diagnostics and the beta live scanner are DEBUG-only.

import SwiftUI
import UserNotifications

struct SettingsView: View {
    @AppStorage("alertLeadMinutes") private var leadMinutes: Int = 15
    @AppStorage("showScansOnDashboard") private var showScansOnDashboard: Bool = false
    @AppStorage("autoCenterOnLaunch") private var autoCenterOnLaunch: Bool = true
    @AppStorage("map.showAvailabilityOverlay") private var mapShowAvailabilityOverlay: Bool = true
    @AppStorage("map.showLegend") private var mapShowLegend: Bool = true
    @AppStorage("map.showCityZoneOverlay") private var mapShowCityZoneOverlay: Bool = true
    #if DEBUG
    @AppStorage("feature.liveScannerBeta") private var liveScannerBeta: Bool = false
    #endif

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
