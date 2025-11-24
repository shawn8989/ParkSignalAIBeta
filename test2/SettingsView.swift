import SwiftUI

struct SettingsView: View {
    @AppStorage("alertLeadMinutes") private var leadMinutes: Int = 15

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
            }
            .navigationTitle("Settings")
        }
    }
}
