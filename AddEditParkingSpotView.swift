import SwiftUI

struct AddEditParkingSpotView: View {
    @Binding var spot: ParkingSpot
    var onSave: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    
    @State private var location: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Location")) {
                    TextField("e.g. 123 Main St", text: $location)
                }
            }
            .navigationTitle(spot.id == UUID() ? "Add Spot" : "Edit Spot")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        spot.location = location
                        onSave?()
                        dismiss()
                    }
                    .disabled(location.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                location = spot.location
            }
        }
    }
}
