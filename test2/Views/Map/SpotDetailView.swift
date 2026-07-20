import SwiftUI
import SwiftData

struct SpotDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var spot: ParkingSpot

    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    private var status: ParkingSignalStatus { spot.signalStatus }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: status.iconName)
                        .font(.system(size: 34))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(status.color.gradient, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(status.label)
                            .font(.headline)
                        Text(spot.location)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowSeparator(.hidden)

                parkButton
            }

            if !spot.photoFilenames.isEmpty {
                Section("Sign Photos") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(spot.photoFilenames, id: \.self) { filename in
                                if let image = ImageStore.loadImage(named: filename) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 110, height: 110)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            Section("Restrictions") {
                if spot.restrictions.isEmpty {
                    Text("No restrictions recorded.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(spot.restrictions, id: \.id) { restriction in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(restriction.type.displayName)
                                .font(.headline)
                            Text("\(restriction.daysDescription) • \(restriction.timeDescription)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let notes = restriction.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete(perform: deleteRestrictions)
                }
            }

            if !spot.scans.isEmpty {
                Section("Scans") {
                    ForEach(spot.scans.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { scan in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(scan.createdAt, format: .dateTime.day().month().year().hour().minute())
                                .font(.subheadline)
                            Text(scan.ocrText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
            }

            if !pastSessions.isEmpty {
                Section("Parking History") {
                    ForEach(pastSessions, id: \.id) { session in
                        HStack {
                            Text(session.startedAt, format: .dateTime.day().month().hour().minute())
                            Spacer()
                            Text(durationText(session.duration))
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }

            Section {
                Button("Delete Spot", role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        }
        .navigationTitle("Spot Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            SpotEditView(spot: spot)
        }
        .confirmationDialog("Delete this spot and all its data?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteSpot()
            }
        }
    }

    private var pastSessions: [ParkSession] {
        spot.parkSessions
            .filter { $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
    }

    @ViewBuilder
    private var parkButton: some View {
        if let session = spot.activeSession {
            Button {
                session.endedAt = .now
                try? context.save()
            } label: {
                Label("End Parking (\(durationText(session.duration)) so far)", systemImage: "figure.walk.departure")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        } else {
            Button {
                parkHere()
            } label: {
                Label("I Parked Here", systemImage: "car.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func parkHere() {
        // Only one active session at a time, across all spots.
        let descriptor = FetchDescriptor<ParkSession>(predicate: #Predicate { $0.endedAt == nil })
        if let active = try? context.fetch(descriptor) {
            for session in active { session.endedAt = .now }
        }
        let session = ParkSession(spot: spot)
        context.insert(session)
        spot.parkSessions.append(session)
        try? context.save()
    }

    private func deleteRestrictions(at offsets: IndexSet) {
        for index in offsets {
            context.delete(spot.restrictions[index])
        }
        try? context.save()
    }

    private func deleteSpot() {
        for filename in spot.photoFilenames {
            ImageStore.deleteImage(named: filename)
        }
        context.delete(spot)
        try? context.save()
        dismiss()
    }

    private func durationText(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let hours = minutes / 60
        if hours > 0 { return "\(hours)h \(minutes % 60)m" }
        return "\(max(minutes, 0))m"
    }
}
