import SwiftUI

struct SpotDangerZoneSection: View {
    let onDelete: () -> Void

    var body: some View {
        Section {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Spot", systemImage: "trash")
            }
        } header: {
            Text("Danger Zone")
        }
    }
}
