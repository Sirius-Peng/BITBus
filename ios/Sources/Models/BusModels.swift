import Foundation

enum RouteDirection: String, CaseIterable, Codable, Identifiable, Sendable {
    case liangxiangToZhongguancun = "良乡校区->中关村校区"
    case zhongguancunToLiangxiang = "中关村校区->良乡校区"
    case zhongguancunToXishan = "中关村校区->西山校区"
    case xishanToZhongguancun = "西山校区->中关村校区"
    case zhongguancunToHuilongguan = "中关村校区->回龙观"
    case huilongguanToZhongguancun = "回龙观->中关村校区"
    case zhongguancunToFangshan = "中关村校区->房山分校阎村"
    case fangshanToZhongguancun = "房山分校阎村->中关村校区"
    case liangxiangToHuilongguan = "良乡校区->回龙观"
    case huilongguanToLiangxiang = "回龙观->良乡校区"

    var id: String { rawValue }

    var origin: String {
        rawValue.components(separatedBy: "->").first ?? ""
    }

    var destination: String {
        rawValue.components(separatedBy: "->").last ?? ""
    }

    var displayName: String {
        "\(origin) → \(destination)"
    }
}

struct APISettings: Codable, Equatable, Sendable {
    var host: String = "hqapp1.bit.edu.cn"
    var token: String = ""
    var time: String = ""
    var userID: String = ""

    func validate() throws {
        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SettingsValidationError.emptyHost
        }
        if token.count != 32 {
            throw SettingsValidationError.invalidToken
        }
        if time.count != 13 {
            throw SettingsValidationError.invalidTime
        }
        if userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SettingsValidationError.emptyUserID
        }
    }
}

enum SettingsValidationError: LocalizedError {
    case emptyHost
    case invalidToken
    case invalidTime
    case emptyUserID

    var errorDescription: String? {
        switch self {
        case .emptyHost:
            return "请填写 API Host。"
        case .invalidToken:
            return "API Token 必须为 32 位字符。"
        case .invalidTime:
            return "API Time 必须为 13 位时间戳。"
        case .emptyUserID:
            return "请填写用户 ID。"
        }
    }
}

struct BusTrip: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: String
    let originAddress: String
    let originTime: String
    let endAddress: String
    let endTime: String
    let studentTicketPrice: String
    let type: Int
    let reservationNumAble: Int

    var isRainbowBus: Bool {
        type == 1
    }
}

enum SeatStatus: String, Codable, Equatable, Sendable {
    case available
    case reserved
    case disabled
}

enum SeatPriority: Int, CaseIterable, Codable, Sendable {
    case high = 1
    case medium = 2
    case low = 3

    var title: String {
        switch self {
        case .high:
            return "高优先级"
        case .medium:
            return "中优先级"
        case .low:
            return "低优先级"
        }
    }

    var shortLabel: String {
        switch self {
        case .high:
            return "H"
        case .medium:
            return "M"
        case .low:
            return "L"
        }
    }
}

struct BusSeat: Identifiable, Equatable, Sendable {
    let id: Int
    let status: SeatStatus
    let reason: String?
}

struct SeatMap: Equatable, Sendable {
    let reservedCount: Int
    let reservationCount: Int
    let totalSeats: Int
    let availableCount: Int
    let seats: [BusSeat]
    let reservedSeats: [Int]
}

struct ReservationResult: Sendable {
    let success: Bool
    let message: String
    let seatID: Int
}

enum GrabTaskStatus: String, Codable, Equatable, Sendable {
    case pending
    case waiting
    case running
    case success
    case failed
    case cancelled

    var label: String {
        switch self {
        case .pending:
            return "准备中"
        case .waiting:
            return "等待开抢"
        case .running:
            return "抢票中"
        case .success:
            return "成功"
        case .failed:
            return "失败"
        case .cancelled:
            return "已取消"
        }
    }
}

struct GrabTaskRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let trip: BusTrip
    let travelDate: String
    let selectedSeats: [Int]
    let autoMode: Bool
    let targetCount: Int
    var status: GrabTaskStatus
    var message: String
    let createdAt: Date
    let startAt: Date
    var reservedSeats: [Int]
}

enum BusSeatLayout {
    static let rows: [[Int?]] = [
        [1, nil, nil, nil, 2],
        [3, 4, nil, 5, 6],
        [7, 8, nil, 9, 10],
        [11, 12, nil, 13, 14],
        [15, 16, nil, 17, 18],
        [19, 20, nil, 21, 22],
        [23, 24, nil, 25, 26],
        [27, 28, nil, nil, nil],
        [29, 30, nil, nil, nil],
        [31, 32, nil, 33, 34],
        [35, 36, nil, 37, 38],
        [39, 40, nil, 41, 42],
        [43, 44, nil, 45, 46],
        [47, 48, 49, 50, 51]
    ]

    static let disabledSeatIDs: Set<Int> = [1, 2, 49]
}

enum ReservationTiming {
    static func openingTime(
        for trip: BusTrip,
        travelDate: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        guard let departure = parseDepartureTime(
            dateString: travelDate,
            timeString: trip.originTime,
            calendar: calendar
        ) else {
            return now
        }

        let start = departure.addingTimeInterval(-3600)
        return max(start, now)
    }

    private static func parseDepartureTime(
        dateString: String,
        timeString: String,
        calendar: Calendar
    ) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(dateString) \(timeString)")
    }
}

enum SeatSelectionPlanner {
    static func prioritizedAvailableSeats(
        in seatMap: SeatMap,
        priorities: [Int: SeatPriority],
        excluding triedSeats: Set<Int>
    ) -> [Int] {
        seatMap.seats
            .filter { $0.status == .available && !triedSeats.contains($0.id) }
            .sorted {
                priorities[$0.id, default: .medium].rawValue < priorities[$1.id, default: .medium].rawValue
            }
            .map(\.id)
    }
}
