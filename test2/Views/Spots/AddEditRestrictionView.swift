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
    @State private var hasLimit = false
    @State private var limitMinutes = 120
    @State private var verified = false
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
                
                Section("Maximum Stay") {
                    Toggle("A maximum stay applies", isOn: $hasLimit)
                    if hasLimit { Stepper("\(limitMinutes) minutes", value: $limitMinutes, in: 1...10080) }
                    Text("Matching start and end times mean all day. Hours and maximum stay are separate.").font(.footnote)
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
                        .frame(minHeight: 44)
                        .accessibilityLabel(Calendar.current.weekdaySymbols[index])
                        .accessibilityValue(daysOfWeek.contains(index) ? "Selected" : "Not selected")
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
            .safeAreaInset(edge: .bottom) {
                Toggle("I checked that this is a complete weekly rule", isOn: $verified)
                    .padding().background(.regularMaterial)
            }
            .environment(\.timeZone, restriction.spot.flatMap { TimeZone(identifier: $0.timeZoneIdentifier) } ?? .current)
            .navigationTitle("Edit Weekly Rule")
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
                        restriction.durationMinutes = hasLimit ? limitMinutes : nil
                        restriction.needsReview = false
                        restriction.reviewReasons = []
                        if let scan = restriction.scan {
                            scan.needsReview = scan.restrictionsList.contains(where: \.needsReview)
                        }
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
                daysOfWeek = Set(restriction.daysOfWeek.isEmpty ? Array(0...6) : restriction.daysOfWeek)
                hasLimit = restriction.durationMinutes != nil
                limitMinutes = restriction.durationMinutes ?? 120
            }
        }
    }
    
    private var isValid: Bool {
        // All-day and overnight windows are valid; unknown types are not verified rules.
        verified && type != .other && !daysOfWeek.isEmpty && (type != .timeLimited || hasLimit)
    }
    
    private func toggleDay(_ index: Int) {
        if daysOfWeek.contains(index) {
            daysOfWeek.remove(index)
        } else {
            daysOfWeek.insert(index)
        }
    }
}
