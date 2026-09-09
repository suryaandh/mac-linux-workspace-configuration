import Foundation
import Observation
import CoreLocation

struct WeatherPlace: Decodable, Identifiable {
    let id: Int
    let name: String
    let country: String?
    let admin1: String?
    let latitude: Double
    let longitude: Double
    var label: String { [name, admin1, country].compactMap { $0 }.joined(separator: ", ") }
}
struct WeatherResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let relative_humidity_2m: Double
        let apparent_temperature: Double
        let weather_code: Int
        let wind_speed_10m: Double
    }
    struct Hourly: Decodable {
        let time: [Double]
        let temperature_2m: [Double?]
        let weather_code: [Int?]
        let is_day: [Int?]
        let precipitation_probability: [Double?]
    }
    let current: Current
    let hourly: Hourly?
    let timezone: String?
}

struct ForecastHour: Identifiable {
    var id: Date { start }
    let start: Date
    let temperature: Double
    let code: Int
    let isDay: Bool
    let rainChance: Double?
}

@Observable
final class WeatherStore: NSObject {
    static let shared = WeatherStore()
    var query = ""
    private(set) var places: [WeatherPlace] = []
    private(set) var current: WeatherResponse.Current?
    private(set) var forecast: [ForecastHour] = []
    private(set) var timeZone = TimeZone.current
    private(set) var location = "Detecting location…"
    private(set) var status = "Detecting your location…"
    private(set) var loading = false
    private(set) var updated: Date?
    private var selected: WeatherPlace?
    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        requestLocationAndLoad()
    }

    private func requestLocationAndLoad() {
        Task { await loadFromDeviceLocation() }
    }

    func loadFromDeviceLocation() async {
        guard !loading else { return }
        loading = true
        status = "Detecting your location…"
        location = "Detecting location…"
        defer { loading = false }
        do {
            let clLocation = try await requestLocation()
            let geocoder = CLGeocoder()
            let placemarks = try await geocoder.reverseGeocodeLocation(clLocation)
            guard let pm = placemarks.first else { status = "Could not determine location"; return }
            let name = pm.locality ?? pm.administrativeArea ?? pm.country ?? "Unknown"
            let country = pm.country
            let admin1 = pm.administrativeArea
            let place = WeatherPlace(
                id: 0,
                name: name,
                country: country,
                admin1: admin1,
                latitude: clLocation.coordinate.latitude,
                longitude: clLocation.coordinate.longitude
            )
            loading = false
            await load(place)
        } catch {
            status = "Location unavailable: \(error.localizedDescription)"
            location = "Choose a city"
        }
    }

    private func requestLocation() async throws -> CLLocation {
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            switch locationManager.authorizationStatus {
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                locationManager.requestLocation()
            default:
                continuation.resume(throwing: CLError(.denied))
                locationContinuation = nil
            }
        }
    }
    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func search() async {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !loading, name.count >= 2 else { return }
        loading = true
        defer { loading = false }
        var url = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        url.queryItems = [.init(name: "name", value: name), .init(name: "count", value: "5"), .init(name: "language", value: "en")]
        do {
            struct Results: Decodable { let results: [WeatherPlace]? }
            let result: Results = try await fetch(url.url!)
            places = result.results ?? []
            status = places.isEmpty ? "No matching cities" : "Select a city"
        } catch { places = []; status = "Search failed: \(error.localizedDescription)" }
    }
    func load(_ place: WeatherPlace) async {
        guard !loading else { return }
        selected = place
        loading = true
        current = nil
        forecast = []
        updated = nil
        location = place.label
        status = "Loading weather…"
        defer { loading = false }
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            .init(name: "latitude", value: String(place.latitude)), .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m"), .init(name: "timezone", value: "auto"),
            .init(name: "hourly", value: "temperature_2m,weather_code,is_day,precipitation_probability"),
            .init(name: "timeformat", value: "unixtime"), .init(name: "forecast_days", value: "2")]
        do {
            let result: WeatherResponse = try await fetch(url.url!)
            current = result.current
            timeZone = TimeZone(identifier: result.timezone ?? "") ?? .current
            forecast = Self.hours(from: result.hourly, now: Date())
            updated = Date()
            places = []
            status = "Current model conditions"
        } catch { status = "Weather unavailable: \(error.localizedDescription)" }
    }
    func refresh() async { if let selected { await load(selected) } }

    // 2 before now + now + 5 after = 8 total
    func nearby6(around now: Date) -> [ForecastHour] {
        guard !forecast.isEmpty else { return [] }
        let sorted = forecast.sorted { $0.start < $1.start }
        let idx = sorted.firstIndex(where: { $0.start >= now }) ?? sorted.endIndex
        let before = min(2, idx)
        let after = 5
        let start = idx - before
        let end = min(sorted.count, idx + 1 + after)
        return Array(sorted[start..<end])
    }

    func shortHour(_ hour: ForecastHour) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: hour.start)
    }
    static func hours(from hourly: WeatherResponse.Hourly?, now: Date) -> [ForecastHour] {
        guard let hourly else { return [] }
        return Array(hourly.time.indices.compactMap { index -> ForecastHour? in
            let start = Date(timeIntervalSince1970: hourly.time[index])
            guard start.addingTimeInterval(3600) > now,
                  index < hourly.temperature_2m.count, index < hourly.weather_code.count, index < hourly.is_day.count,
                  let temperature = hourly.temperature_2m[index], let code = hourly.weather_code[index], let day = hourly.is_day[index] else { return nil }
            return ForecastHour(start: start, temperature: temperature, code: code, isDay: day == 1,
                                rainChance: index < hourly.precipitation_probability.count ? hourly.precipitation_probability[index] : nil)
        }.prefix(24))
    }
    func intervalLabel(_ hour: ForecastHour) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: hour.start) + "–" + formatter.string(from: hour.start.addingTimeInterval(3600))
    }
    static func symbol(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
    static func condition(_ code: Int) -> String {
        switch code {
        case 0: "Clear sky"
        case 1...3: "Cloudy"
        case 45, 48: "Fog"
        case 51...57: "Drizzle"
        case 61...67, 80...82: "Rain"
        case 71...77, 85, 86: "Snow"
        case 95...99: "Thunderstorm"
        default: "Weather conditions"
        }
    }
}

extension WeatherStore: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            locationContinuation?.resume(throwing: CLError(.denied))
            locationContinuation = nil
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        locationContinuation?.resume(returning: loc)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }
}
