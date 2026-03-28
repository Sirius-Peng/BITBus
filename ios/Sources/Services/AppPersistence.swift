import Foundation

struct AppPersistence {
    static let live = AppPersistence()

    private let defaults: UserDefaults
    private let settingsKey = "bitbusgrab.settings"
    private let prioritiesKey = "bitbusgrab.priorities"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSettings() -> APISettings {
        guard
            let data = defaults.data(forKey: settingsKey),
            let settings = try? JSONDecoder().decode(APISettings.self, from: data)
        else {
            return APISettings()
        }
        return settings
    }

    func saveSettings(_ settings: APISettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        defaults.set(data, forKey: settingsKey)
    }

    func loadSeatPriorities() -> [Int: SeatPriority] {
        guard
            let data = defaults.data(forKey: prioritiesKey),
            let raw = try? JSONDecoder().decode([String: Int].self, from: data)
        else {
            return Self.defaultSeatPriorities()
        }

        var priorities = Self.defaultSeatPriorities()
        for (seat, value) in raw {
            if let seatID = Int(seat), let priority = SeatPriority(rawValue: value) {
                priorities[seatID] = priority
            }
        }
        return priorities
    }

    func saveSeatPriorities(_ priorities: [Int: SeatPriority]) {
        let raw = priorities.reduce(into: [String: Int]()) { result, entry in
            result[String(entry.key)] = entry.value.rawValue
        }
        guard let data = try? JSONEncoder().encode(raw) else {
            return
        }
        defaults.set(data, forKey: prioritiesKey)
    }

    static func defaultSeatPriorities() -> [Int: SeatPriority] {
        Dictionary(uniqueKeysWithValues: (1...51).compactMap { seatID in
            guard !BusSeatLayout.disabledSeatIDs.contains(seatID) else {
                return nil
            }
            return (seatID, .medium)
        })
    }
}
