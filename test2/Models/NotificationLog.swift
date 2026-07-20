import Foundation
import SwiftData

@Model
final class NotificationLogEntry {
    @Attribute(.unique) var id: UUID
    var requestIdentifier: String
    var createdAt: Date
    var title: String
    var body: String
    var categoryIdentifier: String?
    var scheduledFor: Date?
    var deliveredAt: Date?
    var respondedAt: Date?
    var actionIdentifier: String?
    var userInfoData: Data?
    
    var userInfo: [String: String]? {
        get {
            guard let data = userInfoData else { return nil }
            return try? JSONDecoder().decode([String: String].self, from: data)
        }
        set {
            if let newValue = newValue {
                userInfoData = try? JSONEncoder().encode(newValue)
            } else {
                userInfoData = nil
            }
        }
    }
    
    init(
        id: UUID = UUID(),
        requestIdentifier: String,
        createdAt: Date = Date(),
        title: String,
        body: String,
        categoryIdentifier: String? = nil,
        scheduledFor: Date? = nil,
        deliveredAt: Date? = nil,
        respondedAt: Date? = nil,
        actionIdentifier: String? = nil,
        userInfo: [String: String]? = nil
    ) {
        self.id = id
        self.requestIdentifier = requestIdentifier
        self.createdAt = createdAt
        self.title = title
        self.body = body
        self.categoryIdentifier = categoryIdentifier
        self.scheduledFor = scheduledFor
        self.deliveredAt = deliveredAt
        self.respondedAt = respondedAt
        self.actionIdentifier = actionIdentifier
        self.userInfo = userInfo
    }
    
    convenience init(
        requestIdentifier: String,
        title: String,
        body: String,
        categoryIdentifier: String? = nil,
        userInfo: [String: String]? = nil
    ) {
        self.init(
            requestIdentifier: requestIdentifier,
            createdAt: Date(),
            title: title,
            body: body,
            categoryIdentifier: categoryIdentifier,
            userInfo: userInfo
        )
    }
    
    convenience init(
        requestIdentifier: String,
        title: String,
        body: String,
        categoryIdentifier: String? = nil,
        scheduledFor: Date? = nil,
        userInfo: [String: String]? = nil
    ) {
        self.init(
            requestIdentifier: requestIdentifier,
            createdAt: Date(),
            title: title,
            body: body,
            categoryIdentifier: categoryIdentifier,
            scheduledFor: scheduledFor,
            userInfo: userInfo
        )
    }
}
