import SwiftUI

struct AddEditRestrictionView: View {
    @Binding var restriction: Restriction
    var onSave: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var type: RestrictionType = .noParking
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date()
    // Sunday = 0 ... Saturday = 6
    @State private var daysOfWeek: Set<Int> = []
    let sourceUser: UUID // Pass in from parent

    // Sunday-first labels to match Calendar.shortWeekdaySymbols
    private let daySymbols: [String] = Calendar.current.shortWeekdaySymbols
    private let allDays: [Int] = Array(0...6)

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Restriction Type")) {
                    Picker("Type", selection: $type) {
                        ForEach(RestrictionType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                }
                
                Section(header: Text("Time Window")) {
                    DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                }
                
                Section(header: Text("Days of Week")) {
                    // Simple multi-select list of weekdays, Sunday = 0
                    ForEach(allDays, id: \.self) { index in
                        let label = daySymbols[index]
                        Button {
                            toggleDay(index)
                        } label: {
                            HStack {
                                Text(label)
                                Spacer()
                                if daysOfWeek.contains(index) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Convenience actions
                    HStack {
                        Button("Weekdays") {
                            daysOfWeek = [1, 2, 3, 4, 5]
                        }
                        Spacer()
                        Button("Weekends") {
                            daysOfWeek = [0, 6]
                        }
                        Spacer()
                        Button("Clear") {
                            daysOfWeek.removeAll()
                        }
                    }
                }
            }
            .navigationTitle("Add Restriction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        restriction.type = type
                        restriction.startTime = startTime
                        restriction.endTime = endTime
                        restriction.daysOfWeek = Array(daysOfWeek).sorted()
                        restriction.sourceUser = sourceUser
                        onSave?()
                        dismiss()
                    }
                    .disabled(!isValid)
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
    
    private var isValid: Bool {
        // Allow overnight windows; only require at least one selected day and different times
        !daysOfWeek.isEmpty && startTime != endTime
    }
    
    private func toggleDay(_ index: Int) {
        if daysOfWeek.contains(index) {
            daysOfWeek.remove(index)
        } else {
            daysOfWeek.insert(index)
        }
    }
}
