import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct SolarEntry: TimelineEntry {
    let date: Date
    let cache: WidgetCacheData?
}

// MARK: - Timeline Provider

struct SolarProvider: TimelineProvider {
    func placeholder(in context: Context) -> SolarEntry {
        SolarEntry(date: Date(), cache: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SolarEntry) -> Void) {
        let entry = SolarEntry(date: Date(), cache: AppGroupCache.loadWidgetData())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SolarEntry>) -> Void) {
        let entry = SolarEntry(date: Date(), cache: AppGroupCache.loadWidgetData())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }
}

// MARK: - Widget View

struct SolarWidgetView: View {
    let entry: SolarEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let data = entry.cache {
            if data.dataAvailable {
                if family == .systemMedium {
                    mediumView(data: data)
                } else {
                    smallView(data: data)
                }
            } else {
                unavailableView(updatedAt: data.updatedAt)
            }
        } else {
            placeholderView
        }
    }

    private func smallView(data: WidgetCacheData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text(formattedEnergy(data.solarUsedToday))
                    .font(.title2.bold())
                    .minimumScaleFactor(0.7)
                Text("solar today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label(
                    String(format: "%.0f%%", data.solarPercentToday * 100),
                    systemImage: "percent"
                )
                .font(.caption2)
                .foregroundStyle(.green)
                Spacer()
                Text(updatedText(data.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func mediumView(data: WidgetCacheData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                header
                Spacer()
                Text(updatedText(data.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Divider()
            HStack(spacing: 0) {
                metricColumn(
                    title: "Solar Today",
                    value: formattedEnergy(data.solarUsedToday),
                    icon: "sun.max.fill",
                    color: .yellow
                )
                Divider()
                metricColumn(
                    title: "Solar %",
                    value: String(format: "%.0f%%", data.solarPercentToday * 100),
                    icon: "percent",
                    color: .green
                )
                Divider()
                metricColumn(
                    title: "Last Hour",
                    value: formattedEnergy(data.lastHourSolarConsumed),
                    icon: "clock.fill",
                    color: .orange
                )
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func metricColumn(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.callout)
            Text(value)
                .font(.callout.bold())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "sun.max.fill")
                .foregroundStyle(.yellow)
                .font(.caption)
            Text("SolarSlice")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
    }

    private func unavailableView(updatedAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Data not available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(updatedText(updatedAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var placeholderView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                Text("SolarSlice")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Open app to load data")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func formattedEnergy(_ kwh: Double) -> String {
        if kwh < 0.1 {
            return String(format: "%.0f Wh", kwh * 1000)
        }
        return String(format: "%.2f kWh", kwh)
    }

    private func updatedText(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "just now" }
        let minutes = Int(elapsed / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = Int(elapsed / 3600)
        return "\(hours)h ago"
    }
}
