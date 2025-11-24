import SwiftUI

struct AddEditRestrictionView: View {
    @Binding var restriction: Restriction
    var onSave: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var type: RestrictionType = .noParking
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date()
    @State private var daysOfWeek: Set<Int> = []
    
    let allDays: [Int] = Array(0...6)
    let daySymbols: [String] = Calendar.current.shortWeekdaySymbols

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Restriction Type")) {
                    Picker("Type", selection: $type) {
                        ForEach(RestrictionType.allCases, id: \.self) {
                            Text($0.displayName)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section(header: Text("Time")) {
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                }
                Section(header: Text("Days Active")) {
                    ForEach(allDays, id: \.self) { idx in
                        Toggle(daySymbols[idx], isOn: Binding(
                            get: { daysOfWeek.contains(idx) },
                            set: { newValue in
                                if newValue { daysOfWeek.insert(idx) } else { daysOfWeek.remove(idx) }
                            }
                        ))
                    }
                }
            }
            .navigationTitle(restriction.id == UUID() ? "Add Restriction" : "Edit Restriction")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        restriction.type = type
                        restriction.startTime = startTime
                        restriction.endTime = endTime
                        restriction.daysOfWeek = Array(daysOfWeek)
                        onSave?()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                type = restriction.type
                startTime = restriction.startTime
                endTime = restriction.endTime
                daysOfWeek = Set(restriction.daysOfWeek)
            }
        }
    }
}
