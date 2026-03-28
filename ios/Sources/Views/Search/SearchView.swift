import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var appModel

    @State private var route: RouteDirection = .liangxiangToZhongguancun
    @State private var travelDate = Date()
    @State private var trips: [BusTrip] = []
    @State private var selectedTrip: BusTrip?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if trips.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "查询班车",
                        systemImage: "bus",
                        description: Text("选择线路和日期后查询可预约班车。")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(trips) { trip in
                                Button {
                                    selectedTrip = trip
                                } label: {
                                    TripCard(trip: trip)
                                }
                                .buttonStyle(.plain)
                                .disabled(trip.isRainbowBus)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("BIT 班车抢票")
            .safeAreaInset(edge: .top) {
                SearchForm(
                    route: $route,
                    travelDate: $travelDate,
                    isLoading: isLoading,
                    onSearch: search
                )
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .overlay {
                if isLoading {
                    ProgressView("正在查询班车...")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert("查询失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(item: $selectedTrip) { trip in
                SeatSelectionView(trip: trip, travelDate: travelDate)
            }
        }
    }

    private func search() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                trips = try await appModel.searchBuses(route: route, date: travelDate)
            } catch {
                errorMessage = error.localizedDescription
                trips = []
            }
            isLoading = false
        }
    }
}

private struct SearchForm: View {
    @Binding var route: RouteDirection
    @Binding var travelDate: Date
    let isLoading: Bool
    let onSearch: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Picker("线路方向", selection: $route) {
                ForEach(RouteDirection.allCases) { direction in
                    Text(direction.displayName).tag(direction)
                }
            }
            .pickerStyle(.menu)

            DatePicker("日期", selection: $travelDate, displayedComponents: .date)
                .datePickerStyle(.compact)

            Button(action: onSearch) {
                Label(isLoading ? "查询中..." : "查询班车", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
        }
    }
}

private struct TripCard: View {
    let trip: BusTrip

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(trip.originAddress) → \(trip.endAddress)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("出发 \(trip.originTime) · 到达 \(trip.endTime)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if trip.isRainbowBus {
                    Text("微信公众号预约")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.yellow.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }

            HStack {
                Label("学生票 ¥\(trip.studentTicketPrice)", systemImage: "yensign.circle")
                    .font(.footnote)
                Spacer()
                Label("最多 \(trip.reservationNumAble) 座", systemImage: "chair.lounge")
                    .font(.footnote)
            }
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
