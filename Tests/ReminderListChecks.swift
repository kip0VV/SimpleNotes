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

func runManyRemindersChecks(notes: NotesApp, fixture: URL) throws {
  let controller = RemindersWindowController(app: notes)
  let calendar = Calendar.current
  let start = calendar.startOfDay(for: Date())
  let now = start.addingTimeInterval(60)
  let reminders = (0..<1000).map { index in
    ActiveReminder(
      path: (index < 300 ? "Café/" : "Работа/") + "Запись \(index).md",
      date: start.addingTimeInterval(index < 500 ? 3600 : 8 * 86400),
      repetition: index.isMultiple(of: 2) ? .daily : .none)
  }
  controller.refresh(reminders)
  precondition(controller.displayed.count == 1000 && controller.table.numberOfRows == 1000,
               "Full manager supports a thousand rows")
  precondition(!controller.openButton.isEnabled && !controller.editButton.isEnabled,
               "Unselected actions stay disabled")
  controller.filter.selectedSegment = 1
  controller.applyFilter(now: now)
  precondition(controller.displayed.count == 500, "Today filter")
  controller.filter.selectedSegment = 2
  controller.applyFilter(now: now)
  precondition(controller.displayed.count == 500, "Next seven days filter")
  controller.filter.selectedSegment = 3
  controller.applyFilter(now: now)
  precondition(controller.displayed.count == 500 && controller.displayed.allSatisfy { $0.repetition == .daily },
               "Repeating-only filter")
  controller.filter.selectedSegment = 0
  controller.search.stringValue = "CAFE"
  controller.applyFilter(now: now)
  precondition(controller.displayed.count == 300, "Case and accent-insensitive folder search")
  controller.search.stringValue = "Запись 999"
  controller.applyFilter(now: now)
  precondition(controller.displayed.count == 1 && controller.displayed[0].path == "Работа/Запись 999.md",
               "Find a reminder deep in a long list")
  controller.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  precondition(controller.editButton.isEnabled && controller.cancelButton.isEnabled, "Selection enables actions")
  controller.search.stringValue = ""
  controller.sort.selectItem(at: 1)
  controller.applyFilter(now: now)
  precondition(controller.selectedReminder?.path == "Работа/Запись 999.md", "Sort preserves selected reminder identity")
  precondition(controller.displayed.first?.path == "Café/Запись 0.md", "Natural name sorting")
  controller.search.stringValue = "no such reminder"
  controller.applyFilter(now: now)
  precondition(controller.displayed.isEmpty && controller.count.stringValue == "Ничего не найдено"
    && !controller.cancelButton.isEnabled, "Empty results have no stale actionable selection")

  notes.root = fixture
  notes.defaults.set(true, forKey: "notificationsEnabled")
  var records: [String: [String: Any]] = [:]
  for index in 0..<24 {
    let name = "Many reminder \(index).md"
    try "Test note \(index)".write(to: fixture.appendingPathComponent(name), atomically: true, encoding: .utf8)
    records[name] = ["id": "many-\(index)", "time": Date().addingTimeInterval(Double(index + 1) * 3600).timeIntervalSince1970]
  }
  notes.defaults.set(records, forKey: "reminders")
  notes.refreshReminderList()
  precondition(notes.reminderHeading.stringValue == "Напоминания · 24"
    && notes.reminderList.arrangedSubviews.count == 3, "Sidebar renders only three nearest reminders")
  precondition(notes.allRemindersButton.action == #selector(NotesApp.showAllReminders), "All button opens manager")
  controller.search.stringValue = ""
  controller.filter.selectedSegment = 0
  controller.refresh(notes.activeReminders())
  controller.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  let selected = controller.selectedReminder!.path
  notes.dirty = false
  controller.openSelected()
  precondition(notes.currentURL?.lastPathComponent == selected, "Manager opens selected note")
  controller.cancelSelected()
  precondition(notes.reminderRecords[selected] == nil && controller.displayed.count == 23,
               "Manager cancellation targets only the selected reminder")
  controller.refresh([])
  precondition(controller.displayed.isEmpty && !controller.openButton.isEnabled,
               "Library change clears old manager selection")
  notes.defaults.set(false, forKey: "notificationsEnabled")
  notes.defaults.removeObject(forKey: "reminders")
  notes.refreshReminderList()
  print("Large reminder manager checks passed — 1000 rows, date/repeat filters, search, sort, stable selection, sidebar cap, open/cancel")
}
