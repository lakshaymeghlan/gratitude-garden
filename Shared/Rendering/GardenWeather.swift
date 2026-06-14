import Foundation

/// The current real-world weather, as an **atmosphere-only** layer — completely separate from
/// progression, lighting, and vitality. It never changes what the garden *contains*; it only adds
/// rain/snow/clouds/wind over the top. Derived from Open-Meteo's current conditions.
struct GardenWeather: Equatable {
    enum Condition: String, Equatable { case clear, cloudy, rain, snow }

    var condition: Condition
    var wind: Double      // 0 (still) … 1 (strong) — drives tree/flower sway
    var clouds: Double    // 0 (clear) … 1 (overcast) — cloud cover + sky darkening

    static let clear = GardenWeather(condition: .clear, wind: 0, clouds: 0)

    var isPrecipitating: Bool { condition == .rain || condition == .snow }

    /// Map Open-Meteo's `weather_code` (WMO) + wind speed (km/h) to our atmosphere.
    /// WMO codes: 0 clear · 1–3 partly→overcast · 45/48 fog · 51–67 drizzle/rain · 71–77 snow ·
    /// 80–82 rain showers · 85/86 snow showers · 95–99 thunderstorm.
    static func from(weatherCode code: Int, windSpeedKmh: Double) -> GardenWeather {
        let wind = min(1.0, max(0.0, (windSpeedKmh - 6) / 34))   // ~6 km/h calm … ~40 km/h strong
        let condition: Condition
        var clouds: Double
        switch code {
        case 71...77, 85, 86:            condition = .snow;   clouds = 0.85
        case 51...67, 80...82, 95...99:  condition = .rain;   clouds = 0.9
        case 45, 48:                     condition = .cloudy; clouds = 0.75
        case 2, 3:                       condition = .cloudy; clouds = code == 3 ? 0.85 : 0.6
        case 1:                          condition = .clear;  clouds = 0.3
        default:                         condition = .clear;  clouds = 0.08
        }
        if condition == .rain || condition == .snow { clouds = max(clouds, 0.8) }
        return GardenWeather(condition: condition, wind: wind, clouds: clouds)
    }
}
