import SwiftUI
import SwiftData

struct ParkSessionListView: View {
    @Query(sort: \.startTime, order: .forward) private var sessions: [ParkSession]
    
    @State private var editingSession: ParkSession?
    @State private var tempStartTime = Date()
    @State private var tempEndTime = Date()
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    Text("No parking sessions found.")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(sessions, id: \.id) { session in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(session.spot?.location ?? "Unknown Spot")
                                    .font(.headline)
                                Spacer()
                                Text(durationString(from: session.startTime, to: session.endTime))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text("Start: \(formattedDate(session.startTime))")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("End: \(formattedDate(session.endTime))")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .swipeActions(allowsFullSwipe: false) {
                            Button("Edit") {
                                startEditing(session)
                            }
                            .tint(.blue)
                            Button("Delete", role: .destructive) {
                                delete(session)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Parking History")
            .sheet(item: $editingSession) { session in
                EditSessionView(session: session,
                                startTime: $tempStartTime,
                                endTime: $tempEndTime,
                                onSave: saveEdits,
                                onCancel: { editingSession = nil })
            }
        }
    }
    
    private func startEditing(_ session: ParkSession) {
        tempStartTime = session.startTime
        tempEndTime = session.endTime
        editingSession = session
    }
    
    private func saveEdits() {
        guard let session = editingSession else { return }
        modelContext.perform {
            session.startTime = tempStartTime
            session.endTime = tempEndTime
            do {
                try modelContext.save()
            } catch {
                // Handle save error if needed
            }
            DispatchQueue.main.async {
                editingSession = nil
            }
        }
    }
    
    private func delete(_ session: ParkSession) {
        modelContext.delete(session)
        do {
            try modelContext.save()
        } catch {
            // Handle delete error if needed
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func durationString(from start: Date, to end: Date) -> String {
        let interval = end.timeIntervalSince(start)
        guard interval > 0 else { return "Invalid duration" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

private struct EditSessionView: View {
    let session: ParkSession
    @Binding var startTime: Date
    @Binding var endTime: Date
    
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Start Time", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                DatePicker("End Time", selection: $endTime, in: startTime..., displayedComponents: [.date, .hourAndMinute])
            }
            .navigationTitle("Edit Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                    .disabled(endTime <= startTime)
                }
            }
        }
    }
}
