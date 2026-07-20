import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @AppStorage("alertLeadMinutes") private var leadMinutes: Int = 15
    @AppStorage(AIAnalyzerService.apiKeyDefaultsKey) private var apiKey: String = ""

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

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

                    HStack {
                        Text("Permission")
                        Spacer()
                        Text(notificationStatusLabel)
                            .foregroundStyle(notificationStatus == .denied ? .red : .secondary)
                    }
                    if notificationStatus == .denied {
                        Button("Open Settings to enable notifications") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.footnote)
                    }
                }

                Section(header: Text("AI Analysis")) {
                    SecureField("OpenAI API key (optional)", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text(AIAnalyzerService.isConfigured
                         ? "AI refinement is on. Scans are first parsed on-device, then refined by AI."
                         : "Without a key, signs are parsed on-device only. Add a key to improve accuracy on complex signs.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Alarms")) {
                    NavigationLink("Scheduled Alarms") {
                        AlarmListView()
                    }
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .task { await refreshNotificationStatus() }
        }
    }

    private var notificationStatusLabel: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "Allowed"
        case .denied: return "Denied"
        case .notDetermined: return "Not requested yet"
        @unknown default: return "Unknown"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
    }
}
