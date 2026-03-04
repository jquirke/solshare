import Foundation
import Combine

struct FiveMinDataPoint: Identifiable {
    let id: String
    let date: Date
    let label: String
    let solar: Double
    let grid: Double
    let exported: Double
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
    @Published private(set) var fiveMinPoints: [FiveMinDataPoint] = []

    private var fiveMinCache: [Date: FiveMinDataPoint] = [:]
    private var fiveMinFetchedUpTo: Date?

    // MARK: - Last hour
    @Published private(set) var lastHourSolarConsumed: Double = 0
    @Published private(set) var lastHourDemand: Double = 0
    @Published private(set) var lastHourGridImport: Double = 0
    @Published private(set) var lastHourSolarPercent: Double = 0

    // MARK: - State
    @Published private(set) var isLoadingToday = false
    @Published private(set) var isLoadingLastHour = false
    @Published private(set) var errorMessage: String?

    private var todayFetchedAt: Date?
    private var lastHourFetchedAt: Date?
    private let cacheTTL: TimeInterval = 300 // 5 minutes

    // MARK: - Fetch

    func refresh(property: SolProperty, token: String, forceRefresh: Bool = false) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchToday(property: property, token: token, force: forceRefresh) }
            group.addTask { await self.fetchLastHour(property: property, token: token, force: forceRefresh) }
            group.addTask { await self.fetchFiveMin(property: property, token: token, force: forceRefresh) }
        }
    }

    func fetchToday(property: SolProperty, token: String, force: Bool = false) async {
        if !force, let fetchedAt = todayFetchedAt,
           Date().timeIntervalSince(fetchedAt) < cacheTTL { return }

        isLoadingToday = true
        defer { isLoadingToday = false }

        let (from, to) = todayRange()
        do {
            let snapshots = try await APIClient.shared.fetchSnapshots(
                propertyId: property.id, from: from, to: to, token: token
            )
            applyTodayAggregates(snapshots)
            todayFetchedAt = Date()
            writeWidgetCache()
        } catch let error as APIError where error == .invalidToken {
            AuthManager.shared.handleTokenExpiry()
        } catch is CancellationError {
            // pull-to-refresh dismissed early — ignore
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession cancelled — ignore
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchLastHour(property: SolProperty, token: String, force: Bool = false) async {
        if !force, let fetchedAt = lastHourFetchedAt,
           Date().timeIntervalSince(fetchedAt) < cacheTTL { return }

        isLoadingLastHour = true
        defer { isLoadingLastHour = false }

        let (from, to) = lastHourRange()
        do {
            let snapshots = try await APIClient.shared.fetchSnapshots(
                propertyId: property.id, from: from, to: to, token: token
            )
            applyLastHourAggregates(snapshots)
            lastHourFetchedAt = Date()
            writeWidgetCache()
        } catch let error as APIError where error == .invalidToken {
            AuthManager.shared.handleTokenExpiry()
        } catch is CancellationError {
            // pull-to-refresh dismissed early — ignore
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession cancelled — ignore
        } catch {
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
            updatedAt: Date()
        )
        AppGroupCache.saveWidgetData(data)
    }

    func fetchFiveMin(property: SolProperty, token: String, force: Bool = false) async {
        let cal = Calendar.current
        let now = Date()

        // Round down to nearest closed 5-min bucket (subtract 1 min for ingestion lag)
        let minuteFloor = (cal.component(.minute, from: now) / 5) * 5
        var comps = cal.dateComponents([.year, .month, .day, .hour], from: now)
        comps.minute = minuteFloor
        let currentBucket = cal.date(from: comps) ?? now

        // On force refresh clear cache and fetch last 2 hours; otherwise fetch delta
        let fetchFrom: Date
        if force || fiveMinFetchedUpTo == nil {
            fiveMinCache = [:]
            fiveMinFetchedUpTo = nil
            let twoHoursAgo = now.addingTimeInterval(-7200)
            fetchFrom = max(twoHoursAgo, cal.startOfDay(for: now))
        } else {
            fetchFrom = fiveMinFetchedUpTo!
        }

        guard fetchFrom < currentBucket else { return }

        // Build list of 5-min windows to fetch
        var windows: [(Date, Date)] = []
        var t = fetchFrom
        while t < currentBucket {
            windows.append((t, t.addingTimeInterval(300)))
            t = t.addingTimeInterval(300)
        }

        let f = DateFormatter()
        f.dateFormat = "HH:mm"

        for (from, to) in windows {
            if Task.isCancelled { break }
            do {
                let snaps = try await APIClient.shared.fetchSnapshots(
                    propertyId: property.id,
                    from: Int(from.timeIntervalSince1970),
                    to: Int(to.timeIntervalSince1970),
                    token: token
                )
                for snap in snaps {
                    guard let date = snap.startDate else { continue }
                    let solar = max(snap.solarConsumed, 0)
                    let grid = max(snap.energyDemand - solar, 0)
                    let exported = max(snap.solarExported, 0)
                    fiveMinCache[date] = FiveMinDataPoint(
                        id: snap.startAt,
                        date: date,
                        label: f.string(from: date),
                        solar: solar,
                        grid: grid,
                        exported: exported
                    )
                }
            } catch is CancellationError { break }
            catch let urlError as URLError where urlError.code == .cancelled { break }
            catch { /* skip individual bucket errors */ }
        }

        fiveMinFetchedUpTo = currentBucket
        fiveMinPoints = fiveMinCache.values.sorted { $0.date < $1.date }
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
