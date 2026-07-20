import SwiftUI
import SwiftData

struct SessionsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor<ParkSession>(\.startedAt, order: .reverse)]) private var sessions: [ParkSession]
    @State private var showingNew = false
    @State private var newSession = ParkSession()

    var body: some View {
        NavigationStack {
            List {
                ForEach(sessions) { session in
                    NavigationLink(value: session) {
                        SessionRow(session: session)
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newSession = ParkSession(startedAt: Date())
                        showingNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: ParkSession.self) { session in
                ParkSessionEditView(session: session)
            }
            .sheet(isPresented: $showingNew) {
                NavigationStack {
                    ParkSessionEditView(session: newSession)
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(sessions[index]) }
        try? modelContext.save()
    }
}

private struct SessionRow: View {
    let session: ParkSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(session.startedAt, style: .date)
                Text(session.startedAt, style: .time)
                if let ended = session.endedAt {
                    Text("→")
                    Text(ended, style: .time)
                } else {
                    Text("• Active")
                        .foregroundStyle(.green)
                }
            }
            if let ended = session.endedAt {
                Text(Self.durationFormatter.string(from: ended.timeIntervalSince(session.startedAt)) ?? "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute]
        f.unitsStyle = .short
        return f
    }()
}

#Preview {
    SessionsListView()
        .modelContainer(for: [User.self, Car.self, ParkingSpot.self, Restriction.self, CurrentParking.self, ParkSession.self, SignScan.self], inMemory: true)
}
