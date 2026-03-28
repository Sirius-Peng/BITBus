import SwiftUI

struct SeatSelectionView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let trip: BusTrip
    let travelDate: Date

    @State private var seatMap: SeatMap?
    @State private var selectedSeats: Set<Int> = []
    @State private var autoMode = false
    @State private var targetCount = 1
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(minimum: 32, maximum: 56), spacing: 8), count: 5)

    var body: some View {
        NavigationStack {
            Group {
                if let seatMap {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            statsBlock(seatMap)
                            modeBlock
                            priorityLegend
                            seatGrid(seatMap)
                        }
                        .padding()
                    }
                } else if isLoading {
                    ProgressView("正在加载座位...")
                } else {
                    ContentUnavailableView(
                        "无法加载座位",
                        systemImage: "wifi.exclamationmark",
                        description: Text(errorMessage ?? "请稍后重试。")
                    )
                }
            }
            .navigationTitle("座位选择")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建任务", action: createTask)
                        .disabled(!autoMode && selectedSeats.isEmpty)
                }
            }
            .task {
                await loadSeats()
            }
            .alert("操作失败", isPresented: Binding(
                get: { errorMessage != nil && !isLoading },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func statsBlock(_ seatMap: SeatMap) -> some View {
        HStack(spacing: 12) {
            statCard(title: "已预订", value: "\(seatMap.reservedCount)", tint: .red)
            statCard(title: "剩余可抢", value: "\(seatMap.availableCount)", tint: .green)
        }
    }

    private func statCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    private var modeBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("自动抢票模式（按优先级轮询）", isOn: $autoMode)

            if autoMode {
                Stepper("目标座位数: \(targetCount)", value: $targetCount, in: 1...10)
                Button("全部恢复中优先级") {
                    appModel.resetSeatPriorities()
                }
                .buttonStyle(.bordered)
            } else {
                Text("手动模式下可直接点选可用座位。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !selectedSeats.isEmpty {
                Text("已选座位: \(selectedSeats.sorted().map(String.init).joined(separator: ", "))")
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var priorityLegend: some View {
        HStack(spacing: 12) {
            legendLabel("H", text: "高优先级", color: .red)
            legendLabel("M", text: "中优先级", color: .orange)
            legendLabel("L", text: "低优先级", color: .gray)
        }
        .font(.caption)
    }

    private func legendLabel(_ badge: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(badge)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(color, in: Circle())
            Text(text)
        }
    }

    private func seatGrid(_ seatMap: SeatMap) -> some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(BusSeatLayout.rows.enumerated()), id: \.offset) { _, row in
                ForEach(Array(row.enumerated()), id: \.offset) { _, seatID in
                    if let seatID, let seat = seatMap.seats.first(where: { $0.id == seatID }) {
                        SeatCell(
                            seat: seat,
                            priority: appModel.priority(for: seatID),
                            isSelected: selectedSeats.contains(seatID),
                            onTap: {
                                guard seat.status == .available else { return }
                                if selectedSeats.contains(seatID) {
                                    selectedSeats.remove(seatID)
                                } else {
                                    selectedSeats.insert(seatID)
                                }
                            },
                            onPriorityChanged: { priority in
                                appModel.setPriority(priority, for: seatID)
                            }
                        )
                    } else {
                        Color.clear
                            .frame(height: 44)
                    }
                }
            }
        }
    }

    private func loadSeats() async {
        isLoading = true
        do {
            seatMap = try await appModel.fetchSeatMap(for: trip, date: travelDate)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func createTask() {
        do {
            try appModel.createReservationTask(
                for: trip,
                date: travelDate,
                selectedSeats: selectedSeats,
                autoMode: autoMode,
                targetCount: targetCount
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SeatCell: View {
    let seat: BusSeat
    let priority: SeatPriority
    let isSelected: Bool
    let onTap: () -> Void
    let onPriorityChanged: (SeatPriority) -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor)
                    .frame(height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : .clear, lineWidth: 2)
                    )

                Text("\(seat.id)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(foregroundColor)

                Text(priority.shortLabel)
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(priorityColor, in: Circle())
                    .offset(x: 6, y: -6)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(SeatPriority.allCases, id: \.rawValue) { priority in
                Button(priority.title) {
                    onPriorityChanged(priority)
                }
            }
        }
        .disabled(seat.status == .disabled)
    }

    private var backgroundColor: Color {
        switch seat.status {
        case .available:
            return isSelected ? .blue.opacity(0.2) : .green.opacity(0.18)
        case .reserved:
            return .red.opacity(0.18)
        case .disabled:
            return .gray.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch seat.status {
        case .disabled:
            return .secondary
        default:
            return .primary
        }
    }

    private var priorityColor: Color {
        switch priority {
        case .high:
            return .red
        case .medium:
            return .orange
        case .low:
            return .gray
        }
    }
}
