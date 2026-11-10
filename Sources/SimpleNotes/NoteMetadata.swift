import Foundation

// Recognize the legacy SimpleNotes header as a whole, not just its topic line.
enum NoteMetadata {
  static func hasHeader(_ lines: [String]) -> Bool {
    guard lines.count >= 4, !lines[0].trimmingCharacters(in: .whitespaces).isEmpty,
      lines[2].hasPrefix("Тема — "), lines[1].count == 16 else { return false }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "dd.MM.yyyy HH:mm"
    formatter.isLenient = false
    guard let date = formatter.date(from: lines[1]) else { return false }
    return formatter.string(from: date) == lines[1]
  }
}
