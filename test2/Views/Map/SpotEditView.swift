import SwiftUI
import SwiftData
import Foundation

struct SpotEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var spot: ParkingSpot

    @State private var locationText: String = ""
    @State private var orientation: String = "with"

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Title / Location")) {
                    TextField("Location label", text: $locationText)
                        .textInputAutocapitalization(.words)
                }
                Section(header: Text("Parking Orientation")) {
                    Picker("Orientation", selection: $orientation) {
                        Text("With Traffic").tag("with")
                        Text("Against Traffic").tag("against")
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Edit Spot")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear { load() }
        }
    }

    private func load() {
        locationText = spot.location
        orientation = DrivingSide.selection(from: spot.streetSide)
    }

    private func save() {
        spot.location = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        if orientation == "unknown" {
            spot.streetSide = "unknown"
        } else {
            spot.streetSide = DrivingSide.storedSide(from: orientation)
        }
        do { try context.save() } catch { }
        dismiss()
    }
}

#Preview {
    let spot = ParkingSpot(location: "123 Main St", latitude: 0, longitude: 0, streetSide: "right")
    return SpotEditView(spot: spot)
        .modelContainer(for: [ParkingSpot.self], inMemory: true)
}
