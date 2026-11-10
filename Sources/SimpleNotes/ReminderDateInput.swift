import Cocoa

final class ReminderDateInput: NSStackView {
  let day = NSDatePicker()
  let time = NSTextField()
  let repetition = NSPopUpButton()
  let timeLabel = NSTextField(labelWithString: "Время")
  let hint = NSTextField(wrappingLabelWithString: "")
  var dayRow: NSStackView!
  private var previousRepeat = ReminderRepeat.none

  var selectedRepeat: ReminderRepeat {
    ReminderRepeat(rawValue: repetition.selectedItem?.representedObject as? String ?? "") ?? .none
  }

  init(date: Date, repeating: ReminderRepeat = .none, calendar: Calendar = .current) {
    super.init(frame: NSRect(x: 0, y: 0, width: 380, height: 150))
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
    func row(_ label: NSTextField, _ control: NSView) -> NSStackView {
      label.widthAnchor.constraint(equalToConstant: 55).isActive = true
      let row = NSStackView(views: [label, control])
      row.spacing = 12
      row.alignment = .centerY
      addArrangedSubview(row)
      return row
    }
    dayRow = row(NSTextField(labelWithString: "Дата"), day)
    _ = row(timeLabel, time)
    for value in ReminderRepeat.allCases {
      repetition.addItem(withTitle: value.title)
      repetition.lastItem?.representedObject = value.rawValue
    }
    repetition.target = self
    repetition.action = #selector(changeRepeat)
    repetition.setAccessibilityLabel("Повтор напоминания")
    _ = row(NSTextField(labelWithString: "Повтор"), repetition)
    hint.font = .systemFont(ofSize: 11)
    hint.textColor = .secondaryLabelColor
    addArrangedSubview(hint)
    hint.widthAnchor.constraint(equalToConstant: 360).isActive = true
    repetition.selectItem(at: ReminderRepeat.allCases.firstIndex(of: repeating)!)
    changeRepeat()

  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  @objc func changeRepeat() {
    let hourly = selectedRepeat == .hourly
    if hourly && previousRepeat != .hourly {
      time.stringValue = time.stringValue.components(separatedBy: ":").last ?? "00"
    } else if !hourly && previousRepeat == .hourly {
      let hour = day.calendar?.component(.hour, from: day.dateValue) ?? 0
      time.stringValue = String(format: "%02d:", hour) + time.stringValue
    }
    previousRepeat = selectedRepeat
    dayRow.isHidden = selectedRepeat == .hourly || selectedRepeat == .daily
    timeLabel.stringValue = hourly ? "Минута" : "Время"
    time.placeholderString = hourly ? "00–59" : "ЧЧ:ММ"
    time.setAccessibilityLabel(hourly ? "Минута каждого часа" : "Время напоминания")
    switch selectedRepeat {
    case .none: hint.stringValue = "Время в 24-часовом формате, например 18:30."
    case .hourly: hint.stringValue = "Каждый час в указанную минуту. Например, 15 — в 12:15, 13:15…"
    case .daily: hint.stringValue = "Каждый день в указанное время, начиная с ближайшего срабатывания."
    case .weekly: hint.stringValue = "Еженедельно в день недели выбранной даты, начиная с ближайшего срабатывания."
    case .monthly: hint.stringValue = "Ежемесячно в выбранный день месяца. Месяцы без этого дня пропускаются."
    }
  }

  func selectedDate(calendar: Calendar = .current, now: Date = Date()) -> Date? {
    let value = time.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = selectedRepeat == .hourly ? "00:" + value : value
    let parts = normalized.split(separator: ":", omittingEmptySubsequences: false)
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
    guard actual.hour == hour && actual.minute == minute else { return nil }
    return selectedRepeat == .none
      ? date : selectedRepeat.nextDate(reference: date, after: now, calendar: calendar)
  }
}
