import SwiftUI
import SwiftData
import MapKit
import UserNotifications

/// QuickSpotActionsSheet
/// - Focuses on starting/stopping parking at a specific spot for a selected car.
/// - Session management is centralized via Car+Parking extension (`startParking`, `endCurrentParking`).
/// - Restriction notifications are scheduled/canceled via NotificationManager for consistency.
/// - Restriction timing utilities come from ParkingSpot+Status (e.g. `nextRestrictionDate`).
/// This reduces duplication and fixes previously glitchy session behavior across the app.
struct QuickSpotActionsSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    var spot: ParkingSpot
    
    @Query private var cars: [Car]
    @Query private var sessions: [ParkSession]
    
    @State private var selectedCarID: UUID? = nil
    @State private var notesText: String = ""
    
    init(spot: ParkingSpot) {
        self.spot = spot
        _notesText = State(initialValue: spot.notes ?? "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Spot") {
                    VStack(alignment: .leading) {
                        Text(spot.location)
                        if let coordinate = spot.locationCoordinate {
                            Text("Lat: \(coordinate.latitude), Lon: \(coordinate.longitude)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Car") {
                    Picker("Car", selection: $selectedCarID) {
                        ForEach(cars, id: \.id) { car in
                            Text(car.nickname).tag(car.id as UUID?)
                        }
                    }
                    .onAppear {
                        if selectedCarID == nil {
                            if let lastUsedID = UserDefaults.standard.string(forKey: "CarList.LastUsedCarID"),
                               let uuid = UUID(uuidString: lastUsedID),
                               cars.contains(where: { $0.id == uuid }) {
                                selectedCarID = uuid
                            } else {
                                selectedCarID = cars.first?.id
                            }
                        }
                    }
                }
                
                Section("Actions") {
                    Button("Start Parking") {
                        guard let selectedCarID = selectedCarID,
                              let car = cars.first(where: { $0.id == selectedCarID }) else { return }

                        // Use centralized session management: this ends any prior active session for this car
                        // and starts a new one at this spot. This avoids scattered, glitch‑prone logic.
                        let _ = car.startParking(at: spot, now: Date(), in: context)

                        // Persist the change and remember the last used car
                        try? context.save()
                        UserDefaults.standard.set(car.id.uuidString, forKey: "CarList.LastUsedCarID")

                        // Schedule weekly notifications for this spot's restrictions via the NotificationManager
                        // (centralized policy and lead time). This runs asynchronously so the UI can dismiss immediately.
                        Task { await NotificationManager.shared.schedule(for: spot.restrictions, spot: spot) }

                        // Close the sheet
                        dismiss()
                    }
                    
                    if let selectedCarID = selectedCarID,
                       let car = cars.first(where: { $0.id == selectedCarID }),
                       let activeSession = activeSession(for: car) {
                        Button("Stop Parking", role: .destructive) {
                            // Centralized end for the selected car's active session
                            car.endCurrentParking(at: Date())
                            try? context.save()

                            // Cancel any previously scheduled weekly notifications for this spot
                            Task { await NotificationManager.shared.cancel(for: spot.restrictions, spot: spot) }

                            dismiss()
                        }
                    }
                    
                    Button("Navigate") {
                        let coordinate = spot.locationCoordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
                        let placemark = MKPlacemark(coordinate: coordinate)
                        let mapItem = MKMapItem(placemark: placemark)
                        mapItem.name = spot.location
                        mapItem.openInMaps()
                    }
                }
                
                Section("Notes") {
                    TextEditor(text: $notesText)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Spot Actions")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        spot.notes = notesText
                        try? context.save()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    /// Returns the active session for this car at the current spot, if any.
    /// Uses the centralized `Car.activeSession` helper to avoid duplicating predicates.
    private func activeSession(for car: Car) -> ParkSession? {
        if let current = car.activeSession, current.spot?.id == spot.id { return current }
        return nil
    }
}

private extension ParkingSpot {
    var locationCoordinate: CLLocationCoordinate2D? {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
