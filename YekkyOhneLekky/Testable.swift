import Foundation

struct Testable {
    static var offset: TimeInterval = 0

    static func Date() -> Foundation.Date {
        if offset == 0 {
            offset = Foundation.Date().distance(to:ISO8601DateFormatter().date(from:"2027-06-09T12:00:00Z")!)
        }
        return Foundation.Date() + offset
    }
}
