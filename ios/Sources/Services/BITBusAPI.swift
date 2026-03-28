import Foundation

protocol BusServicing: Sendable {
    func searchBuses(route: RouteDirection, date: String, settings: APISettings) async throws -> [BusTrip]
    func fetchSeatMap(busID: String, date: String, settings: APISettings) async throws -> SeatMap
    func reserveSeat(busID: String, seatID: Int, date: String, settings: APISettings) async -> ReservationResult
}

enum BITBusAPIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case business(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务端返回了无效响应。"
        case .httpStatus(let status):
            return "网络请求失败，状态码 \(status)。"
        case .business(let message):
            return message
        }
    }
}

struct BITBusRequestFactory {
    func searchBusesRequest(settings: APISettings, route: RouteDirection, date: String) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "http"
        components.host = settings.host.trimmingCharacters(in: .whitespacesAndNewlines)
        components.path = "/vehicle/get-list"
        components.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "date", value: date),
            URLQueryItem(name: "address", value: route.rawValue),
            URLQueryItem(name: "userid", value: settings.userID)
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request, settings: settings)
        return request
    }

    func seatMapRequest(settings: APISettings, busID: String, date: String) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "http"
        components.host = settings.host.trimmingCharacters(in: .whitespacesAndNewlines)
        components.path = "/vehicle/get-reserved-seats"
        components.queryItems = [
            URLQueryItem(name: "id", value: busID),
            URLQueryItem(name: "date", value: date),
            URLQueryItem(name: "userid", value: settings.userID)
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(to: &request, settings: settings)
        return request
    }

    func reserveRequest(settings: APISettings, busID: String, seatID: Int, date: String) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "http"
        components.host = settings.host.trimmingCharacters(in: .whitespacesAndNewlines)
        components.path = "/vehicle/create-order"

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = "id=\(busID)&date=\(date)&seat_number=\(seatID)&userid=\(settings.userID)"
            .data(using: .utf8)
        applyHeaders(to: &request, settings: settings)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func applyHeaders(to request: inout URLRequest, settings: APISettings) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(settings.token, forHTTPHeaderField: "apitoken")
        request.setValue(settings.time, forHTTPHeaderField: "apitime")
        request.setValue(settings.host, forHTTPHeaderField: "Host")
    }
}

struct BITBusAPIClient: BusServicing, Sendable {
    private let session: URLSession
    private let requestFactory: BITBusRequestFactory

    init(session: URLSession = .shared, requestFactory: BITBusRequestFactory = BITBusRequestFactory()) {
        self.session = session
        self.requestFactory = requestFactory
    }

    func searchBuses(route: RouteDirection, date: String, settings: APISettings) async throws -> [BusTrip] {
        let request = try requestFactory.searchBusesRequest(settings: settings, route: route, date: date)
        let data = try await perform(request)
        return try Self.parseTrips(from: data, fallbackRoute: route)
    }

    func fetchSeatMap(busID: String, date: String, settings: APISettings) async throws -> SeatMap {
        let request = try requestFactory.seatMapRequest(settings: settings, busID: busID, date: date)
        let data = try await perform(request)
        return try Self.parseSeatMap(from: data)
    }

    func reserveSeat(busID: String, seatID: Int, date: String, settings: APISettings) async -> ReservationResult {
        do {
            let request = try requestFactory.reserveRequest(settings: settings, busID: busID, seatID: seatID, date: date)
            let data = try await perform(request)
            let response = try JSONDecoder().decode(BasicEnvelope.self, from: data)
            let success = response.message == "ok"
            return ReservationResult(
                success: success,
                message: success ? "预订成功" : response.message,
                seatID: seatID
            )
        } catch {
            return ReservationResult(success: false, message: error.localizedDescription, seatID: seatID)
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BITBusAPIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw BITBusAPIError.httpStatus(httpResponse.statusCode)
        }
        return data
    }

    static func parseTrips(from data: Data, fallbackRoute: RouteDirection) throws -> [BusTrip] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(TripEnvelope.self, from: data)

        if envelope.code == "SYS_UNKNOWN" {
            throw BITBusAPIError.business("班车接口返回系统异常。")
        }

        return envelope.data.map {
            BusTrip(
                id: $0.id,
                originAddress: $0.originAddress ?? fallbackRoute.origin,
                originTime: $0.originTime ?? "",
                endAddress: $0.endAddress ?? fallbackRoute.destination,
                endTime: $0.endTime ?? "",
                studentTicketPrice: $0.studentTicketPrice ?? "0.00",
                type: $0.type ?? 0,
                reservationNumAble: $0.reservationNumAble ?? 51
            )
        }
    }

    static func parseSeatMap(from data: Data) throws -> SeatMap {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(SeatEnvelope.self, from: data)

        let reservedSeats = envelope.data.reservedSeatNumber.compactMap(Int.init).sorted()
        let totalSeats = envelope.data.reservationNumAble ?? 51
        let seats = (1...totalSeats).map { seatID -> BusSeat in
            if BusSeatLayout.disabledSeatIDs.contains(seatID) {
                return BusSeat(id: seatID, status: .disabled, reason: "系统保留座位")
            }
            if reservedSeats.contains(seatID) {
                return BusSeat(id: seatID, status: .reserved, reason: "已被预订")
            }
            return BusSeat(id: seatID, status: .available, reason: nil)
        }

        return SeatMap(
            reservedCount: envelope.data.reservedCount ?? reservedSeats.count,
            reservationCount: envelope.data.reservationNum ?? max(0, totalSeats - reservedSeats.count),
            totalSeats: totalSeats,
            availableCount: max(0, (envelope.data.reservationNum ?? totalSeats) - BusSeatLayout.disabledSeatIDs.count),
            seats: seats,
            reservedSeats: reservedSeats
        )
    }
}

private struct TripEnvelope: Decodable {
    let code: String
    let data: [TripDTO]
}

private struct TripDTO: Decodable {
    let id: String
    let originAddress: String?
    let originTime: String?
    let endAddress: String?
    let endTime: String?
    let studentTicketPrice: String?
    let type: Int?
    let reservationNumAble: Int?
}

private struct SeatEnvelope: Decodable {
    let code: String?
    let data: SeatDTO
}

private struct SeatDTO: Decodable {
    let reservedCount: Int?
    let reservationNum: Int?
    let reservationNumAble: Int?
    let reservedSeatNumber: [String]
}

private struct BasicEnvelope: Decodable {
    let message: String
}
