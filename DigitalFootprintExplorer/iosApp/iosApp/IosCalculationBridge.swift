import Foundation
import Shared

/// [01] Translate the iPhone inputs for the shared calculation model.
/// Keeping the same emission maths helps the Android and iOS estimates stay comparable.
struct SharedFootprintCalculator: FootprintCalculating {
    static func exampleUsage(for category: FootprintCategory) -> CategoryUsage {
        // [02] Starter traffic values and their units are kept in one shared place.
        // Each category starts with traffic and connection assumptions.
        let value = IosUsageAssumptions().defaults.first { $0.category == category.rawValue }
        return CategoryUsage(category: category, gigabytesPerHour: value?.gigabytesPerHour ?? 0,
                             wifiShare: value?.wifiShare ?? 1)
    }
    // [03] Check both sides of the language boundary: bad inputs or a bad result must never become a saved day.
    func calculate(_ inputs: FootprintInputs) throws -> FootprintResult {
        try inputs.validate()
        let usages = inputs.usages.map {
            IosCategoryUsage(category: $0.category.rawValue, minutes: $0.minutes,
                             gigabytesPerHour: $0.gigabytesPerHour, wifiShare: $0.wifiShare)
        }
        // [04] The shared code handles unit changes and the existing Android calculation.
        // This iPhone layer only passes the values across.
        let value = try IosFootprintCalculator().calculateForCalendarDay(usages: usages, brightness: inputs.brightness,
            gpsHours: inputs.gpsHours, bluetoothHours: inputs.bluetoothHours,
            calendarDayMinutes: inputs.usageCapacityMinutes)
        // [05] Refuse an unfamiliar category rather than silently treating it as Other.
        let categories = try value.categories.map { category -> CategoryFootprint in
            guard let kind = FootprintCategory(rawValue: category.category) else { throw FootprintError.invalidResult }
            return CategoryFootprint(category: kind, totalKg: category.totalKg, deviceKg: category.deviceKg,
                                     networkKg: category.networkKg, backendKg: category.backendKg)
        }
        let result = FootprintResult(totalKg: value.totalKg, appUsageKg: value.appUsageKg,
                                     displayKg: value.displayKg, backgroundKg: value.backgroundKg, categories: categories)
        try result.validate()
        return result
    }
}
