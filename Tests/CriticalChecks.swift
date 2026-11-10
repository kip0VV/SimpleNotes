import Cocoa

func runCriticalChecks(notes: NotesApp, fixture: URL) throws {
  notes.root = fixture
  notes.defaults.set(true, forKey: "notificationsEnabled")
  let date = Date().addingTimeInterval(3600).timeIntervalSince1970
  let first: [String: Any] = ["id": "notification-1", "time": date, "repeat": "daily", "revision": "first"]
  let second: [String: Any] = ["id": "notification-1", "time": date, "repeat": "daily", "revision": "second"]
  let failure = NSError(domain: "Test", code: 1)

  // A pending add completes after the note was renamed. Its identifier is still in use.
  notes.defaults.set(["Renamed.md": first], forKey: "reminders")
  precondition(notes.finishReminderSchedule(
    path: "Original.md", library: fixture, record: first, previous: nil, error: nil) == .ignored,
    "Late completion must not cancel the notification of a moved note")

  // An older edit fails after a newer edit of the same time already succeeded.
  notes.defaults.set(["Note.md": second], forKey: "reminders")
  precondition(notes.finishReminderSchedule(
    path: "Note.md", library: fixture, record: first, previous: nil, error: failure) == .ignored,
    "Older failed request must not roll back a newer identical-time edit")
  precondition(notes.reminderRecords["Note.md"]?["revision"] as? String == "second")

  // Cancel, then create a new reminder for exactly the same time.
  var recreated = second
  recreated["id"] = "notification-2"
  notes.defaults.set(["Note.md": recreated], forKey: "reminders")
  precondition(notes.finishReminderSchedule(
    path: "Note.md", library: fixture, record: first, previous: nil, error: failure) == .orphaned,
    "Cancelled request can clean up only its old identifier")
  precondition(notes.reminderRecords["Note.md"]?["id"] as? String == "notification-2")

  notes.defaults.set(["Note.md": first], forKey: "reminders")
  notes.root = fixture.appendingPathComponent("OtherLibrary")
  notes.defaults.removeObject(forKey: "reminders")
  precondition(notes.finishReminderSchedule(
    path: "Note.md", library: fixture, record: first, previous: nil, error: failure) == .orphaned,
    "Completion from previous library must not restore its data")
  precondition(notes.reminderRecords.isEmpty)
  notes.root = fixture
  notes.defaults.set(["Note.md": second], forKey: "reminders")
  precondition(notes.finishReminderSchedule(
    path: "Note.md", library: fixture, record: second, previous: first, error: failure) == .failed)
  precondition(notes.reminderRecords["Note.md"]?["revision"] as? String == "first",
               "Current request failure restores the previous reminder")
  notes.defaults.set(["Note.md": second], forKey: "reminders")
  precondition(notes.finishReminderSchedule(
    path: "Note.md", library: fixture, record: second, previous: first, error: nil) == .saved,
    "The latest successful request remains saved")
  precondition(notes.reminderRecords["Note.md"]?["revision"] as? String == "second")
  notes.defaults.set(false, forKey: "notificationsEnabled")
  precondition(notes.finishReminderSchedule(
    path: "Note.md", library: fixture, record: second, previous: first, error: nil) == .orphaned,
    "Disabling notifications while adding prevents a pending notification")

  var rejectedPast = false
  notes.scheduleReminder(path: "Note.md", record: ["id": "past", "time": Date().addingTimeInterval(-1).timeIntervalSince1970]) {
    rejectedPast = $0 != nil
  }
  precondition(rejectedPast, "Past date must complete with an error, not silently abandon the request")
  var rejectedInvalid = false
  notes.scheduleReminder(path: "Note.md", record: ["id": "bad", "time": Double.nan]) {
    rejectedInvalid = $0 != nil
  }
  precondition(rejectedInvalid, "Invalid record must complete with an error")
  // The same file can have two equivalent URLs with different percent encoding.
  let file = fixture.appendingPathComponent("Alias note.md")
  try "- [ ] Original".write(to: file, atomically: true, encoding: .utf8)
  let encoded = URL(string: file.absoluteString.replacingOccurrences(of: "Alias", with: "%41lias"))!
  precondition(encoded != encoded.deletingLastPathComponent().appendingPathComponent(encoded.lastPathComponent),
               "Fixture must exercise different URL spellings of the same file")
  notes.loadNote("- [ ] Original", url: encoded)
  notes.editor.string = "- [x] Original"
  notes.dirty = true
  precondition(notes.saveCurrent(preservingExistingFile: true),
               "Preserving an encoded file URL must finish without a filename retry loop")
  precondition(try! String(contentsOf: file, encoding: .utf8) == "- [x] Original")
  precondition(notes.currentURL == encoded && !notes.dirty, "Task save preserves original identity")
  let stressRoot = fixture.appendingPathComponent("ActiveReminderStress", isDirectory: true)
  try FileManager.default.createDirectory(at: stressRoot, withIntermediateDirectories: true)
  var stressRecords: [String: [String: Any]] = [:]
  let reference = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 18))!
  for index in 0..<1000 {
    let path = "Note \(index).md"
    try "Test".write(to: stressRoot.appendingPathComponent(path), atomically: true, encoding: .utf8)
    stressRecords[path] = ["id": "stress-\(index)", "time": reference.timeIntervalSince1970, "repeat": "monthly"]
  }
  notes.root = stressRoot
  notes.defaults.set(true, forKey: "notificationsEnabled")
  notes.defaults.set(stressRecords, forKey: "reminders")
  let start = Date()
  let active = notes.activeReminders()
  precondition(active.count == 1000 && active.allSatisfy { $0.date > start },
               "Calculate active dates for a thousand real reminder files")
  print("1000 active monthly reminder records calculated in \(String(format: "%.3f", Date().timeIntervalSince(start))) seconds")
  notes.refreshReminderList()
  precondition(notes.reminderList.arrangedSubviews.count == 3, "Stress data does not create a thousand sidebar views")
  notes.root = fixture
  notes.defaults.set(false, forKey: "notificationsEnabled")
  notes.defaults.removeObject(forKey: "reminders")
  print("Critical checks passed — delayed callbacks, rename/edit/cancel races, library change, rollback, past/invalid time, encoded URL save")
}
