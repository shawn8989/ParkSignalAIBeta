import SwiftUI
import SwiftData

struct ParkSessionEditView: View {
    @Bindable var session: ParkSession
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    init(session: ParkSession) {
        self._session = .init(projectedValue: .init(wrappedValue: session))
    }

    var body: some View {
        NavigationView {
            Form {
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
                        DatePicker("Ended At", selection: Binding($session.endedAt, Date()), displayedComponents: [.date, .hourAndMinute])
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
