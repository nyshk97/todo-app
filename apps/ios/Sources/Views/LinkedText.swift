import SwiftUI

func linkedText(_ string: String) -> Text {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
        return Text(string)
    }

    let nsString = string as NSString
    let matches = detector.matches(in: string, range: NSRange(location: 0, length: nsString.length))

    guard !matches.isEmpty else {
        return Text(string)
    }

    var attributed = AttributedString(string)

    for match in matches {
        guard let range = Range(match.range, in: string),
              let url = match.url,
              let attrRange = Range(range, in: attributed) else { continue }
        attributed[attrRange].link = url
    }

    return Text(attributed)
}
