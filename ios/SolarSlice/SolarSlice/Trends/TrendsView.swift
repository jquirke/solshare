import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var propertyManager: PropertyManager
    @StateObject private var viewModel = TrendsViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                periodPicker
                    .padding(.horizontal)
                    .padding(.top, 8)

                if viewModel.dataPoints.isEmpty {
                    Spacer()
                    ProgressView("Loading…")
                    Spacer()
                } else if let error = viewModel.errorMessage {
                    Spacer()
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding()
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            chartCard
                            legendRow
                        }
                        .padding()
                    }
                    .refreshable {
                        await refresh(force: true)
                    }
                }
            }
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Button {
                            Task { await refresh(force: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .task {
                await refresh(force: false)
            }
            .onChange(of: viewModel.selectedPeriod) {
                Task { await periodChanged() }
            }
        }
    }

    // MARK: - Subviews

    private var periodPicker: some View {
        Picker("Period", selection: $viewModel.selectedPeriod) {
            ForEach(TrendPeriod.allCases) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(chartTitle)
                .font(.headline)

            Chart(viewModel.dataPoints) { point in
                if point.isPlaceholder {
                    if viewModel.selectedPeriod == .day {
                        BarMark(x: .value("Period", point.date, unit: .day), y: .value("kWh", 0.5))
                            .foregroundStyle(.gray.opacity(0.25))
                    } else {
                        BarMark(x: .value("Period", point.label), y: .value("kWh", 0.5))
                            .foregroundStyle(.gray.opacity(0.25))
                    }
                } else if viewModel.selectedPeriod == .day {
                    BarMark(x: .value("Period", point.date, unit: .day), y: .value("Solar (kWh)", point.solar), stacking: .standard)
                        .foregroundStyle(.yellow)
                    BarMark(x: .value("Period", point.date, unit: .day), y: .value("Exported (kWh)", point.exported), stacking: .standard)
                        .foregroundStyle(.mint)
                    BarMark(x: .value("Period", point.date, unit: .day), y: .value("Grid (kWh)", point.grid), stacking: .standard)
                        .foregroundStyle(.blue)
                } else {
                    BarMark(x: .value("Period", point.label), y: .value("Solar (kWh)", point.solar), stacking: .standard)
                        .foregroundStyle(.yellow)
                    BarMark(x: .value("Period", point.label), y: .value("Exported (kWh)", point.exported), stacking: .standard)
                        .foregroundStyle(.mint)
                    BarMark(x: .value("Period", point.label), y: .value("Grid (kWh)", point.grid), stacking: .standard)
                        .foregroundStyle(.blue)
                }
            }
            .chartXAxis {
                if viewModel.selectedPeriod == .day {
                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                } else {
                    AxisMarks(values: .automatic(desiredCount: xAxisDesiredCount)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel()
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = value.as(Double.self) {
                            Text(String(format: "%.0f", d))
                        }
                    }
                }
            }
            .frame(height: 260)
        }
        .cardStyle()
    }

    private var legendRow: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                Circle().fill(.yellow).frame(width: 10, height: 10)
                Text("Solar Used").font(.caption)
            }
            HStack(spacing: 6) {
                Circle().fill(.mint).frame(width: 10, height: 10)
                Text("Exported").font(.caption)
            }
            HStack(spacing: 6) {
                Circle().fill(.blue).frame(width: 10, height: 10)
                Text("Grid").font(.caption)
            }
            Spacer()
            Text("kWh")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private var xAxisDesiredCount: Int {
        switch viewModel.selectedPeriod {
        case .day:   return 6
        case .week:  return 6
        case .month: return 4
        }
    }

    private var chartTitle: String {
        switch viewModel.selectedPeriod {
        case .day:   return "Last 30 Days"
        case .week:  return "Last 12 Weeks"
        case .month: return "Last 12 Months"
        }
    }

    private func refresh(force: Bool) async {
        guard let property = propertyManager.selectedProperty,
              let token = authManager.token else { return }
        await viewModel.refresh(property: property, token: token, forceRefresh: force)
    }

    private func periodChanged() async {
        guard let property = propertyManager.selectedProperty,
              let token = authManager.token else { return }
        await viewModel.periodChanged(property: property, token: token)
    }
}
