import SwiftUI
import SwiftData
import CoreLocation
import UIKit

/// Imports sample city-dataset restrictions into a spot and schedules their reminders.
enum CityRestrictionImporter {
    static func importNear(spot: ParkingSpot, context: ModelContext) async {
        let coordinate = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
        await ParkingDataProvider.shared.bootstrapIfNeeded(currentLocation: coordinate)
        let items = await ParkingDataProvider.shared.restrictionsNear(coordinate)
        guard !items.isEmpty else { return }
        await importRestrictions(items, into: spot, context: context)
    }

    static func importRestrictions(_ items: [CityRestriction], into spot: ParkingSpot, context: ModelContext) async {
        for cr in items {
            let start = DateTimeUtils.parseHHmm(cr.startTime) ?? (8, 0)
            let end = DateTimeUtils.parseHHmm(cr.endTime) ?? (10, 0)
            let startDate = DateTimeUtils.todayAt(hour: start.0, minute: start.1)
            var endDate = DateTimeUtils.todayAt(hour: end.0, minute: end.1)
            if endDate <= startDate { endDate = endDate.addingTimeInterval(24 * 60 * 60) }
            let r = Restriction(type: cr.type, startTime: startDate, endTime: endDate, daysOfWeek: cr.daysOfWeek, sourceUser: LocalIdentity.userID, signPhotoFilename: nil, ocrText: "City dataset", spot: spot)
            context.insert(r)
            spot.restrictions.append(r)
        }
        try? context.save()
        await NotificationManager.shared.schedule(for: spot.restrictions, spot: spot)
    }
}

/// The City Dataset (Sample) section of the spot screen.
struct SpotCityDataSection: View {
    @Environment(\.modelContext) private var context
    @Bindable var spot: ParkingSpot

    @State private var cityRestrictions: [CityRestriction] = []
    @State private var loadingCityData = false
    @State private var cityDataError: String? = nil
    @State private var matchedCityName: String? = nil

    var body: some View {
        cityDatasetSection()
    }

    private var spotCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
    }

    @ViewBuilder
    private func cityDatasetSection() -> some View {
        Section(header: Text("City Dataset (Sample)")) {
            if let name = matchedCityName {
                Text("Matched city: \(name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No sample dataset for this area")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button {
                Task { await fetchCityRestrictions() }
            } label: {
                Label(loadingCityData ? "Fetching…" : (cityRestrictions.isEmpty ? "Fetch Nearby Restrictions" : "Refresh Nearby Restrictions"), systemImage: "arrow.clockwise")
            }
            .disabled(loadingCityData)

            if loadingCityData {
                HStack { ProgressView(); Text("Loading nearby restrictions…") }
            }

            if let err = cityDataError {
                Text(err).foregroundColor(.red)
            }

            if !cityRestrictions.isEmpty {
                ForEach(Array(cityRestrictions.enumerated()), id: \.offset) { _, r in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.type.displayName).font(.headline)
                        Text("\(daysDescription(r.daysOfWeek)) • \(r.startTime) - \(r.endTime)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if let n = r.notes, !n.isEmpty { Text(n).font(.caption).foregroundColor(.secondary) }
                    }
                }
                Button {
                    Task { await importCityRestrictions() }
                } label: {
                    Label("Import into This Spot", systemImage: "tray.and.arrow.down")
                }
            }
        }
    }

    @MainActor
    private func fetchCityRestrictions() async {
        loadingCityData = true
        cityDataError = nil
        cityRestrictions = []
        await ParkingDataProvider.shared.bootstrapIfNeeded(currentLocation: spotCoordinate)
        matchedCityName = ParkingDataProvider.shared.matchedCity?.cityName
        let items = await ParkingDataProvider.shared.restrictionsNear(spotCoordinate)
        if items.isEmpty {
            if matchedCityName == nil {
                cityDataError = "No sample dataset available for this area. Try a spot in San Francisco or New York City."
            } else {
                cityDataError = "No sample restrictions found near this spot. Try moving closer to the city center."
            }
            let gen = UINotificationFeedbackGenerator(); gen.notificationOccurred(.warning)
        } else {
            cityRestrictions = items
            let gen = UINotificationFeedbackGenerator(); gen.notificationOccurred(.success)
        }
        loadingCityData = false
    }

    @MainActor
    private func importCityRestrictions() async {
        guard !cityRestrictions.isEmpty else { return }
        await CityRestrictionImporter.importRestrictions(cityRestrictions, into: spot, context: context)
    }

    private func daysDescription(_ days: [Int]) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols // Sun..Sat
        let labels = days.compactMap { (0...6).contains($0) ? symbols[$0] : nil }
        return labels.isEmpty ? "None" : labels.joined(separator: ", ")
    }
}
