import Foundation
import Combine

// MARK: - Period

enum TrendPeriod: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }
}

// MARK: - Bucketed Data Point

struct TrendDataPoint: Identifiable {
    let id: String
    let label: String
    let date: Date
    let solar: Double
    let grid: Double
    let exported: Double
    var isPlaceholder: Bool = false
}

// MARK: - TrendsViewModel

@MainActor
final class TrendsViewModel: ObservableObject {
    @Published var selectedPeriod: TrendPeriod = .day
    @Published private(set) var dataPoints: [TrendDataPoint] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var cache: [TrendPeriod: (points: [TrendDataPoint], fetchedAt: Date)] = [:]
    private let cacheTTL: TimeInterval = 300

    // MARK: - Fetch

    func refresh(property: SolProperty, token: String, forceRefresh: Bool = false) async {
        let period = selectedPeriod

        if !forceRefresh,
           let cached = cache[period],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            dataPoints = cached.points
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let (from, to) = dateRange(for: period)
        do {
            let snapshots = try await APIClient.shared.fetchSnapshots(
                propertyId: property.id,
                from: Int(from.timeIntervalSince1970),
                to: Int(to.timeIntervalSince1970),
                token: token
            )
            let points = bucket(snapshots: snapshots, period: period)
            cache[period] = (points, Date())
            dataPoints = points
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

    func periodChanged(property: SolProperty, token: String) async {
        let period = selectedPeriod
        if let cached = cache[period],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            dataPoints = cached.points
            return
        }
        // Clear stale data from the previous period so the loading spinner
        // shows instead of the wrong chart while the new fetch is in flight.
        dataPoints = []
        await refresh(property: property, token: token, forceRefresh: false)
    }

    // MARK: - Bucketing

    private func bucket(snapshots: [Snapshot], period: TrendPeriod) -> [TrendDataPoint] {
        let cal = Calendar.current
        var dict: [Date: [Snapshot]] = [:]

        for snapshot in snapshots {
            guard let date = snapshot.startDate else { continue }
            let key = bucketDate(date, period: period, cal: cal)
            dict[key, default: []].append(snapshot)
        }

        let sorted = dict.map { (date, snaps) in
            let solar = snaps.map { max($0.solarConsumed, 0) }.reduce(0, +)
            let demand = snaps.map(\.energyDemand).reduce(0, +)
            let grid = max(demand - solar, 0)
            let exported = snaps.map { max($0.solarExported, 0) }.reduce(0, +)
            return TrendDataPoint(
                id: ISO8601DateFormatter().string(from: date),
                label: label(for: date, period: period),
                date: date,
                solar: solar,
                grid: grid,
                exported: exported
            )
        }.sorted { $0.date < $1.date }

        // Strip trailing all-zero points (no data yet), then re-add the current
        // period bucket as a placeholder so the chart always shows where "now" is.
        var result = sorted
        while let last = result.last, last.solar == 0 && last.grid == 0 && last.exported == 0 {
            result.removeLast()
        }

        let now = Date()
        let currentBucket = bucketDate(now, period: period, cal: cal)
        let alreadyPresent = result.contains { $0.date == currentBucket }
        if !alreadyPresent {
            result.append(TrendDataPoint(
                id: "placeholder-\(ISO8601DateFormatter().string(from: currentBucket))",
                label: label(for: currentBucket, period: period),
                date: currentBucket,
                solar: 0, grid: 0, exported: 0,
                isPlaceholder: true
            ))
        }
        return result
    }

    private func bucketDate(_ date: Date, period: TrendPeriod, cal: Calendar) -> Date {
        switch period {
        case .day:
            return cal.startOfDay(for: date)
        case .week:
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return cal.date(from: comps) ?? date
        case .month:
            let comps = cal.dateComponents([.year, .month], from: date)
            return cal.date(from: comps) ?? date
        }
    }

    private func label(for date: Date, period: TrendPeriod) -> String {
        let f = DateFormatter()
        switch period {
        case .day:   f.dateFormat = "d MMM"
        case .week:  f.dateFormat = "d MMM"   // "14 Apr" — avoids clipping W-numbers
        case .month: f.dateFormat = "MMM yy"  // label used for placeholder id only
        }
        return f.string(from: date)
    }

    // MARK: - Date ranges

    private func dateRange(for period: TrendPeriod) -> (Date, Date) {
        let now = Date()
        let cal = Calendar.current
        let to = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now) ?? now)

        switch period {
        case .day:
            let from = cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: now)) ?? now
            return (from, to)
        case .week:
            let from = cal.date(byAdding: .weekOfYear, value: -12, to: now) ?? now
            return (from, to)
        case .month:
            let from = cal.date(byAdding: .month, value: -12, to: now) ?? now
            return (from, to)
        }
    }
}
