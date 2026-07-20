import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query private var sessions: [ParkSession]

    @State private var editingSession: ParkSession?

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No parking history yet")
                            .font(.headline)
                        Text("When you assign a car to a spot, sessions appear here. You can edit or delete them.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(sessions.sorted { ($0.startedAt) > ($1.startedAt) }, id: \.id) { session in
                        Button {
                            editingSession = session
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.spot?.location ?? "(Unknown spot)")
                                    .font(.headline)
                                Text("Started: \(session.startedAt.formatted())" + (session.endedAt != nil ? " • Ended: \(session.endedAt!.formatted())" : " • Active"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                context.delete(session)
                                try? context.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Parking History")
            .sheet(item: $editingSession) { session in
                ParkSessionEditView(session: session)
            }
        }
    }
}

#Preview("HistoryView") {
    // Provide an in-memory model container for previews and avoid injecting context manually
    HistoryView()
        .modelContainer(for: [ParkingSpot.self, ParkSession.self], inMemory: true)
}
