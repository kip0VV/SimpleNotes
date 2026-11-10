import Cocoa

func runReminderChecks() {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "Asia/Yekaterinburg")!
  let initial = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 18, minute: 45))!
  let input = ReminderDateInput(date: initial, calendar: calendar)
  precondition(input.time.stringValue == "18:45", "Existing reminder uses local 24-hour time")
  for value in ["00:00", "9:05", "23:59", " 18:30 "] {
    input.time.stringValue = value
    precondition(input.selectedDate(calendar: calendar) != nil, "Accept valid time \(value)")
  }
  for value in ["", "24:00", "18:60", "-1:30", "12", "12:3", "12:30:00", "ab:cd", "1e:20"] {
    input.time.stringValue = value
    precondition(input.selectedDate(calendar: calendar) == nil, "Reject malformed time \(value)")
  }
  input.time.stringValue = "07:15"
  let result = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: input.selectedDate(calendar: calendar)!)
  precondition(result.year == 2026 && result.month == 11 && result.day == 10
    && result.hour == 7 && result.minute == 15 && result.second == 0,
    "Combine chosen calendar date and typed time exactly")
  calendar.timeZone = TimeZone(identifier: "America/New_York")!
  input.day.dateValue = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
  input.time.stringValue = "02:30"
  precondition(input.selectedDate(calendar: calendar) == nil, "Reject nonexistent local time during clock change")
  print("Reminder checks passed — editable local time, validation, date combination, daylight-saving gap")
}
