import SwiftUI

struct TasksView: View {
    @Environment(ReservationTaskManager.self) private var taskManager

    var body: some View {
        NavigationStack {
            Group {
                if taskManager.tasks.isEmpty {
                    ContentUnavailableView(
                        "暂无任务",
                        systemImage: "clock.badge.questionmark",
                        description: Text("创建手动抢票或自动抢票任务后会在这里显示。")
                    )
                } else {
                    List {
                        ForEach(taskManager.tasks) { task in
                            TaskCard(task: task)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("任务管理")
        }
    }
}

private struct TaskCard: View {
    @Environment(ReservationTaskManager.self) private var taskManager

    let task: GrabTaskRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(task.trip.originAddress) → \(task.trip.endAddress)")
                    .font(.headline)
                Spacer()
                Text(task.status.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusColor.opacity(0.16), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            Text("发车 \(task.travelDate) \(task.trip.originTime) · 开抢 \(task.startAt.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(task.message)
                .font(.subheadline)

            if !task.reservedSeats.isEmpty {
                Text("已预订座位: \(task.reservedSeats.sorted().map(String.init).joined(separator: ", "))")
                    .font(.footnote.weight(.semibold))
            }

            Text(task.autoMode ? "自动模式 · 目标 \(task.targetCount) 个座位" : "手动模式")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                if task.status == .waiting || task.status == .running {
                    Button("取消") {
                        taskManager.cancelTask(task.id)
                    }
                    .buttonStyle(.bordered)
                }

                Button("删除", role: .destructive) {
                    taskManager.deleteTask(task.id)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        switch task.status {
        case .pending:
            return .orange
        case .waiting:
            return .blue
        case .running:
            return .indigo
        case .success:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .secondary
        }
    }
}
