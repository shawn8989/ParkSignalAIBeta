import SwiftUI
import SwiftData

struct SpotEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var spot: ParkingSpot

    @State private var locationText: String = ""
    @State private var streetSide: String = "right"

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Title / Location")) {
                    TextField("Location label", text: $locationText)
                        .textInputAutocapitalization(.words)
                }
                Section(header: Text("Street Side")) {
                    Picker("Street Side", selection: $streetSide) {
                        Text("Left").tag("left")
                        Text("Right").tag("right")
                        Text("Unknown").tag("unknown")
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
        streetSide = spot.streetSide
    }

    private func save() {
        spot.location = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        spot.streetSide = streetSide
        do { try context.save() } catch { }
        dismiss()
    }
}

#Preview {
    let model = ModelContainer.preview
    let spot = ParkingSpot(location: "123 Main St", latitude: 0, longitude: 0, streetSide: "right")
    return SpotEditView(spot: spot)
        .environment(\.modelContext, model.mainContext)
}
