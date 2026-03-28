import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var settings: APISettings
    var seatPriorities: [Int: SeatPriority]

    let taskManager: ReservationTaskManager

    private let persistence: AppPersistence
    private let apiClient: BITBusAPIClient

    init(
        persistence: AppPersistence = .live,
        apiClient: BITBusAPIClient = BITBusAPIClient(),
        notificationClient: NotificationClient = .live
    ) {
        self.persistence = persistence
        self.apiClient = apiClient
        self.settings = persistence.loadSettings()
        self.seatPriorities = persistence.loadSeatPriorities()
        self.taskManager = ReservationTaskManager(
            serviceFactory: { BITBusAPIClient() },
            notifications: notificationClient
        )
    }

    func saveSettings() throws {
        try settings.validate()
        persistence.saveSettings(settings)
    }

    func resetSeatPriorities() {
        seatPriorities = AppPersistence.defaultSeatPriorities()
        persistence.saveSeatPriorities(seatPriorities)
    }

    func setPriority(_ priority: SeatPriority, for seatID: Int) {
        seatPriorities[seatID] = priority
        persistence.saveSeatPriorities(seatPriorities)
    }

    func priority(for seatID: Int) -> SeatPriority {
        seatPriorities[seatID, default: .medium]
    }

    func searchBuses(route: RouteDirection, date: Date) async throws -> [BusTrip] {
        try settings.validate()
        return try await apiClient.searchBuses(
            route: route,
            date: date.bitBusString,
            settings: settings
        )
    }

    func fetchSeatMap(for trip: BusTrip, date: Date) async throws -> SeatMap {
        try settings.validate()
        return try await apiClient.fetchSeatMap(
            busID: trip.id,
            date: date.bitBusString,
            settings: settings
        )
    }

    func createReservationTask(
        for trip: BusTrip,
        date: Date,
        selectedSeats: Set<Int>,
        autoMode: Bool,
        targetCount: Int
    ) throws {
        try settings.validate()
        taskManager.createTask(
            trip: trip,
            travelDate: date.bitBusString,
            settings: settings,
            selectedSeats: Array(selectedSeats).sorted(),
            autoMode: autoMode,
            targetCount: targetCount,
            priorities: seatPriorities
        )
    }

    func requestNotificationAuthorization() async {
        await taskManager.requestNotificationAuthorization()
    }
}

extension Date {
    fileprivate var bitBusString: String {
        Self.bitBusDateFormatter.string(from: self)
    }

    private static let bitBusDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
