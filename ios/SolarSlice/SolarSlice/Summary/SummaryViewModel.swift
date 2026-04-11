import Foundation
import Combine

enum DataState {
    case idle
    case loading
    case loaded
    case empty   // fetch succeeded but API returned no records
}

struct HourlyDataPoint: Identifiable {
    let id: String
    let label: String
    let date: Date
    let solar: Double
    let grid: Double
    let exported: Double
}

@MainActor
final class SummaryViewModel: ObservableObject {
    // MARK: - Today aggregates
    @Published private(set) var todayDemand: Double = 0
    @Published private(set) var todaySolarConsumed: Double = 0
    @Published private(set) var todaySolarDelivered: Double = 0
    @Published private(set) var todaySolarExported: Double = 0
    @Published private(set) var todayGridImport: Double = 0
    @Published private(set) var todaySolarPercent: Double = 0

    @Published private(set) var todayHourlyPoints: [HourlyDataPoint] = []

    // MARK: - Last hour
    @Published private(set) var lastHourSolarConsumed: Double = 0
    @Published private(set) var lastHourDemand: Double = 0
    @Published private(set) var lastHourGridImport: Double = 0
    @Published private(set) var lastHourSolarPercent: Double = 0

    // MARK: - State
    @Published private(set) var todayState: DataState = .idle
    @Published private(set) var lastHourState: DataState = .idle
    @Published private(set) var errorMessage: String?

    private var todayFetchedAt: Date?
    private var lastHourFetchedAt: Date?
    private let cacheTTL: TimeInterval = 300 // 5 minutes

    // MARK: - Fetch

    func refresh(property: SolProperty, token: String, forceRefresh: Bool = false) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchToday(property: property, token: token, force: forceRefresh) }
            group.addTask { await self.fetchLastHour(property: property, token: token, force: forceRefresh) }
        }
    }

    func fetchToday(property: SolProperty, token: String, force: Bool = false) async {
        if !force, let fetchedAt = todayFetchedAt,
           Date().timeIntervalSince(fetchedAt) < cacheTTL { return }

        todayState = .loading

        let (from, to) = todayRange()
        do {
            let snapshots = try await APIClient.shared.fetchSnapshots(
                propertyId: property.id, from: from, to: to, token: token
            )
            if snapshots.isEmpty {
                todayState = .empty
                writeWidgetCacheUnavailable()
            } else {
                applyTodayAggregates(snapshots)
                todayState = .loaded
                todayFetchedAt = Date()
                writeWidgetCache()
            }
        } catch let error as APIError where error == .invalidToken {
            AuthManager.shared.handleTokenExpiry()
        } catch is CancellationError {
            // pull-to-refresh dismissed early — ignore
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession cancelled — ignore
        } catch {
            todayState = .idle
            errorMessage = error.localizedDescription
        }
    }

    func fetchLastHour(property: SolProperty, token: String, force: Bool = false) async {
        if !force, let fetchedAt = lastHourFetchedAt,
           Date().timeIntervalSince(fetchedAt) < cacheTTL { return }

        lastHourState = .loading

        let (from, to) = lastHourRange()
        do {
            let snapshots = try await APIClient.shared.fetchSnapshots(
                propertyId: property.id, from: from, to: to, token: token
            )
            if snapshots.isEmpty {
                lastHourState = .empty
            } else {
                applyLastHourAggregates(snapshots)
                lastHourState = .loaded
                lastHourFetchedAt = Date()
                writeWidgetCache()
            }
        } catch let error as APIError where error == .invalidToken {
            AuthManager.shared.handleTokenExpiry()
        } catch is CancellationError {
            // pull-to-refresh dismissed early — ignore
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession cancelled — ignore
        } catch {
            lastHourState = .idle
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private helpers

    private func applyTodayAggregates(_ snapshots: [Snapshot]) {
        let demand = snapshots.map(\.energyDemand).reduce(0, +)
        let solar = snapshots.map { max($0.solarConsumed, 0) }.reduce(0, +)
        let delivered = snapshots.map { max($0.solarDelivered, 0) }.reduce(0, +)
        let exported = snapshots.map { max($0.solarExported, 0) }.reduce(0, +)

        todayDemand = demand
        todaySolarConsumed = solar
        todaySolarDelivered = delivered
        todaySolarExported = exported
        todayGridImport = max(demand - solar, 0)
        todaySolarPercent = demand > 0 ? solar / demand : 0
        todayHourlyPoints = buildHourlyPoints(snapshots)
    }

    private func buildHourlyPoints(_ snapshots: [Snapshot]) -> [HourlyDataPoint] {
        let cal = Calendar.current
        let f = DateFormatter()
        f.dateFormat = "ha"
        f.amSymbol = "am"
        f.pmSymbol = "pm"

        var dict: [Date: [Snapshot]] = [:]
        for snap in snapshots {
            guard let date = snap.startDate else { continue }
            let key = cal.dateInterval(of: .hour, for: date)?.start ?? date
            dict[key, default: []].append(snap)
        }

        return dict.map { (date, snaps) in
            let solar = snaps.map { max($0.solarConsumed, 0) }.reduce(0, +)
            let demand = snaps.map(\.energyDemand).reduce(0, +)
            let grid = max(demand - solar, 0)
            let exported = snaps.map { max($0.solarExported, 0) }.reduce(0, +)
            return HourlyDataPoint(
                id: ISO8601DateFormatter().string(from: date),
                label: f.string(from: date).lowercased(),
                date: date,
                solar: solar,
                grid: grid,
                exported: exported
            )
        }.sorted { $0.date < $1.date }
    }

    private func applyLastHourAggregates(_ snapshots: [Snapshot]) {
        let demand = snapshots.map(\.energyDemand).reduce(0, +)
        let solar = snapshots.map { max($0.solarConsumed, 0) }.reduce(0, +)

        lastHourDemand = demand
        lastHourSolarConsumed = solar
        lastHourGridImport = max(demand - solar, 0)
        lastHourSolarPercent = demand > 0 ? solar / demand : 0
    }

    private func writeWidgetCache() {
        let data = WidgetCacheData(
            solarUsedToday: todaySolarConsumed,
            solarPercentToday: todaySolarPercent,
            lastHourSolarConsumed: lastHourSolarConsumed,
            updatedAt: Date(),
            dataAvailable: true
        )
        AppGroupCache.saveWidgetData(data)
    }

    private func writeWidgetCacheUnavailable() {
        let data = WidgetCacheData(
            solarUsedToday: 0,
            solarPercentToday: 0,
            lastHourSolarConsumed: 0,
            updatedAt: Date(),
            dataAvailable: false
        )
        AppGroupCache.saveWidgetData(data)
    }

    // MARK: - Time ranges (unix seconds)

    private func todayRange() -> (Int, Int) {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        let from = Int(startOfDay.timeIntervalSince1970)
        let to = from + 86400
        return (from, to)
    }

    private func lastHourRange() -> (Int, Int) {
        let now = Date()
        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month, .day, .hour], from: now)
        let startOfHour = cal.date(from: components) ?? now
        let to = Int(startOfHour.timeIntervalSince1970)
        let from = to - 3600
        return (from, to)
    }
}
