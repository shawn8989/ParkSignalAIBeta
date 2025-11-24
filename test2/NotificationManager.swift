import Foundation
import UserNotifications
import SwiftData

final class NotificationManager {

    static let shared = NotificationManager()
    private init() {}

    // Default lead time 15 minutes; user-editable via SettingsView (@AppStorage writes to UserDefaults)
    var leadMinutes: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: "alertLeadMinutes")
            return value == 0 ? 15 : value
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "alertLeadMinutes")
        }
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func schedule(for restrictions: [Restriction], spot: ParkingSpot) async {
        let allowed: Set<RestrictionType> = [.streetCleaning, .noParking]
        let center = UNUserNotificationCenter.current()
        let ok = await requestAuthorizationIfNeeded()
        guard ok else { return }

        for r in restrictions where allowed.contains(r.type) {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: r.startTime)
            let startHour = comps.hour ?? 0
            let startMinute = comps.minute ?? 0

            for dow in r.daysOfWeek {
                let lead = computeLead(weekday0_6: dow, startHour: startHour, startMinute: startMinute, leadMinutes: leadMinutes)
                var dateComps = DateComponents()
                dateComps.weekday = lead.weekday1_7
                dateComps.hour = lead.hour
                dateComps.minute = lead.minute

                let content = UNMutableNotificationContent()
                content.title = title(for: r)
                content.body = "Starts at \(formatTime(r.startTime)) near \(spot.location)"
                content.sound = .default

                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComps, repeats: true)
                let id = "restriction.\(r.id.uuidString).\(lead.weekday1_7)"
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                do {
                    try await center.add(request)
                } catch {
                    // Best-effort; ignore individual failures
                }
            }
        }
    }

    private func title(for r: Restriction) -> String {
        switch r.type {
        case .streetCleaning: return "Street Cleaning Reminder"
        case .noParking: return "No Parking Reminder"
        default: return "Parking Reminder"
        }
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }

    // Compute pre-start alert time possibly on the previous weekday
    private func computeLead(weekday0_6: Int, startHour: Int, startMinute: Int, leadMinutes: Int) -> (weekday1_7: Int, hour: Int, minute: Int) {
        let startTotal = startHour * 60 + startMinute
        var alertTotal = startTotal - leadMinutes
        var weekday = weekday0_6
        if alertTotal < 0 {
            alertTotal += 24 * 60
            weekday = (weekday - 1 + 7) % 7
        }
        let hour = alertTotal / 60
        let minute = alertTotal % 60
        // Convert 0..6 (Sun..Sat) to 1..7 (Sun..Sat) for DateComponents.weekday
        let weekday1_7 = ((weekday + 1 - 1) % 7) + 1
        return (weekday1_7, hour, minute)
    }
}
