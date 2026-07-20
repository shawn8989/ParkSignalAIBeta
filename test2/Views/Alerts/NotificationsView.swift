import SwiftUI

@MainActor
struct NotificationsView: View {
    @ObservedObject private var store = NotificationLogStore.shared
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(store.entries.sorted(by: { $0.createdAt > $1.createdAt })) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(.headline)
                        Text(entry.body)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        HStack(spacing: 12) {
                            if let scheduled = entry.scheduledFor {
                                Text("Scheduled: \(scheduled, style: .time)")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            if let delivered = entry.deliveredAt {
                                Text("Delivered: \(delivered, style: .time)")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            if let responded = entry.respondedAt {
                                Text("Responded: \(responded, style: .time)")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Notifications")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        store.clearAll()
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }
}

