import XCTest
@testable import BITBusGrab

final class BITBusGrabTests: XCTestCase {
    func testSearchRequestIncludesHeadersAndQueryItems() throws {
        let settings = APISettings(
            host: "hqapp1.bit.edu.cn",
            token: String(repeating: "a", count: 32),
            time: "1234567890123",
            userID: "10001"
        )

        let request = try BITBusRequestFactory().searchBusesRequest(
            settings: settings,
            route: .liangxiangToZhongguancun,
            date: "2026-03-29"
        )

        let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(items["address"], RouteDirection.liangxiangToZhongguancun.rawValue)
        XCTAssertEqual(items["date"], "2026-03-29")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apitoken"), settings.token)
        XCTAssertEqual(request.value(forHTTPHeaderField: "apitime"), settings.time)
    }

    func testReserveRequestUsesFormEncodedBody() throws {
        let settings = APISettings(
            host: "hqapp1.bit.edu.cn",
            token: String(repeating: "b", count: 32),
            time: "1234567890123",
            userID: "10086"
        )

        let request = try BITBusRequestFactory().reserveRequest(
            settings: settings,
            busID: "bus-1",
            seatID: 18,
            date: "2026-03-29"
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8), "id=bus-1&date=2026-03-29&seat_number=18&userid=10086")
    }

    func testSeatMapParserBuildsDisabledAndReservedSeats() throws {
        let json = """
        {
          "code": "1",
          "data": {
            "is_full": 0,
            "reservation_num": 34,
            "reserved_count": 17,
            "reserved_seat_number": ["3", "11", "50"]
          }
        }
        """.data(using: .utf8)!

        let seatMap = try BITBusAPIClient.parseSeatMap(from: json)

        XCTAssertEqual(seatMap.totalSeats, 51)
        XCTAssertEqual(seatMap.availableCount, 31)
        XCTAssertEqual(seatMap.seats.first(where: { $0.id == 1 })?.status, .disabled)
        XCTAssertEqual(seatMap.seats.first(where: { $0.id == 3 })?.status, .reserved)
        XCTAssertEqual(seatMap.seats.first(where: { $0.id == 4 })?.status, .available)
    }

    func testOpeningTimeStartsOneHourBeforeDeparture() {
        let trip = BusTrip(
            id: "1",
            originAddress: "良乡校区",
            originTime: "17:05",
            endAddress: "中关村校区",
            endTime: "17:55",
            studentTicketPrice: "0.00",
            type: 0,
            reservationNumAble: 51
        )
        let calendar = Calendar(identifier: .gregorian)
        let now = ISO8601DateFormatter().date(from: "2026-03-29T12:00:00+08:00")!

        let opening = ReservationTiming.openingTime(
            for: trip,
            travelDate: "2026-03-29",
            now: now,
            calendar: calendar
        )

        let expected = ISO8601DateFormatter().date(from: "2026-03-29T16:05:00+08:00")!
        XCTAssertEqual(opening.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
    }

    func testSeatPlannerUsesPriorityAndExcludesTriedSeats() {
        let seatMap = SeatMap(
            reservedCount: 0,
            reservationCount: 10,
            totalSeats: 10,
            availableCount: 7,
            seats: [
                BusSeat(id: 3, status: .available, reason: nil),
                BusSeat(id: 4, status: .available, reason: nil),
                BusSeat(id: 5, status: .reserved, reason: nil),
                BusSeat(id: 6, status: .available, reason: nil)
            ],
            reservedSeats: [5]
        )

        let ordered = SeatSelectionPlanner.prioritizedAvailableSeats(
            in: seatMap,
            priorities: [3: .medium, 4: .low, 6: .high],
            excluding: [3]
        )

        XCTAssertEqual(ordered, [6, 4])
    }
}
