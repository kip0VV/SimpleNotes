import Cocoa

func runReminderListChecks(notes: NotesApp, fixture: URL) throws {
  let calendar = Calendar.current
  let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 11, minute: 5))!
  let reference = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 18, minute: 30))!
  for (repetition, hour, day) in [(ReminderRepeat.hourly, 11, 10), (.daily, 18, 10), (.weekly, 18, 10), (.monthly, 18, 10)] {
    let next = repetition.nextDate(reference: reference, after: now)!
    let parts = calendar.dateComponents([.day, .hour, .minute], from: next)
    precondition(parts.day == day && parts.hour == hour && parts.minute == 30,
                 "Next recurrence for \(repetition)")
    precondition(repetition.trigger(for: reference).repeats, "Native repeating notification persists after quit")
  }
  precondition(!ReminderRepeat.none.trigger(for: reference).repeats, "Legacy reminder stays one-shot")
  precondition(ReminderRepeat.none.nextDate(reference: now, after: now) == nil, "Expired single reminder disappears")
  let later = calendar.date(byAdding: .hour, value: 9, to: now)!
  let nextDay = ReminderRepeat.daily.nextDate(reference: reference, after: later)!
  precondition(calendar.component(.day, from: nextDay) == 11, "Daily repeat advances after today fires")
  let monthEnd = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 8))!
  let february = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
  precondition(calendar.component(.month, from: ReminderRepeat.monthly.nextDate(reference: monthEnd, after: february)!) == 3,
               "Monthly repeats skip months without the requested day")
  let input = ReminderDateInput(date: reference)
  input.repetition.selectItem(at: 1)
  input.changeRepeat()
  precondition(input.selectedRepeat == .hourly && input.time.stringValue == "30" && input.dayRow.isHidden,
               "Hourly input asks only for a minute")
  precondition(input.selectedDate(now: now) == ReminderRepeat.hourly.nextDate(reference: reference, after: now),
               "Hourly input picks nearest matching time")
  input.time.stringValue = "99"
  precondition(input.selectedDate(now: now) == nil, "Hourly minute validation")
  input.time.stringValue = "15"
  input.repetition.selectItem(at: 2)
  input.changeRepeat()
  precondition(input.time.stringValue == "18:15" && input.selectedRepeat == .daily,
               "Returning from hourly restores hour and preserves minute")

  notes.root = fixture
  let file = fixture.appendingPathComponent("Reminder target.md")
  try "Plain reminder note".write(to: file, atomically: true, encoding: .utf8)
  notes.defaults.set(true, forKey: "notificationsEnabled")
  notes.defaults.set([
    "Reminder target.md": ["id": "repeat", "time": reference.timeIntervalSince1970, "repeat": "hourly"],
    "Missing.md": ["id": "missing", "time": reference.timeIntervalSince1970],
    "../outside.md": ["id": "outside", "time": reference.timeIntervalSince1970],
  ], forKey: "reminders")
  let active = notes.activeReminders(now: later)
  precondition(active.count == 1 && active[0].path == "Reminder target.md" && active[0].date > later,
               "Active list excludes missing files and keeps recurring reminders after initial date")
  notes.defaults.set(false, forKey: "notificationsEnabled")
  precondition(notes.activeReminders(now: now).isEmpty, "Disabled notifications have no active reminders")
  let panel = notes.makeReminderList()
  precondition(notes.reminderHeading.stringValue == "Напоминания · 0" && notes.reminderListHeight?.constant == 22,
               "Empty list remains compact")
  notes.defaults.set(true, forKey: "notificationsEnabled")
  notes.refreshReminderList()
  precondition(notes.reminderList.arrangedSubviews.count == 1 && notes.reminderListHeight?.constant == 48,
               "One reminder produces one compact row")
  let row = notes.reminderList.arrangedSubviews[0] as! NSStackView
  let open = row.arrangedSubviews[0] as! NSButton
  let menu = row.arrangedSubviews[1] as! NSPopUpButton
  precondition(menu.itemArray.count == 3 && open.attributedTitle.string.contains("Каждый час"),
               "List has repeat description, edit and cancellation actions")
  notes.dirty = false
  notes.openListedReminder(open)
  precondition(notes.currentURL?.path == file.path && notes.editor.string == "Plain reminder note",
               "Clicking reminder opens its note")
  notes.cancelReminders(in: file)
  precondition(notes.reminderHeading.stringValue == "Напоминания · 0", "Cancellation refreshes list immediately")
  notes.reminderListTimer?.invalidate()
  notes.defaults.set(false, forKey: "notificationsEnabled")
  _ = panel
  print("Reminder list checks passed — all repeat modes, native repeat triggers, next dates, legacy data, list rows, open/edit/cancel, disabled/expired states")
}
