import SwiftUI
import Charts

struct SummaryView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var propertyManager: PropertyManager
    @StateObject private var viewModel = SummaryViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.todayState == .loading && viewModel.lastHourState == .loading {
                    ProgressView("Loading…")
                        .padding(.top, 60)
                } else {
                    ScrollView {
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
                            switch viewModel.lastHourState {
                            case .loading:
                                ProgressView().padding()
                            case .empty:
                                dataUnavailableNote.padding(.horizontal)
                            case .loaded:
                                lastHourGrid.padding(.horizontal)
                            case .idle:
                                EmptyView()
                            }

                            SectionHeader(title: "Today")
                            switch viewModel.todayState {
                            case .loading:
                                ProgressView().padding()
                            case .empty:
                                dataUnavailableNote.padding(.horizontal)
                            case .loaded:
                                todayGrid.padding(.horizontal)
                                if !viewModel.todayHourlyPoints.isEmpty {
                                    SectionHeader(title: "Today by Hour")
                                    todayHourlyChart.padding(.horizontal)
                                }
                            case .idle:
                                EmptyView()
                            }
                        }
                    }
                    .refreshable {
                        await refresh(force: true)
                    }
                }
            }
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.todayState == .loading || viewModel.lastHourState == .loading {
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
        }
    }

    // MARK: - Data unavailable

    private var dataUnavailableNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Data not available")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
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

    private var todayHourlyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
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
                            AxisMarks { _ in
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
                        .frame(
                            width: max(geo.size.width, CGFloat(viewModel.todayHourlyPoints.count) * 28),
                            height: 200
                        )
                        .id("hourlyChart")
                    }
                    .onAppear {
                        proxy.scrollTo("hourlyChart", anchor: .trailing)
                    }
                    .onChange(of: viewModel.todayHourlyPoints.count) {
                        proxy.scrollTo("hourlyChart", anchor: .trailing)
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
