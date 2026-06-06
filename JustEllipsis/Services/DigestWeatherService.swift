import CoreLocation
import WeatherKit
import Foundation

struct DigestWeather {
    let weekday: String
    let conditionLabel: String
    let high: Measurement<UnitTemperature>
    let low: Measurement<UnitTemperature>
    let suggestion: String
}

@MainActor
final class DigestWeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = DigestWeatherService()

    @Published private(set) var weather: DigestWeather?

    private let locationManager = CLLocationManager()
    private var cachedDate: Date?
    private var isFetching = false

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func refresh() {
        let today = Calendar.current.startOfDay(for: Date())
        if let cached = cachedDate, Calendar.current.isDate(cached, inSameDayAs: today), weather != nil {
            return
        }
        guard !isFetching else { return }

        let status = locationManager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }

        guard let location = locationManager.location else {
            locationManager.requestLocation()
            return
        }
        fetch(location: location)
    }

    func requestPermissionIfNeeded() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.fetch(location: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }

    private func fetch(location: CLLocation) {
        guard !isFetching else { return }
        isFetching = true
        Task {
            defer { isFetching = false }
            do {
                let service = WeatherService.shared
                let (current, daily) = try await service.weather(
                    for: location,
                    including: .current, .daily
                )
                guard let today = daily.forecast.first else { return }
                let weekday = Date().formatted(.dateTime.weekday(.wide)).uppercased()
                let conditionLabel = condition(for: current.condition)
                let suggestion = readingSuggestion(for: current.condition, high: today.highTemperature)
                weather = DigestWeather(
                    weekday: weekday,
                    conditionLabel: conditionLabel,
                    high: today.highTemperature,
                    low: today.lowTemperature,
                    suggestion: suggestion
                )
                cachedDate = Calendar.current.startOfDay(for: Date())
            } catch {
                // Fail silently — card stays hidden
            }
        }
    }

    private func condition(for condition: WeatherCondition) -> String {
        switch condition {
        case .clear, .mostlyClear:                       return "CLEAR"
        case .partlyCloudy, .mostlyCloudy:               return "PARTLY CLOUDY"
        case .cloudy:                                    return "OVERCAST"
        case .drizzle, .rain, .heavyRain:                return "RAINY"
        case .thunderstorms, .strongStorms, .isolatedThunderstorms: return "STORMY"
        case .snow, .heavySnow, .blizzard, .flurries, .blowingSnow, .sleet: return "SNOWY"
        case .windy, .breezy:                            return "WINDY"
        case .hot:                                       return "HOT"
        case .frigid, .blowingDust:                      return "COLD"
        case .haze, .smoky, .foggy:                      return "FOGGY"
        default:                                         return "CLOUDY"
        }
    }

    private func readingSuggestion(for condition: WeatherCondition, high: Measurement<UnitTemperature>) -> String {
        let celsius = high.converted(to: .celsius).value
        switch condition {
        case .clear, .mostlyClear:
            return celsius > 25 ? "Stay inside. Good reading weather." : "A good day to read outside."
        case .partlyCloudy, .mostlyCloudy:
            return celsius < 10 ? "Good light for reading." : "Good light for reading."
        case .cloudy:
            return "A quiet day. Plenty of time to read."
        case .drizzle, .rain:
            return "A good day to stay in and read."
        case .heavyRain, .thunderstorms, .strongStorms, .isolatedThunderstorms:
            return "Nowhere to be. A good day to read more."
        case .snow, .heavySnow, .blizzard, .flurries, .blowingSnow, .sleet:
            return "Slow day outside. A good day for something long."
        case .windy, .breezy:
            return "A good day to settle in with something."
        case .hot:
            return "Stay inside. Good reading weather."
        case .frigid:
            return "Stay warm. A good day to read something long."
        default:
            return "A good day to read."
        }
    }
}
