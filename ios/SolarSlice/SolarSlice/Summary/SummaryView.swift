import SwiftUI
import Charts

struct SummaryView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var propertyManager: PropertyManager
    @StateObject private var viewModel = SummaryViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoadingToday && viewModel.todayDemand == 0 {
                    ProgressView("Loading…")
                        .padding(.top, 60)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        if let address = propertyManager.selectedProperty?.displayAddress {
                            Text(address)
                                .font(.headline)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                        }
                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal)
                                .padding(.top, 8)
                        }

                        SectionHeader(title: "Last Hour")
                        lastHourGrid
                            .padding(.horizontal)

                        SectionHeader(title: "Today")
                        todayGrid
                            .padding(.horizontal)

                        if !viewModel.todayHourlyPoints.isEmpty {
                            SectionHeader(title: "Today by Hour")
                            todayHourlyChart
                                .padding(.horizontal)
                        }

                        if !viewModel.fiveMinPoints.isEmpty {
                            SectionHeader(title: "Recent (5 min)")
                            fiveMinChart
                                .padding(.horizontal)
                                .padding(.bottom, 16)
                        }
                    }
                }
            }
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isLoadingToday || viewModel.isLoadingLastHour {
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
            .refreshable {
                await refresh(force: true)
            }
            .task {
                await refresh(force: false)
            }
        }
    }

    // MARK: - Grids

    private var lastHourGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(
                title: "Solar Used",
                value: Formatters.energy(viewModel.lastHourSolarConsumed),
                unit: "",
                iconName: "sun.max.fill",
                iconColor: .yellow
            )
            MetricCard(
                title: "Solar %",
                value: Formatters.percent(viewModel.lastHourSolarPercent),
                unit: "",
                iconName: "percent",
                iconColor: .green
            )
            MetricCard(
                title: "Total Demand",
                value: Formatters.energy(viewModel.lastHourDemand),
                unit: "",
                iconName: "bolt.fill",
                iconColor: .blue
            )
            MetricCard(
                title: "Grid Import",
                value: Formatters.energy(viewModel.lastHourGridImport),
                unit: "",
                iconName: "powerplug.fill",
                iconColor: .orange
            )
        }
        .padding(.vertical, 8)
    }

    private var todayGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(
                title: "Solar Used",
                value: Formatters.energy(viewModel.todaySolarConsumed),
                unit: "",
                iconName: "sun.max.fill",
                iconColor: .yellow
            )
            MetricCard(
                title: "Solar %",
                value: Formatters.percent(viewModel.todaySolarPercent),
                unit: "",
                iconName: "percent",
                iconColor: .green
            )
            MetricCard(
                title: "Total Demand",
                value: Formatters.energy(viewModel.todayDemand),
                unit: "",
                iconName: "bolt.fill",
                iconColor: .blue
            )
            MetricCard(
                title: "Grid Import",
                value: Formatters.energy(viewModel.todayGridImport),
                unit: "",
                iconName: "powerplug.fill",
                iconColor: .orange
            )
            MetricCard(
                title: "Solar Delivered",
                value: Formatters.energy(viewModel.todaySolarDelivered),
                unit: "",
                iconName: "arrow.down.circle.fill",
                iconColor: .yellow
            )
            MetricCard(
                title: "Solar Exported",
                value: Formatters.energy(viewModel.todaySolarExported),
                unit: "",
                iconName: "arrow.up.circle.fill",
                iconColor: .mint
            )
        }
        .padding(.vertical, 8)
    }

    private var fiveMinChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(viewModel.fiveMinPoints) { point in
                BarMark(
                    x: .value("Time", point.label),
                    y: .value("Solar (kWh)", point.solar),
                    stacking: .standard
                )
                .foregroundStyle(.yellow)

                BarMark(
                    x: .value("Time", point.label),
                    y: .value("Exported (kWh)", point.exported),
                    stacking: .standard
                )
                .foregroundStyle(.mint)

                BarMark(
                    x: .value("Time", point.label),
                    y: .value("Grid (kWh)", point.grid),
                    stacking: .standard
                )
                .foregroundStyle(.blue)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = value.as(Double.self) {
                            Text(String(format: "%.2f", d))
                        }
                    }
                }
            }
            .frame(height: 160)

            HStack(spacing: 20) {
                HStack(spacing: 6) {
                    Circle().fill(.yellow).frame(width: 10, height: 10)
                    Text("Solar").font(.caption)
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
                Text("kWh").font(.caption).foregroundStyle(.secondary)
            }
        }
        .cardStyle()
        .padding(.bottom, 16)
    }

    private var todayHourlyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(viewModel.todayHourlyPoints) { point in
                BarMark(
                    x: .value("Hour", point.label),
                    y: .value("Solar (kWh)", point.solar),
                    stacking: .standard
                )
                .foregroundStyle(.yellow)

                BarMark(
                    x: .value("Hour", point.label),
                    y: .value("Exported (kWh)", point.exported),
                    stacking: .standard
                )
                .foregroundStyle(.mint)

                BarMark(
                    x: .value("Hour", point.label),
                    y: .value("Grid (kWh)", point.grid),
                    stacking: .standard
                )
                .foregroundStyle(.blue)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 8)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = value.as(Double.self) {
                            Text(String(format: "%.2f", d))
                        }
                    }
                }
            }
            .frame(height: 200)

            HStack(spacing: 20) {
                HStack(spacing: 6) {
                    Circle().fill(.yellow).frame(width: 10, height: 10)
                    Text("Solar").font(.caption)
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
                Text("kWh").font(.caption).foregroundStyle(.secondary)
            }
        }
        .cardStyle()
        .padding(.bottom, 16)
    }

    // MARK: - Helpers

    private func refresh(force: Bool) async {
        guard let property = propertyManager.selectedProperty,
              let token = authManager.token else { return }
        await viewModel.refresh(property: property, token: token, forceRefresh: force)
    }
}
