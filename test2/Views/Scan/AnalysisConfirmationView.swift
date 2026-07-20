import SwiftUI
import SwiftData

/// Final step of the scan flow: review the detected restrictions, then save them
/// as a new ParkingSpot (with its SignScan record) and schedule reminders.
struct AnalysisConfirmationView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let ocrText: String
    let photoFilename: String?
    let analysis: AIAnalysisResponse
    let latitude: Double
    let longitude: Double
    let address: String
    var onFinished: (() -> Void)? = nil

    @State private var includeFlags: [Bool] = []
    @State private var locationLabel: String = ""
    @State private var saveError: String?

    private var cannotParkNow: Bool {
        ParkingSignalEvaluator.status(for: analysis) == .red
    }

    var body: some View {
        NavigationStack {
            List {
                if cannotParkNow {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("You can’t park here right now based on the detected restrictions.")
                            .font(.subheadline)
                    }
                }

                Section(header: Text("Location")) {
                    TextField("Location label", text: $locationLabel)
                        .textInputAutocapitalization(.words)
                }

                Section(header: Text("Detected Restrictions")) {
                    ForEach(analysis.restrictions.indices, id: \.self) { idx in
                        let r = analysis.restrictions[idx]
                        Toggle(isOn: binding(for: idx)) {
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

                if let saveError {
                    Section {
                        Text(saveError)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Confirm & Save")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Remind") {
                        Task { await saveAndSchedule() }
                    }
                    .disabled(!includeFlags.contains(true))
                }
            }
            .onAppear {
                if includeFlags.count != analysis.restrictions.count {
                    includeFlags = Array(repeating: true, count: analysis.restrictions.count)
                }
                if locationLabel.isEmpty {
                    locationLabel = address.isEmpty
                        ? String(format: "%.5f, %.5f", latitude, longitude)
                        : address
                }
            }
        }
    }

    private func binding(for idx: Int) -> Binding<Bool> {
        Binding(
            get: { includeFlags.indices.contains(idx) ? includeFlags[idx] : true },
            set: { if includeFlags.indices.contains(idx) { includeFlags[idx] = $0 } }
        )
    }

    private func saveAndSchedule() async {
        let spot = ParkingSpot(
            location: locationLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: latitude,
            longitude: longitude
        )
        context.insert(spot)

        var created: [Restriction] = []
        for (idx, include) in includeFlags.enumerated() where include {
            let r = analysis.restrictions[idx]
            guard let mappedType = mapType(r.type) else { continue }
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
                notes: r.notes,
                ocrText: ocrText,
                signPhotoFilename: photoFilename,
                spot: spot
            )
            context.insert(restriction)
            spot.restrictions.append(restriction)
            created.append(restriction)
        }

        let scan = SignScan(
            latitude: latitude,
            longitude: longitude,
            ocrText: ocrText,
            photoFilename: photoFilename,
            address: address.isEmpty ? nil : address,
            spot: spot
        )
        context.insert(scan)
        spot.scans.append(scan)

        do {
            try context.save()
        } catch {
            saveError = "Couldn't save: \(error.localizedDescription)"
            return
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
        return labels.isEmpty ? "Every day" : labels.joined(separator: ", ")
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
}
