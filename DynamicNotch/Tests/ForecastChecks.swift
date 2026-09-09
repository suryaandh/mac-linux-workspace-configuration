import Foundation

@main struct ForecastChecks {
    static func main() {
        let hourly = WeatherResponse.Hourly(time: [0, 3600, 7200, 10800], temperature_2m: [20, 21, nil], weather_code: [0, 61, 3], is_day: [0, 1, 1], precipitation_probability: [0, 90])
        let result = WeatherStore.hours(from: hourly, now: Date(timeIntervalSince1970: 3600))
        precondition(result.count == 1, "Past, missing and mismatched records must be skipped")
        precondition(result[0].code == 61 && result[0].rainChance == 90)
        precondition(WeatherStore.symbol(0, isDay: false) == "moon.stars.fill")
        precondition(WeatherStore.symbol(0) == "sun.max.fill")
        precondition(WeatherStore.symbol(61) == "cloud.rain.fill")
        precondition(WeatherStore.symbol(95) == "cloud.bolt.rain.fill")
        print("Forecast checks passed: hourly boundaries, missing data, sun/night/rain icons")
    }
}
