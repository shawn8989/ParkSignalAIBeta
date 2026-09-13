import SwiftUI
import SwiftData

/// Confirm (and CORRECT) the parsed restrictions before they are saved and
/// alarms are scheduled. Each row is editable — type, days, and times — so a
/// wrong on-device/AI interpretation can be fixed here instead of scheduling a
/// bad alarm. Low-confidence parses are flagged for the user to double-check.
struct AnalysisConfirmationView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let spot: ParkingSpot
    let sourceUser: UUID
    let ocrText: String
    let photoFilename: String?
    let analysis: AIAnalysisResponse
    var onFinished: (([Restriction]) -> Void)? = nil

    @State private var items: [EditableRestriction] = []
    @State private var setAsCurrentParking: Bool = true
    @State private var saveError: String?
    @AppStorage("alertLeadMinutes") private var leadMinutes: Int = 15

    private struct EditableRestriction: Identifiable {
        let id = UUID()
        var include: Bool
        var type: RestrictionType
        var days: Set<Int>
        var startTime: Date
        var endTime: Date
        var durationMinutes: Int?
        var notes: String?
        var needsReview: Bool
    }

    var body: some View {
        NavigationStack {
            List {
                statusBanner

                if items.contains(where: { $0.include && $0.needsReview }) {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text("Some detections may be off — please double-check the days and times below before saving.")
                            .font(.subheadline)
                    }
                }

                Section {
                    ForEach($items) { $item in
                        editableRow($item)
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                } header: {
                    Text("Detected Restrictions")
                } footer: {
                    Text("Tap a field to correct anything the scan got wrong before saving.")
                }

                Section {
                    Toggle(isOn: $setAsCurrentParking) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Set as current parking location")
                            Text("Only schedule alerts for where your car is currently parked. You can change this later by scanning at a different spot.")
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
                    Button("Save & Schedule") { Task { await saveAndSchedule() } }
                        .disabled(!items.contains { $0.include })
                }
            }
            .onAppear {
                if items.isEmpty {
                    items = analysis.restrictions.map(editable(from:))
                }
            }
            .alert("Couldn't Save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func editableRow(_ item: Binding<EditableRestriction>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("Include", isOn: item.include).labelsHidden()
                Picker("Type", selection: item.type) {
                    ForEach(RestrictionType.allCases, id: \.self) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
                if item.wrappedValue.needsReview {
                    Label("Check", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            if item.wrappedValue.include {
                if item.wrappedValue.durationMinutes == nil {
                    dayChips(item.days)
                    HStack(spacing: 8) {
                        DatePicker("Start", selection: item.startTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Text("–").foregroundStyle(.secondary)
                        DatePicker("End", selection: item.endTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Spacer()
                    }
                } else {
                    Text("Time limit: \(item.wrappedValue.durationMinutes ?? 0) min from arrival")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let notes = item.wrappedValue.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func dayChips(_ days: Binding<Set<Int>>) -> some View {
        let symbols = ["S", "M", "T", "W", "T", "F", "S"]
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { d in
                let on = days.wrappedValue.contains(d)
                Button {
                    if on { days.wrappedValue.remove(d) } else { days.wrappedValue.insert(d) }
                } label: {
                    Text(symbols[d])
                        .font(.caption.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .background(on ? Color.accentColor : Color.gray.opacity(0.15))
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[d])
                .accessibilityValue(on ? "selected" : "not selected")
            }
        }
    }

    private var statusBanner: some View {
        let status = ParkingSignalEvaluator.status(for: analysis, now: Date(), leadMinutes: leadMinutes)
        return HStack(spacing: 10) {
            Image(systemName: status.iconName).foregroundStyle(status.color)
                .accessibilityHidden(true)
            Text(status.label).font(.subheadline)
            Spacer()
        }
        .padding(8)
        .background(status.color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Build editable state

    private func editable(from r: AIRestriction) -> EditableRestriction {
        let type = mapType(r.type) ?? .other
        let days = Set(r.daysOfWeek.filter { (0...6).contains($0) })
        let start: Date
        let end: Date
        let dur: Int?
        if let d = r.durationMinutes, d > 0 {
            dur = d
            start = Date()
            end = Date().addingTimeInterval(TimeInterval(d * 60))
        } else {
            dur = nil
            let s = DateTimeUtils.parseHHmm(r.startTime) ?? (hour: 8, minute: 0)
            let e = DateTimeUtils.parseHHmm(r.endTime) ?? (hour: 9, minute: 0)
            let sDate = DateTimeUtils.todayAt(hour: s.hour, minute: s.minute)
            var eDate = DateTimeUtils.todayAt(hour: e.hour, minute: e.minute)
            if eDate <= sDate { eDate = eDate.addingTimeInterval(24 * 60 * 60) }
            start = sDate
            end = eDate
        }
        return EditableRestriction(include: true, type: type, days: days,
                                   startTime: start, endTime: end,
                                   durationMinutes: dur, notes: r.notes,
                                   needsReview: r.needsReview ?? false)
    }

    // MARK: - Save

    private func saveAndSchedule() async {
        var created: [Restriction] = []
        for item in items where item.include {
            let restriction = Restriction(
                type: item.type,
                startTime: item.startTime,
                endTime: item.endTime,
                daysOfWeek: Array(item.days).sorted(),
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
            saveError = "Couldn't save these restrictions: \(error.localizedDescription)"
            return
        }

        if setAsCurrentParking {
            setCurrentParking(to: spot)
            await NotificationManager.shared.schedule(for: created, spot: spot)
            for (item, r) in zip(items.filter { $0.include }, created) where item.durationMinutes != nil {
                let seconds = max(60.0, TimeInterval((item.durationMinutes ?? 0) * 60))
                Task {
                    _ = await AlarmService.shared.requestAuthorization()
                    do { _ = try await AlarmService.shared.scheduleCountdown(seconds: seconds, title: LocalizedStringResource("\(r.type.displayName)")) } catch {}
                }
            }
        }
        onFinished?(created)
        dismiss()
    }

    private func setCurrentParking(to spot: ParkingSpot) {
        do {
            let existingCurrent = try context.fetch(FetchDescriptor<CurrentParking>())
            if let first = existingCurrent.first {
                first.spotID = spot.id
                first.parkedAt = Date()
            } else {
                context.insert(CurrentParking(spotID: spot.id, parkedAt: Date()))
            }
            if #available(iOS 17.0, *) {
                let openFetch = FetchDescriptor<ParkSession>(predicate: #Predicate { $0.endedAt == nil })
                for s in try context.fetch(openFetch) { s.endedAt = Date() }
            } else {
                for s in try context.fetch(FetchDescriptor<ParkSession>()) where s.endedAt == nil { s.endedAt = Date() }
            }
            context.insert(ParkSession(spot: spot, startedAt: Date(), endedAt: nil))
            try context.save()
        } catch {
            // Non-fatal: tracking failed
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
}
