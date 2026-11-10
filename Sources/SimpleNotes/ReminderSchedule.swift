import Foundation
import UserNotifications

enum ReminderRepeat: String, CaseIterable {
  case none, hourly, daily, weekly, monthly

  var title: String {
    switch self {
    case .none: return "Без повтора"
    case .hourly: return "Каждый час"
    case .daily: return "Каждый день"
    case .weekly: return "Каждую неделю"
    case .monthly: return "Каждый месяц"
    }
  }

  func components(for date: Date, calendar: Calendar) -> DateComponents {
    let fields: Set<Calendar.Component>
    switch self {
    case .none: fields = [.year, .month, .day, .hour, .minute, .second]
    case .hourly: fields = [.minute, .second]
    case .daily: fields = [.hour, .minute, .second]
    case .weekly: fields = [.weekday, .hour, .minute, .second]
    case .monthly: fields = [.day, .hour, .minute, .second]
    }
    var result = calendar.dateComponents(fields, from: date)
    if self != .none { result.second = 0 }
    return result
  }

  func nextDate(reference: Date, after now: Date, calendar: Calendar = .current) -> Date? {
    if self == .none { return reference > now ? reference : nil }
    return calendar.nextDate(
      after: now, matching: components(for: reference, calendar: calendar), matchingPolicy: .strict)
  }

  func trigger(for date: Date, calendar: Calendar = .current) -> UNCalendarNotificationTrigger {
    UNCalendarNotificationTrigger(
      dateMatching: components(for: date, calendar: calendar), repeats: self != .none)
  }
}

struct ActiveReminder {
  let path: String
  let date: Date
  let repetition: ReminderRepeat
}
