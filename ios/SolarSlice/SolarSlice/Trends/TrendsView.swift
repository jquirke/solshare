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
            Text(chartTitle).font(.headline)

            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        Chart(viewModel.dataPoints) { point in
                            if point.isPlaceholder {
                                BarMark(
                                    x: .value("Period", point.date, unit: xUnit),
                                    y: .value("kWh", 0.5)
                                )
                                .foregroundStyle(.gray.opacity(0.25))
                            } else {
                                BarMark(
                                    x: .value("Period", point.date, unit: xUnit),
                                    y: .value("Solar (kWh)", point.solar),
                                    stacking: .standard
                                )
                                .foregroundStyle(.yellow)
                                BarMark(
                                    x: .value("Period", point.date, unit: xUnit),
                                    y: .value("Exported (kWh)", point.exported),
                                    stacking: .standard
                                )
                                .foregroundStyle(.mint)
                                BarMark(
                                    x: .value("Period", point.date, unit: xUnit),
                                    y: .value("Grid (kWh)", point.grid),
                                    stacking: .standard
                                )
                                .foregroundStyle(.blue)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: xAxisLabelCount)) { _ in
                                AxisGridLine()
                                AxisTick()
                                AxisValueLabel(format: xAxisFormat)
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
                        .frame(
                            width: max(geo.size.width, CGFloat(viewModel.dataPoints.count) * pointWidth),
                            height: 240
                        )
                        .id("chart")
                    }
                    .onAppear {
                        proxy.scrollTo("chart", anchor: .trailing)
                    }
                    .onChange(of: viewModel.dataPoints.count) {
                        proxy.scrollTo("chart", anchor: .trailing)
                    }
                }
            }
            .frame(height: 240)
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

    private var xUnit: Calendar.Component {
        switch viewModel.selectedPeriod {
        case .day:   return .day
        case .week:  return .weekOfYear
        case .month: return .month
        }
    }

    private var xAxisFormat: Date.FormatStyle {
        switch viewModel.selectedPeriod {
        case .day:   return .dateTime.day().month(.abbreviated)
        case .week:  return .dateTime.day().month(.abbreviated)
        case .month: return .dateTime.month(.abbreviated).year(.twoDigits)
        }
    }

    // Desired number of axis labels within the scrollable width.
    private var xAxisLabelCount: Int {
        switch viewModel.selectedPeriod {
        case .day:   return 8
        case .week:  return 6
        case .month: return 4
        }
    }

    // Minimum pixels per data point — sets scroll width when data exceeds screen.
    private var pointWidth: CGFloat {
        switch viewModel.selectedPeriod {
        case .day:   return 16   // 31 days × 16 = 496pt → scrolls on iPhone
        case .week:  return 24   // 13 weeks × 24 = 312pt → fits most screens
        case .month: return 26   // 13 months × 26 = 338pt → fits most screens
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
