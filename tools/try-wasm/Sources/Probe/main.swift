import Foundation
@testable import VolantCalc

/// Prints, one step at a time, which time zone and date APIs Foundation for WASI supports, so a trap
/// shows which step it stopped after.
func step(_ name: String, _ body: () -> String) {
    print("start \(name)")
    print("  \(name): \(body())")
}

step("utc") { TimeZone(identifier: "UTC").map { "\($0.identifier) \($0.secondsFromGMT())" } ?? "nil" }
step("tokyo") { TimeZone(identifier: "Asia/Tokyo").map { "\($0.identifier) \($0.secondsFromGMT())" } ?? "nil" }
step("known") { "\(TimeZone.knownTimeZoneIdentifiers.count)" }
step("abbreviation") { TimeZone(abbreviation: "EST")?.identifier ?? "nil" }
step("calendar") {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return "\(calendar.component(.hour, from: Date(timeIntervalSince1970: 0)))"
}
step("formatter") {
    let formatter = Foundation.DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateStyle = .full
    return formatter.string(from: Date(timeIntervalSince1970: 0))
}
step("template") { Foundation.DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: Locale(identifier: "en_US")) ?? "nil" }
step("lock") { let lock = NSLock(); lock.lock(); lock.unlock(); return "ok" }
step("regex") { (try? NSRegularExpression(pattern: #"(?<!\d)-|-(?!\d)"#)) == nil ? "nil" : "ok" }
step("range regex") { "3pm".range(of: #"^(\d{1,2}(:\d{2})?(am|pm)?|noon|midnight)$"#, options: .regularExpression) == nil ? "no match" : "match" }
step("replace regex") { "2nd".replacingOccurrences(of: #"\b(\d+)(st|nd|rd|th)\b"#, with: "$1", options: .regularExpression) }
let now = Date(timeIntervalSince1970: 1_794_040_200)
let la = TimeZone(identifier: "America/Los_Angeles")!
let english = Locale(identifier: "en_US")
step("utc template") {
    let formatter = Foundation.DateFormatter()
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.locale = english
    formatter.setLocalizedDateFormatFromTemplate("jmm")
    return formatter.string(from: now)
}
step("fixed offset format") {
    let formatter = Foundation.DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: -8 * 3600)
    formatter.locale = english
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: now)
}
step("la calendar components") {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = la
    let parts = calendar.dateComponents([.hour, .minute], from: now)
    return "\(parts.hour ?? -1):\(parts.minute ?? -1) dst=\(la.isDaylightSavingTime(for: now)) offset=\(la.secondsFromGMT(for: now))"
}
// A named zone such as America/Los_Angeles in Foundation.DateFormatter traps on WASI (see
// WASIDateFormatter.swift); those steps are left out so the rest can run.
for template in ["EEEEMMMMd", "MMMd", "MMM d yyyy", "jmm"] {
    step("template \(template)") { Foundation.DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: english) ?? "nil" }
}
for pattern in ["MMM d", "LLL d", "MMMM d", "EEEE, MMMM d", "EEE, MMM d"] {
    step("pattern \(pattern)") {
        let formatter = Foundation.DateFormatter()
        formatter.locale = english
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = pattern
        return formatter.string(from: now)
    }
}
for (name, order) in [("calendar then format", 0), ("format then calendar", 1), ("no calendar", 2)] {
    step(name) {
        let formatter = Foundation.DateFormatter()
        formatter.locale = english
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -8 * 3600)!
        calendar.locale = english
        if order == 0 { formatter.calendar = calendar }
        formatter.dateFormat = "EEEE, MMMM d"
        if order == 1 { formatter.calendar = calendar }
        formatter.timeZone = TimeZone(secondsFromGMT: -8 * 3600)
        return formatter.string(from: now)
    }
}
step("place shaped") { "\(TimeCalculator.placeShaped("tokyo"))" }
step("city lookup") { CityDirectory.shared.lookup("tokyo")?.name ?? "nil" }
step("airport lookup") { AirportDirectory.shared.lookup("lax")?.code ?? "nil" }
step("time 3pm utc") { TimeCalculator.evaluate("3pm utc in est", now: now, localZone: la, locale: english)?.headline ?? "nil" }
step("time tokyo") { TimeCalculator.evaluate("3pm tokyo in new york", now: now, localZone: la, locale: english)?.headline ?? "nil" }
step("date") { DateCalculator.evaluate("1000 days from today", now: now, localZone: la, locale: english)?.result ?? "nil" }
step("localized name") { TimeZone(identifier: "UTC")?.localizedName(for: .generic, locale: Locale(identifier: "en_US")) ?? "nil" }
