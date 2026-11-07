import Foundation
import VolantCore

/// The request the browser sends: the typed query, the visitor's clock as Unix seconds, their IANA
/// time zone and locale identifier, so answers match what the launcher would show on their Mac.
struct Request: Decodable {
    let query: String
    let now: Double
    let zone: String?
    let locale: String?
}

/// One answer, as the launcher's calculator card shows it.
struct Answer: Encodable {
    let input: String
    let inputDetail: String?
    let result: String
    let resultDetail: String?
    let copyText: String
}

/// Reads one request from standard input, answers it with `CalculationAnswer.answers`, and writes the
/// answers as JSON. A malformed request writes an empty list rather than failing the command.
func main() {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    var answers: [Answer] = []
    if let request = try? JSONDecoder().decode(Request.self, from: data) {
        let zone = request.zone.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: request.locale ?? "en_US")
        answers = CalculationAnswer.answers(for: request.query, now: Date(timeIntervalSince1970: request.now),
                                            localZone: zone, locale: locale).map {
            Answer(input: $0.input, inputDetail: $0.inputDetail, result: $0.result, resultDetail: $0.resultDetail, copyText: $0.copyText)
        }
    }
    let output = (try? JSONEncoder().encode(answers)) ?? Data("[]".utf8)
    FileHandle.standardOutput.write(output)
}

main()
