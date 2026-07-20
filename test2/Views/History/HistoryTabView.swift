import SwiftUI
import SwiftData

struct HistoryTabView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ParkingSpot.createdAt, order: .reverse) private var spots: [ParkingSpot]

    var body: some View {
        NavigationStack {
            Group {
                if spots.isEmpty {
                    ContentUnavailableView(
                        "No scans yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Saved parking spots and their sign scans will appear here.")
                    )
                } else {
                    List {
                        ForEach(spots, id: \.id) { spot in
                            NavigationLink(value: spot) {
                                SpotRow(spot: spot)
                            }
                        }
                        .onDelete(perform: deleteSpots)
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: ParkingSpot.self) { spot in
                SpotDetailView(spot: spot)
            }
        }
    }

    private func deleteSpots(at offsets: IndexSet) {
        for index in offsets {
            let spot = spots[index]
            for filename in spot.photoFilenames {
                ImageStore.deleteImage(named: filename)
            }
            context.delete(spot)
        }
        try? context.save()
    }
}

private struct SpotRow: View {
    let spot: ParkingSpot

    var body: some View {
        let status = spot.signalStatus
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(spot.location)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 9, height: 9)
                    Text(status.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(spot.restrictions.count) restriction\(spot.restrictions.count == 1 ? "" : "s") • \(spot.createdAt, format: .relative(presentation: .named))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let filename = spot.photoFilenames.first, let image = ImageStore.loadImage(named: filename) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "parkingsign")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary)
        }
    }
}
