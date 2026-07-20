import Foundation
import SwiftUI
import UserNotifications
import Combine

struct LoggedNotification: Identifiable, Codable, Equatable {
    let id: UUID
    let requestIdentifier: String
    let createdAt: Date
    let title: String
    let body: String
    let categoryIdentifier: String?
    let scheduledFor: Date?
    let deliveredAt: Date?
    let respondedAt: Date?
    let actionIdentifier: String?
    let userInfo: [String: String]?
}

@MainActor
final class NotificationLogStore: ObservableObject {
    static let shared = NotificationLogStore()
    
    @Published private(set) var entries: [LoggedNotification] = []
    
    private let userDefaultsKey = "NotificationLog.entries"
    
    init() {
        load()
        NotificationCenter.default.addObserver(forName: Notification.Name("NotificationLog.Record"), object: nil, queue: .main) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let event = userInfo["event"] as? String else {
                return
            }
            
            switch event {
            case "delivered":
                if let unNotification = userInfo["notification"] as? UNNotification {
                    self.appendDelivered(from: unNotification)
                }
            case "responded":
                if let unResponse = userInfo["response"] as? UNNotificationResponse {
                    self.appendResponse(unResponse)
                }
            default:
                break
            }
        }
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            entries = []
            return
        }
        do {
            let decoded = try JSONDecoder().decode([LoggedNotification].self, from: data)
            entries = decoded
        } catch {
            entries = []
        }
    }
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            // silently fail saving
        }
    }
    
    private func stringStringUserInfo(from anyDict: [AnyHashable: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in anyDict {
            if let k = key as? String, let v = value as? String {
                result[k] = v
            }
        }
        return result
    }
    
    func all() -> [LoggedNotification] {
        entries
    }
    
    func appendDelivered(from notification: UNNotification) {
        let request = notification.request
        let content = request.content
        
        let logged = LoggedNotification(
            id: UUID(),
            requestIdentifier: request.identifier,
            createdAt: Date(),
            title: content.title,
            body: content.body,
            categoryIdentifier: content.categoryIdentifier.isEmpty ? nil : content.categoryIdentifier,
            scheduledFor: nil,
            deliveredAt: Date(),
            respondedAt: nil,
            actionIdentifier: nil,
            userInfo: stringStringUserInfo(from: content.userInfo)
        )
        entries.append(logged)
        save()
    }
    
    func appendResponse(_ response: UNNotificationResponse) {
        guard let index = entries.firstIndex(where: { $0.requestIdentifier == response.notification.request.identifier && $0.respondedAt == nil }) else {
            // If no matching notification found, create a new logged one with response info
            let content = response.notification.request.content
            let logged = LoggedNotification(
                id: UUID(),
                requestIdentifier: response.notification.request.identifier,
                createdAt: Date(),
                title: content.title,
                body: content.body,
                categoryIdentifier: content.categoryIdentifier.isEmpty ? nil : content.categoryIdentifier,
                scheduledFor: nil,
                deliveredAt: nil,
                respondedAt: Date(),
                actionIdentifier: response.actionIdentifier,
                userInfo: stringStringUserInfo(from: content.userInfo)
            )
            entries.append(logged)
            save()
            return
        }
        
        var existing = entries[index]
        existing = LoggedNotification(
            id: existing.id,
            requestIdentifier: existing.requestIdentifier,
            createdAt: existing.createdAt,
            title: existing.title,
            body: existing.body,
            categoryIdentifier: existing.categoryIdentifier,
            scheduledFor: existing.scheduledFor,
            deliveredAt: existing.deliveredAt,
            respondedAt: Date(),
            actionIdentifier: response.actionIdentifier,
            userInfo: existing.userInfo
        )
        entries[index] = existing
        save()
    }
    
    func appendScheduled(id: String, title: String, body: String, categoryIdentifier: String?, scheduledFor: Date?, userInfo: [String: String]?) {
        let logged = LoggedNotification(
            id: UUID(),
            requestIdentifier: id,
            createdAt: Date(),
            title: title,
            body: body,
            categoryIdentifier: categoryIdentifier,
            scheduledFor: scheduledFor,
            deliveredAt: nil,
            respondedAt: nil,
            actionIdentifier: nil,
            userInfo: userInfo
        )
        entries.append(logged)
        save()
    }
    
    func clearAll() {
        entries.removeAll()
        save()
    }
}

