import Foundation

//google AI wrote this file for me

enum UsHolidays: String, CaseIterable {
    case newYearsDay = "New Year's Day"
    case martinLutherKingJrDay = "MLK Day"
    case washingtonSBirthday = "Presidents' Day"
    case goodFriday = "Good Friday"
    case memorialDay = "Memorial Day"
    case juneteenth = "Juneteenth"
    case independenceDay = "Independence Day"
    case laborDay = "Labor Day"
    case thanksgivingDay = "Thanksgiving"
    case christmasDay = "Xmas"

    // Function to calculate the date of the holiday for a given year
    func date(in year: Int, using calendar: Calendar = .current) -> Date? {
        var components = DateComponents()
        components.year = year
        
        switch self {
        case .newYearsDay:
            components.month = 1
            components.day = 1
        case .martinLutherKingJrDay:
            components.month = 1
            components.weekday = 2 // Monday
            components.weekdayOrdinal = 3 // Third Monday
        case .washingtonSBirthday:
            components.month = 2
            components.weekday = 2 // Monday
            components.weekdayOrdinal = 3 // Third Monday
        case .goodFriday:
            // Good Friday is two days before Easter Sunday
            // Calculating Easter requires a specific algorithm (Gregorian Easter calculation)
            return calculateGoodFriday(in: year, using: calendar)
        case .memorialDay:
            components.month = 5
            components.weekday = 2 // Monday
            components.weekdayOrdinal = -1 // Last Monday of the month
        case .juneteenth:
            components.month = 6
            components.day = 19
        case .independenceDay:
            components.month = 7
            components.day = 4
        case .laborDay:
            components.month = 9
            components.weekday = 2 // Monday
            components.weekdayOrdinal = 1 // First Monday
        case .thanksgivingDay:
            components.month = 11
            components.weekday = 5 // Thursday
            components.weekdayOrdinal = 4 // Fourth Thursday
        case .christmasDay:
            components.month = 12
            components.day = 25
        }

        // Calculate the base date (handling fixed dates vs. ordinal dates)
        var date = calendar.date(from: components)

        // Handle weekend "observed" rules for fixed-date holidays (New Years, Juneteenth, Independence Day, Christmas)
        if self == .newYearsDay || self == .juneteenth || self == .independenceDay || self == .christmasDay {
            if let holidayDate = date {
                let weekday = calendar.component(.weekday, from: holidayDate)
                // If Saturday, observed on Friday
                if weekday == 7 { // Saturday
                    date = calendar.date(byAdding: .day, value: -1, to: holidayDate)
                }
                // If Sunday, observed on Monday
                else if weekday == 1 { // Sunday
                    date = calendar.date(byAdding: .day, value: 1, to: holidayDate)
                }
            }
        }
        
        return date
    }
}

/// Helper function to calculate the date of Good Friday (using Gregorian algorithm for Easter)
func calculateGoodFriday(in year: Int, using calendar: Calendar) -> Date? {
    // Implementing the Meeus/Jones/Butcher Gregorian Easter calculation algorithm
    let a = year % 19
    let b = year / 100
    let c = year % 100
    let d = b / 4
    let e = b % 4
    let f = (b + 8) / 25
    let g = (b - f + 1) / 3
    let h = (19 * a + b - d - g + 15) % 30
    let i = c / 4
    let k = c % 4
    let l = (32 + 2 * e + 2 * i - h - k) % 7
    let m = (a + 11 * h + 22 * l) / 451
    let month = (h + l - 7 * m + 114) / 31
    let day = (h + l - 7 * m + 114) % 31 + 1

    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    
    guard let easterSunday = calendar.date(from: components) else {
        return nil
    }
    
    // Good Friday is 2 days before Easter Sunday
    return calendar.date(byAdding: .day, value: -2, to: easterSunday)
}
