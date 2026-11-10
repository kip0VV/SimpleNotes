import Cocoa

final class ReminderDateInput: NSStackView {
  let day = NSDatePicker()
  let time = NSTextField()

  init(date: Date, calendar: Calendar = .current) {
    super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 100))
    orientation = .vertical
    alignment = .leading
    spacing = 10
    day.datePickerStyle = .textFieldAndStepper
    day.datePickerElements = .yearMonthDay
    day.calendar = calendar
    day.timeZone = calendar.timeZone
    day.dateValue = date
    day.setAccessibilityLabel("Дата напоминания")
    day.widthAnchor.constraint(equalToConstant: 200).isActive = true
    let components = calendar.dateComponents([.hour, .minute], from: date)
    time.stringValue = String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    time.placeholderString = "ЧЧ:ММ"
    time.setAccessibilityLabel("Время напоминания")
    time.widthAnchor.constraint(equalToConstant: 90).isActive = true
    for (title, control) in [("Дата", day as NSView), ("Время", time as NSView)] {
      let label = NSTextField(labelWithString: title)
      label.widthAnchor.constraint(equalToConstant: 55).isActive = true
      let row = NSStackView(views: [label, control])
      row.spacing = 12
      row.alignment = .centerY
      addArrangedSubview(row)
    }
    let hint = NSTextField(labelWithString: "Время в 24-часовом формате, например 18:30.")
    hint.font = .systemFont(ofSize: 11)
    hint.textColor = .secondaryLabelColor
    addArrangedSubview(hint)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func selectedDate(calendar: Calendar = .current) -> Date? {
    let value = time.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2,
      parts.allSatisfy({ $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
      let hour = Int(parts[0]), let minute = Int(parts[1]),
      (0...23).contains(hour), (0...59).contains(minute)
    else { return nil }
    var components = calendar.dateComponents([.era, .year, .month, .day], from: day.dateValue)
    components.hour = hour
    components.minute = minute
    components.second = 0
    guard let date = calendar.date(from: components) else { return nil }
    let actual = calendar.dateComponents([.hour, .minute], from: date)
    // A daylight-saving transition can skip the requested local time.
    return actual.hour == hour && actual.minute == minute ? date : nil
  }
}
