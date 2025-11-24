// Renamed file to ParkSession_removed.swift to avoid duplicate declaration issues

import Foundation

@Model final class ParkSession_removed {
  // This class has been renamed to avoid redeclaration issues.
  // It originally contained only startedAt and endedAt fields.
  var startedAt: Date
  var endedAt: Date?

  init(startedAt: Date, endedAt: Date?) {
    self.startedAt = startedAt
    self.endedAt = endedAt
  }
}
