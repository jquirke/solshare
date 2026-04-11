import Foundation

// MARK: - Auth

struct LoginResponse: Decodable {
    let accessToken: String
}

// MARK: - Properties

struct PropertiesResponse: Decodable {
    let properties: [SolProperty]
}

struct SolProperty: Decodable, Identifiable {
    let id: Int
    let meterId: Int
    let projectId: Int
    let siteId: Int
    let address1: String
    let address2: String
    let NMI: String

    var displayAddress: String {
        address2.isEmpty ? address1 : "\(address1), \(address2)"
    }
}

// MARK: - Snapshots

struct Snapshot: Decodable, Identifiable {
    let startAt: String
    let endAt: String
    let energyDemand: Double
    let solarConsumed: Double
    let solarDelivered: Double
    let solarExported: Double
    let emissionReduced: Double

    var id: String { startAt }

    /// Energy imported from the grid (demand not met by solar)
    var gridImport: Double {
        max(energyDemand - max(solarConsumed, 0), 0)
    }

    /// Fraction of demand met by solar (0–1)
    var solarPercent: Double {
        guard energyDemand > 0 else { return 0 }
        return max(solarConsumed, 0) / energyDemand
    }

    /// Parse startAt ISO-8601 string to Date
    var startDate: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: startAt)
    }
}

// MARK: - Widget Cache

struct WidgetCacheData: Codable {
    let solarUsedToday: Double
    let solarPercentToday: Double
    let lastHourSolarConsumed: Double
    let updatedAt: Date
    var dataAvailable: Bool = true
}
