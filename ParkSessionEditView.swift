import SwiftUI
import SwiftData

struct ParkSessionEditView: View {
    @Bindable var session: ParkSession
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var cars: [Car]
    @Query private var spots: [ParkingSpot]

    init(session: ParkSession) {
        self._session = .init(projectedValue: .init(wrappedValue: session))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Car") {
                    Picker("Car", selection: Binding<UUID?> (
                        get: { session.car?.id },
                        set: { newID in session.car = cars.first(where: { $0.id == newID }) }
                    )) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(cars, id: \.id) { car in
                            Text(car.nickname).tag(Optional(car.id))
                        }
                    }
                }
                Section("Spot") {
                    Picker("Spot", selection: Binding<UUID?> (
                        get: { session.spot?.id },
                        set: { newID in session.spot = spots.first(where: { $0.id == newID }) }
                    )) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(spots, id: \.id) { spot in
                            Text(spot.location).tag(Optional(spot.id))
                        }
                    }
                }
                Section("Start") {
                    DatePicker("Started At", selection: $session.startedAt, displayedComponents: [.date, .hourAndMinute])
                }
                Section("End") {
                    Toggle("Has Ended", isOn: Binding(
                        get: { session.endedAt != nil },
                        set: { newValue in
                            if newValue == false {
                                session.endedAt = nil
                            } else if session.endedAt == nil {
                                session.endedAt = Date()
                            }
                        }
                    ))
                    if session.endedAt != nil {
                        DatePicker(
                            "Ended At",
                            selection: Binding<Date>(
                                get: { session.endedAt ?? Date() },
                                set: { newValue in session.endedAt = newValue }
                            ),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }
            }
            .navigationTitle("Edit Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        modelContext.insert(session)
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
