import SwiftUI

struct DigestWeatherCard: View {
    let weather: DigestWeather

    @Environment(\.appTheme) private var appTheme

    private var temperatureFormatter: MeasurementFormatter {
        let f = MeasurementFormatter()
        f.numberFormatter.maximumFractionDigits = 0
        f.unitStyle = .short
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(weather.weekday) · \(weather.conditionLabel)")
                .font(AppTheme.mono(11))
                .foregroundStyle(appTheme.textFaint)
                .kerning(1.5)

            Text("\(temperatureFormatter.string(from: weather.high)) / \(temperatureFormatter.string(from: weather.low))")
                .font(AppTheme.playfair(22, weight: .semibold))
                .foregroundStyle(appTheme.heading)

            Text(weather.suggestion)
                .font(AppTheme.mono(13))
                .foregroundStyle(appTheme.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.cardPadding)
        .background(appTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}
