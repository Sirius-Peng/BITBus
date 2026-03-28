import Foundation
import Observation

@MainActor
@Observable
final class ReservationTaskManager {
    private(set) var tasks: [GrabTaskRecord] = []

    private let serviceFactory: @Sendable () -> BITBusAPIClient
    private let notifications: NotificationClient
    private let parallelWorkers = 5
    private var taskHandles: [UUID: Task<Void, Never>] = [:]

    init(
        serviceFactory: @escaping @Sendable () -> BITBusAPIClient,
        notifications: NotificationClient
    ) {
        self.serviceFactory = serviceFactory
        self.notifications = notifications
    }

    func requestNotificationAuthorization() async {
        await notifications.requestAuthorization()
    }

    func createTask(
        trip: BusTrip,
        travelDate: String,
        settings: APISettings,
        selectedSeats: [Int],
        autoMode: Bool,
        targetCount: Int,
        priorities: [Int: SeatPriority]
    ) {
        let startAt = ReservationTiming.openingTime(for: trip, travelDate: travelDate)
        let record = GrabTaskRecord(
            id: UUID(),
            trip: trip,
            travelDate: travelDate,
            selectedSeats: selectedSeats,
            autoMode: autoMode,
            targetCount: targetCount,
            status: .pending,
            message: startAt <= .now ? "立即开始抢票" : "等待开抢",
            createdAt: .now,
            startAt: startAt,
            reservedSeats: []
        )

        tasks.insert(record, at: 0)

        taskHandles[record.id] = Task { [weak self] in
            await self?.runTask(
                id: record.id,
                trip: trip,
                travelDate: travelDate,
                settings: settings,
                selectedSeats: selectedSeats,
                autoMode: autoMode,
                targetCount: targetCount,
                priorities: priorities,
                startAt: startAt
            )
        }
    }

    func cancelTask(_ id: UUID) {
        taskHandles[id]?.cancel()
        updateTask(id) {
            $0.status = .cancelled
            $0.message = "任务已取消"
        }
    }

    func deleteTask(_ id: UUID) {
        taskHandles[id]?.cancel()
        taskHandles[id] = nil
        tasks.removeAll { $0.id == id }
    }

    private func runTask(
        id: UUID,
        trip: BusTrip,
        travelDate: String,
        settings: APISettings,
        selectedSeats: [Int],
        autoMode: Bool,
        targetCount: Int,
        priorities: [Int: SeatPriority],
        startAt: Date
    ) async {
        await waitUntilStart(id: id, startAt: startAt)
        guard !Task.isCancelled else {
            finishTask(id, status: .cancelled, message: "任务已取消")
            return
        }

        updateTask(id) {
            $0.status = .running
            $0.message = "正在抢票..."
        }

        if autoMode {
            await runAutoMode(
                id: id,
                trip: trip,
                travelDate: travelDate,
                settings: settings,
                targetCount: targetCount,
                priorities: priorities
            )
        } else {
            await runManualMode(
                id: id,
                trip: trip,
                travelDate: travelDate,
                settings: settings,
                selectedSeats: selectedSeats
            )
        }

        taskHandles[id] = nil
    }

    private func waitUntilStart(id: UUID, startAt: Date) async {
        updateTask(id) { task in
            task.status = .waiting
        }

        while Date.now < startAt {
            guard !Task.isCancelled else { return }
            let remaining = Int(startAt.timeIntervalSinceNow)
            let minutes = max(0, remaining / 60)
            let seconds = max(0, remaining % 60)
            updateTask(id) {
                $0.message = "等待开抢（\(minutes)分\(seconds)秒后开始）"
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func runManualMode(
        id: UUID,
        trip: BusTrip,
        travelDate: String,
        settings: APISettings,
        selectedSeats: [Int]
    ) async {
        let serviceFactory = self.serviceFactory

        updateTask(id) {
            $0.message = "并行尝试 \(selectedSeats.count) 个座位..."
        }

        var successSeats: [Int] = []
        var failedSeats: [Int] = []

        await withTaskGroup(of: ReservationResult.self) { group in
            for seatID in selectedSeats {
                group.addTask {
                    await serviceFactory().reserveSeat(
                        busID: trip.id,
                        seatID: seatID,
                        date: travelDate,
                        settings: settings
                    )
                }
            }

            for await result in group {
                guard !Task.isCancelled else { return }
                if result.success {
                    successSeats.append(result.seatID)
                    updateTask(id) {
                        $0.reservedSeats.append(result.seatID)
                        $0.message = "座位 \(result.seatID) 预订成功"
                    }
                } else {
                    failedSeats.append(result.seatID)
                    updateTask(id) {
                        $0.message = "座位 \(result.seatID) 失败: \(result.message)"
                    }
                }
            }
        }

        if Task.isCancelled {
            finishTask(id, status: .cancelled, message: "任务已取消")
            return
        }

        if successSeats.isEmpty {
            let message = "所选座位均未抢到: \(failedSeats.map(String.init).joined(separator: ", "))"
            finishTask(id, status: .failed, message: message)
            await notifications.send("BITBusGrab 抢票失败", message)
        } else {
            let message = "已预订座位: \(successSeats.sorted().map(String.init).joined(separator: ", "))"
            finishTask(id, status: .success, message: message)
            await notifications.send("BITBusGrab 抢票成功", message)
        }
    }

    private func runAutoMode(
        id: UUID,
        trip: BusTrip,
        travelDate: String,
        settings: APISettings,
        targetCount: Int,
        priorities: [Int: SeatPriority]
    ) async {
        let serviceFactory = self.serviceFactory
        var round = 0
        var triedSeats = Set<Int>()
        var reservedSeats = currentTask(id)?.reservedSeats ?? []

        while reservedSeats.count < targetCount && round < 1000 && !Task.isCancelled {
            round += 1

            do {
                let seatMap = try await serviceFactory().fetchSeatMap(
                    busID: trip.id,
                    date: travelDate,
                    settings: settings
                )

                let availableSeats = SeatSelectionPlanner.prioritizedAvailableSeats(
                    in: seatMap,
                    priorities: priorities,
                    excluding: triedSeats
                )

                if availableSeats.isEmpty {
                    updateTask(id) {
                        $0.message = "暂无可用座位，第 \(round) 轮继续尝试..."
                    }
                    if round.isMultiple(of: 10) {
                        triedSeats.removeAll()
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                    continue
                }

                let remaining = targetCount - reservedSeats.count
                let batch = Array(availableSeats.prefix(min(parallelWorkers, remaining)))
                updateTask(id) {
                    $0.message = "第 \(round) 轮尝试 \(batch.count) 个座位..."
                }

                await withTaskGroup(of: ReservationResult.self) { group in
                    for seatID in batch {
                        group.addTask {
                            await serviceFactory().reserveSeat(
                                busID: trip.id,
                                seatID: seatID,
                                date: travelDate,
                                settings: settings
                            )
                        }
                    }

                    for await result in group {
                        triedSeats.insert(result.seatID)
                        guard !Task.isCancelled else { return }
                        if result.success && !reservedSeats.contains(result.seatID) && reservedSeats.count < targetCount {
                            reservedSeats.append(result.seatID)
                            updateTask(id) {
                                $0.reservedSeats = reservedSeats.sorted()
                                $0.message = "座位 \(result.seatID) 预订成功，已抢 \(reservedSeats.count)/\(targetCount)"
                            }
                            await notifications.send(
                                "BITBusGrab 已抢到座位",
                                "座位 \(result.seatID) 预订成功，当前 \(reservedSeats.count)/\(targetCount)"
                            )
                        } else if !result.success {
                            updateTask(id) {
                                $0.message = "座位 \(result.seatID) 失败: \(result.message)"
                            }
                        }
                    }
                }

                try? await Task.sleep(for: .milliseconds(200))
            } catch {
                finishTask(id, status: .failed, message: error.localizedDescription)
                await notifications.send("BITBusGrab 抢票失败", error.localizedDescription)
                return
            }
        }

        if Task.isCancelled {
            finishTask(id, status: .cancelled, message: "任务已取消")
            return
        }

        if reservedSeats.count >= targetCount {
            let message = "抢票成功，已预订座位: \(reservedSeats.sorted().map(String.init).joined(separator: ", "))"
            finishTask(id, status: .success, message: message)
            await notifications.send("BITBusGrab 抢票成功", message)
        } else {
            let message = reservedSeats.isEmpty
                ? "抢票未完成，已达到最大轮询次数"
                : "仅抢到部分座位: \(reservedSeats.sorted().map(String.init).joined(separator: ", "))"
            finishTask(id, status: .failed, message: message)
            await notifications.send("BITBusGrab 抢票未完成", message)
        }
    }

    private func currentTask(_ id: UUID) -> GrabTaskRecord? {
        tasks.first { $0.id == id }
    }

    private func finishTask(_ id: UUID, status: GrabTaskStatus, message: String) {
        updateTask(id) {
            $0.status = status
            $0.message = message
        }
    }

    private func updateTask(_ id: UUID, mutate: (inout GrabTaskRecord) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutate(&tasks[index])
    }
}
