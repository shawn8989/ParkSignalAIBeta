import SwiftUI
import SwiftData

struct AnalysisConfirmationView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let spot: ParkingSpot
    let sourceUser: UUID
    let ocrText: String
    let photoFilename: String?
    let analysis: AIAnalysisResponse
    var onFinished: (([Restriction]) -> Void)? = nil

    @State private var includeFlags: [Bool] = []
    @State private var cannotParkNow: Bool = false
    @State private var setAsCurrentParking: Bool = true
    @AppStorage("alertLeadMinutes") private var leadMinutes: Int = 15

    var body: some View {
        NavigationStack {
            List {
                let status = ParkingSignalEvaluator.status(for: analysis, now: Date(), leadMinutes: leadMinutes)
                HStack(spacing: 10) {
                    Image(systemName: status.iconName).foregroundStyle(status.color)
                    Text(status.label).font(.subheadline)
                    Spacer()
                }
                .padding(8)
                .background(status.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if cannotParkNow {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("You can’t park here right now based on the detected restrictions.")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                }

                Section(header: Text("Detected Restrictions")) {
                    ForEach(analysis.restrictions.indices, id: \.self) { idx in
                        let r = analysis.restrictions[idx]
                        Toggle(isOn: bindingForIncludeFlag(idx)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title(for: r.type))
                                    .font(.headline)
                                Text("\(daysDescription(r.daysOfWeek)) • \(r.startTime) - \(r.endTime)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                if let notes = r.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Toggle(isOn: $setAsCurrentParking) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Set as current parking location")
                            Text("Only schedule alerts and timers for where your car is currently parked. You can change this later by scanning at a different spot.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Confirm Restrictions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Schedule") {
                        Task { await saveAndSchedule() }
                    }
                    .disabled(!includeFlags.contains(true))
                }
            }
            .onAppear {
                includeFlags = Array(repeating: true, count: analysis.restrictions.count)
                cannotParkNow = computeCannotParkNow()
            }
            .onChange(of: analysis.restrictions.count) { newCount in
                includeFlags = Array(repeating: true, count: newCount)
            }
        }
    }
    
    private func bindingForIncludeFlag(_ idx: Int) -> Binding<Bool> {
        Binding(
            get: {
                if idx < includeFlags.count { return includeFlags[idx] }
                return true
            },
            set: { newValue in
                if idx < includeFlags.count {
                    includeFlags[idx] = newValue
                } else {
                    if includeFlags.count < idx {
                        includeFlags.append(contentsOf: Array(repeating: true, count: idx - includeFlags.count))
                    }
                    includeFlags.append(newValue)
                }
            }
        )
    }

    private func setCurrentParking(to spot: ParkingSpot) {
        do {
            // Update or insert CurrentParking
            let currentFetch = FetchDescriptor<CurrentParking>()
            let existingCurrent = try context.fetch(currentFetch)
            if let first = existingCurrent.first {
                first.spot = spot
                first.parkedAt = Date()
            } else {
                let current = CurrentParking(spot: spot, parkedAt: Date())
                context.insert(current)
            }

            // End any open ParkSession (no endedAt)
            if #available(iOS 17.0, *) {
                let openFetch = FetchDescriptor<ParkSession>(predicate: #Predicate { $0.endedAt == nil })
                let openSessions = try context.fetch(openFetch)
                for s in openSessions { s.endedAt = Date() }
            } else {
                // Fallback: fetch all and end those without endedAt
                let all = try context.fetch(FetchDescriptor<ParkSession>())
                for s in all where s.endedAt == nil { s.endedAt = Date() }
            }

            // Start a new ParkSession for this spot
            let session = ParkSession(spot: spot, startedAt: Date(), endedAt: nil)
            context.insert(session)

            try context.save()
        } catch {
            // Non-fatal: tracking failed
            print("Failed to set current parking / session: \(error)")
        }
    }

    private func saveAndSchedule() async {
        // Create Restriction models for included items
        var created: [Restriction] = []
        for (idx, r) in analysis.restrictions.enumerated() {
            guard idx < includeFlags.count, includeFlags[idx] else { continue }
            guard let mappedType = mapType(r.type) else { continue }

            var startDate: Date
            var endDate: Date
            if let dur = r.durationMinutes, dur > 0 {
                // Interpret as a time-limited parking window starting now
                startDate = Date()
                endDate = Date().addingTimeInterval(TimeInterval(dur * 60))
            } else {
                // Parse HH:mm
                guard let start = DateTimeUtils.parseHHmm(r.startTime), let end = DateTimeUtils.parseHHmm(r.endTime) else { continue }
                startDate = DateTimeUtils.todayAt(hour: start.hour, minute: start.minute)
                endDate = DateTimeUtils.todayAt(hour: end.hour, minute: end.minute)
                if endDate <= startDate {
                    endDate = endDate.addingTimeInterval(24 * 60 * 60) // overnight
                }
            }

            let restriction = Restriction(
                type: mappedType,
                startTime: startDate,
                endTime: endDate,
                daysOfWeek: r.daysOfWeek,
                sourceUser: sourceUser,
                signPhotoFilename: photoFilename,
                ocrText: ocrText,
                spot: spot
            )
            context.insert(restriction)
            spot.restrictions.append(restriction)
            created.append(restriction)
        }

        do {
            try context.save()
        } catch {
            // Best-effort; still try scheduling
        }

        if setAsCurrentParking {
            // Mark this as the current parking location
            setCurrentParking(to: spot)

            await NotificationManager.shared.schedule(for: created, spot: spot)

            // Schedule AlarmKit countdowns for duration-based restrictions (one-time timers)
            for r in created {
                if let ocr = r.ocrText, ocr.lowercased().contains("hour") || ocr.lowercased().contains("minute") {
                    let seconds = max(60.0, r.endTime.timeIntervalSince(r.startTime))
                    Task {
                        _ = await AlarmService.shared.requestAuthorization()
                        do { let _ = try await AlarmService.shared.scheduleCountdown(seconds: seconds, title: LocalizedStringResource("\(r.type.displayName)")) } catch { }
                    }
                }
            }

            onFinished?(created)
            dismiss()
        } else {
            // Do not schedule alerts or timers; just save the data
            onFinished?(created)
            dismiss()
        }
    }

    private func title(for type: AIRestrictionType) -> String {
        switch type {
        case .street_cleaning: return "Street Cleaning"
        case .no_parking: return "No Parking"
        case .metered: return "Metered"
        case .permit: return "Permit"
        case .other: return "Other"
        }
    }

    private func mapType(_ type: AIRestrictionType) -> RestrictionType? {
        switch type {
        case .street_cleaning: return .streetCleaning
        case .no_parking: return .noParking
        case .metered: return .metered
        case .permit: return .permit
        case .other: return .other
        }
    }

    private func daysDescription(_ days: [Int]) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols // Sun..Sat
        let labels = days.compactMap { (0...6).contains($0) ? symbols[$0] : nil }
        return labels.isEmpty ? "None" : labels.joined(separator: ", ")
    }

    // "Common sense" check: if now is inside a forbidden window for today for types that matter
    private func computeCannotParkNow() -> Bool {
        let now = Date()
        let cal = Calendar.current
        let weekday0_6 = (cal.component(.weekday, from: now) + 6) % 7 // 0..6

        for r in analysis.restrictions {
            guard r.type == .street_cleaning || r.type == .no_parking else { continue }
            guard r.daysOfWeek.contains(weekday0_6) else { continue }
            guard let s = DateTimeUtils.parseHHmm(r.startTime), let e = DateTimeUtils.parseHHmm(r.endTime) else { continue }
            let start = DateTimeUtils.todayAt(hour: s.hour, minute: s.minute)
            var end = DateTimeUtils.todayAt(hour: e.hour, minute: e.minute)
            if end <= start { end = end.addingTimeInterval(24*60*60) }
            if now >= start && now <= end { return true }
        }
        return false
    }
}
