import SwiftUI
import SwiftData

struct AnalysisConfirmationView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var cars: [Car]
    let spot: ParkingSpot
    let sourceUser: UUID
    let ocrText: String
    let photoFilename: String?
    let analysis: AIAnalysisResponse
    var scan: SignScan? = nil
    var onFinished: (([Restriction]) -> Void)? = nil

    @State private var items: [Item] = []
    @State private var parkedHere = false
    @State private var confirmed = false
    @State private var saving = false
    @State private var saveError: String?

    private struct Item: Identifiable {
        let id = UUID()
        var include = true
        var draft: ReviewedRestriction
    }
    private var unresolved: Bool { analysis.restrictions.contains(where: \.requiresReview) || items.contains { $0.include && ($0.draft.needsReview || $0.draft.type == .other) } }
    private var spotCalendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: spot.timeZoneIdentifier) ?? .current
        return calendar
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Compare these suggestions with every sign on this curb. A scan cannot confirm that parking is legal.")
                    if unresolved {
                        Label("Review required", systemImage: "exclamationmark.triangle")
                        Text("Some conditions cannot be represented as a weekly rule. They will be saved as unresolved, without automatic reminders or a clear parking signal.")
                    }
                }
                Section("Original sign text") { Text(ocrText).textSelection(.enabled) }
                if items.isEmpty {
                    Section { Text("No supported rule was found. Save the photo and add a verified rule manually from the spot screen.") }
                }
                ForEach($items) { $item in
                    Section {
                        Toggle("Include rule", isOn: $item.include)
                        if item.include {
                            Picker("Type", selection: $item.draft.type) {
                                ForEach(RestrictionType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                            DatePicker("From", selection: $item.draft.start, displayedComponents: .hourAndMinute)
                            DatePicker("Until", selection: $item.draft.end, displayedComponents: .hourAndMinute)
                            Text("Matching start and end times mean all day.").font(.footnote)
                            if let minutes = item.draft.durationMinutes {
                                Stepper("Maximum stay: \(minutes) minutes", value: Binding(
                                    get: { item.draft.durationMinutes ?? 1 },
                                    set: { item.draft.durationMinutes = $0 }), in: 1...10080)
                                Text("The limit applies within the selected days and hours; it is separate from those hours.").font(.footnote)
                            }
                            ForEach(0..<7, id: \.self) { day in
                                Toggle(Calendar.current.weekdaySymbols[day], isOn: Binding(
                                    get: { item.draft.days.contains(day) },
                                    set: { on in
                                        if on { if !item.draft.days.contains(day) { item.draft.days.append(day) } }
                                        else { item.draft.days.removeAll { $0 == day } }
                                    }))
                            }
                            ForEach(item.draft.reviewReasons, id: \.self) { Text($0).font(.footnote) }
                        }
                    }
                }
                Section {
                    Toggle("I checked the included rules against the signs", isOn: $confirmed)
                    if !unresolved {
                        Toggle("I am parked here — enable reminders on this device", isOn: $parkedHere)
                    }
                }
            }
            .environment(\.timeZone, spotCalendar.timeZone)
            .navigationTitle("Review Sign")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(unresolved ? "Save for Review" : "Save Rules") { Task { await save() } }
                        .disabled(!confirmed || saving || !items.contains(where: \.include) || items.contains { $0.include && $0.draft.days.isEmpty })
                }
            }
            .onAppear { if items.isEmpty { items = analysis.restrictions.map(makeItem) } }
            .alert("Couldn't Save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(saveError ?? "") }
        }
    }

    private func makeItem(_ rule: AIRestriction) -> Item {
        let start = DateTimeUtils.parseHHmm(rule.startTime) ?? (hour: 0, minute: 0)
        let end = DateTimeUtils.parseHHmm(rule.endTime) ?? (hour: 0, minute: 0)
        let type: RestrictionType
        switch rule.type {
        case .no_parking: type = .noParking
        case .street_cleaning: type = .streetCleaning
        case .metered: type = .metered
        case .time_limited: type = .timeLimited
        case .permit: type = .permit
        case .other: type = .other
        }
        return Item(draft: ReviewedRestriction(type: type, days: rule.daysOfWeek.isEmpty ? Array(0...6) : rule.daysOfWeek,
            start: DateTimeUtils.todayAt(hour: start.hour, minute: start.minute, calendar: spotCalendar),
            end: DateTimeUtils.todayAt(hour: end.hour, minute: end.minute, calendar: spotCalendar),
            durationMinutes: rule.durationMinutes, needsReview: rule.requiresReview,
            reviewReasons: rule.reviewReasons ?? (rule.requiresReview ? ["Confirm all conditions manually."] : [])))
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let oldIDs = scan?.restrictionsList.map(\.id) ?? []
        do {
            let created = try ScanReviewService(context: context).save(items.filter(\.include).map(\.draft),
                for: spot, scan: scan, text: ocrText, photoFilename: photoFilename, sourceUser: sourceUser,
                sourceRequiresReview: analysis.restrictions.contains(where: \.requiresReview))
            await NotificationManager.shared.cancel(forRestrictionIDs: oldIDs)
            if parkedHere && !unresolved {
                if await ParkingSessionService(context: context).park(cars.count == 1 ? cars.first : nil, at: spot) {
                    await ReminderCoordinator.shared.enable(context: context)
                }
            }
            await ReminderCoordinator.shared.reconcile(context: context)
            onFinished?(created)
            dismiss()
        } catch { saveError = error.localizedDescription }
    }
}
