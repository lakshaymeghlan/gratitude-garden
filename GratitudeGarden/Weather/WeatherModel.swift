import SwiftUI
import CoreLocation
import os

/// Fetches the **current real-world weather** from Open-Meteo (free, no API key) and publishes it as
/// a `GardenWeather` the scene renders as atmosphere only. Fails soft: any error (no permission, no
/// network) just leaves the last value — the world stays calm/clear, never broken.
@MainActor
@Observable
final class WeatherModel {
    private(set) var weather: GardenWeather = .clear

    @ObservationIgnored private let location = LocationProvider()
    @ObservationIgnored private var lastFetch: Date?
    @ObservationIgnored private let minInterval: TimeInterval = 20 * 60   // refresh at most every 20 min
    @ObservationIgnored private let log = Logger(subsystem: "ai.sofsuite.gratitudegarden", category: "weather")

    /// Refresh if enough time has passed (call on appear / when the app becomes active).
    func refreshIfStale() async {
        if let last = lastFetch, Date().timeIntervalSince(last) < minInterval { return }
        await refresh()
    }

    func refresh() async {
        guard let coord = await location.currentCoordinate() else {
            log.info("weather: no location; staying clear")
            return
        }
        guard let url = endpoint(for: coord) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let resp = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            weather = .from(weatherCode: resp.current.weather_code,
                            windSpeedKmh: resp.current.wind_speed_10m)
            lastFetch = Date()
            log.info("weather: \(self.weather.condition.rawValue, privacy: .public) wind=\(self.weather.wind)")
        } catch {
            log.error("weather fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func endpoint(for c: CLLocationCoordinate2D) -> URL? {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        comps?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", c.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", c.longitude)),
            URLQueryItem(name: "current", value: "weather_code,wind_speed_10m"),
        ]
        return comps?.url
    }

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable { let weather_code: Int; let wind_speed_10m: Double }
        let current: Current
    }
}
