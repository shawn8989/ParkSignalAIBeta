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
    var onFinished: (() -> Void)? = nil

    @State private var includeFlags: [Bool] = []
    @State private var cannotParkNow: Bool = false

    var body: some View {
        NavigationStack {
            List {
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
                        Toggle(isOn: $includeFlags[idx]) {
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
        }
    }

    private func saveAndSchedule() async {
        // Create Restriction models for included items
        var created: [Restriction] = []
        for (idx, include) in includeFlags.enumerated() where include {
            let r = analysis.restrictions[idx]
            guard let mappedType = mapType(r.type) else { continue }

            // Parse HH:mm
            guard let start = parseHHmm(r.startTime), let end = parseHHmm(r.endTime) else { continue }
            let startDate = todayAt(hour: start.hour, minute: start.minute)
            var endDate = todayAt(hour: end.hour, minute: end.minute)
            if endDate <= startDate {
                endDate = endDate.addingTimeInterval(24 * 60 * 60) // overnight
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

        await NotificationManager.shared.schedule(for: created, spot: spot)
        onFinished?()
        dismiss()
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

    private func parseHHmm(_ s: String) -> (hour: Int, minute: Int)? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m) else {
            return nil
        }
        return (h, m)
    }

    private func todayAt(hour: Int, minute: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    // "Common sense" check: if now is inside a forbidden window for today for types that matter
    private func computeCannotParkNow() -> Bool {
        let now = Date()
        let cal = Calendar.current
        let weekday0_6 = (cal.component(.weekday, from: now) + 6) % 7 // 0..6

        for r in analysis.restrictions {
            guard r.type == .street_cleaning || r.type == .no_parking else { continue }
            guard r.daysOfWeek.contains(weekday0_6) else { continue }
            guard let s = parseHHmm(r.startTime), let e = parseHHmm(r.endTime) else { continue }
            let start = todayAt(hour: s.hour, minute: s.minute)
            var end = todayAt(hour: e.hour, minute: e.minute)
            if end <= start { end = end.addingTimeInterval(24*60*60) }
            if now >= start && now <= end { return true }
        }
        return false
    }
}
