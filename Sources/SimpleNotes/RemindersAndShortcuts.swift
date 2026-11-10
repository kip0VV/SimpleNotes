import Carbon
import Cocoa
import UserNotifications

final class ShortcutRecorder: NSView {
  var keyCode: UInt32?
  var modifiers: UInt32 = 0
  var serviceCharacter: String?
  var label = "Нажми удобное сочетание клавиш"
  override var acceptsFirstResponder: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    NSColor.controlBackgroundColor.setFill()
    NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.labelColor,
    ]
    let size = label.size(withAttributes: attributes)
    label.draw(
      at: NSPoint(x: max(8, (bounds.width - size.width) / 2), y: (bounds.height - size.height) / 2),
      withAttributes: attributes)
  }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard !event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
      return super.performKeyEquivalent(with: event)
    }
    keyDown(with: event)
    return true
  }
  override func keyDown(with event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard !flags.intersection([.command, .option, .control]).isEmpty else {
      NSSound.beep()
      return
    }
    serviceCharacter =
      NotesApp.shortcutCharacter(keyCode: UInt32(event.keyCode))
      ?? event.characters(byApplyingModifiers: [])?.lowercased()
    keyCode = UInt32(event.keyCode)
    modifiers = 0
    var symbols = ""
    if flags.contains(.control) {
      modifiers |= UInt32(controlKey)
      symbols += "⌃"
    }
    if flags.contains(.option) {
      modifiers |= UInt32(optionKey)
      symbols += "⌥"
    }
    if flags.contains(.shift) {
      modifiers |= UInt32(shiftKey)
      symbols += "⇧"
    }
    if flags.contains(.command) {
      modifiers |= UInt32(cmdKey)
      symbols += "⌘"
    }
    label =
      symbols
      + (["\r": "↩", "\t": "⇥", "\u{1b}": "⎋", "\u{7f}": "⌫", "\u{8}": "⌫", " ": "Пробел"][
        serviceCharacter ?? ""]
        ?? serviceCharacter?.uppercased() ?? "Клавиша \(event.keyCode)")
    needsDisplay = true
  }
}

enum ReminderSchedulingError: LocalizedError {
  case invalidRecord, pastDate

  var errorDescription: String? {
    switch self {
    case .invalidRecord: return "Не удалось прочитать дату напоминания. Выбери дату и время заново."
    case .pastDate: return "Время напоминания уже прошло. Выбери новое время."
    }
  }
}

enum ReminderScheduleResult {
  case saved, ignored, orphaned, failed
}

extension NotesApp: UNUserNotificationCenterDelegate {
  var reminderRecords: [String: [String: Any]] {
    defaults.dictionary(forKey: "reminders") as? [String: [String: Any]] ?? [:]
  }
  var notificationsEnabled: Bool { defaults.bool(forKey: "notificationsEnabled") }

  func prepareRemindersAndShortcut() {
    noteNotifications.delegate = self
    installQuickNoteHandler()
    if let key = defaults.object(forKey: "quickNoteKeyCode") as? UInt32 {
      _ = registerQuickNote(
        key: key, modifiers: UInt32(defaults.integer(forKey: "quickNoteModifiers")))
    }
    if notificationsEnabled { rescheduleReminders() }
  }

  func suspendQuickNoteHotkey() {
    if let key = quickHotKey {
      UnregisterEventHotKey(key)
      quickHotKey = nil
    }
  }
  func restoreQuickNoteHotkey() {
    if quickHotKey == nil, let code = defaults.object(forKey: "quickNoteKeyCode") as? UInt32 {
      _ = registerQuickNote(
        key: code, modifiers: UInt32(defaults.integer(forKey: "quickNoteModifiers")))
    }
  }
  @objc func configureQuickNoteShortcut() {
    suspendQuickNoteHotkey()
    defer { restoreQuickNoteHotkey() }
    let alert = NSAlert()
    alert.messageText = "Горячая клавиша быстрой заметки"
    alert.informativeText =
      "Системная команда откроет SimpleNotes и создаст заметку даже после полного выхода из приложения. В самом SimpleNotes также доступно ⌘N."
    let recorder = ShortcutRecorder(frame: NSRect(x: 0, y: 0, width: 380, height: 54))
    alert.accessoryView = recorder
    alert.addButton(withTitle: "Назначить")
    alert.addButton(withTitle: "Отмена")
    alert.addButton(withTitle: "Сбросить")
    alert.window.initialFirstResponder = recorder
    let result = alert.runModal()
    if result == .alertThirdButtonReturn {
      if let key = quickHotKey {
        UnregisterEventHotKey(key)
        quickHotKey = nil
      }
      setQuickNoteServiceShortcut(nil)
      for name in [
        "quickNoteKeyCode", "quickNoteModifiers", "quickNoteLabel", "quickNoteServiceCharacter",
      ] {
        defaults.removeObject(forKey: name)
      }
      return
    }
    guard result == .alertFirstButtonReturn, let code = recorder.keyCode else { return }
    guard let character = recorder.serviceCharacter, character.count == 1,
      character.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) })
    else {
      showError("Для системной команды выбери сочетание с буквой или цифрой.")
      return
    }
    if let conflict = shortcutConflict(
      key: character, modifiers: eventModifiers(recorder.modifiers), excluding: "global")
    {
      showError("Это сочетание используется для «\(conflict)».")
      return
    }
    guard registerQuickNote(key: code, modifiers: recorder.modifiers) else {
      showError("Это сочетание уже используется. Выбери другое.")
      return
    }
    defaults.set(character, forKey: "quickNoteServiceCharacter")
    setQuickNoteServiceShortcut(
      serviceKeyEquivalent(character: character, modifiers: recorder.modifiers))
    defaults.set(code, forKey: "quickNoteKeyCode")
    defaults.set(recorder.modifiers, forKey: "quickNoteModifiers")
    defaults.set(recorder.label, forKey: "quickNoteLabel")
  }

  func installQuickNoteHandler() {
    var type = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, context in
        guard let context = context else { return OSStatus(eventNotHandledErr) }
        let owner = Unmanaged<NotesApp>.fromOpaque(context).takeUnretainedValue()
        DispatchQueue.main.async {
          owner.openQuickNote()
        }
        return noErr
      }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &quickHotKeyHandler)
  }

  func registerQuickNote(key: UInt32, modifiers: UInt32) -> Bool {
    if quickHotKey != nil && key == UInt32(defaults.integer(forKey: "quickNoteKeyCode"))
      && modifiers == UInt32(defaults.integer(forKey: "quickNoteModifiers"))
    {
      return true
    }
    var reference: EventHotKeyRef?
    let identifier = EventHotKeyID(signature: 0x534E_4F54, id: 1)
    guard
      RegisterEventHotKey(key, modifiers, identifier, GetApplicationEventTarget(), 0, &reference)
        == noErr
    else { return false }
    if let old = quickHotKey { UnregisterEventHotKey(old) }
    quickHotKey = reference
    return true
  }

  func enableNotifications(_ completion: @escaping (Bool) -> Void) {
    noteNotifications.requestAuthorization(options: [.alert, .sound]) {
      [weak self] granted, error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.defaults.set(granted, forKey: "notificationsEnabled")
        self.refreshReminderList()
        if !granted {
          self.showError(
            error?.localizedDescription
              ?? "Разреши уведомления для SimpleNotes в системных настройках macOS → Уведомления.")
        }
        completion(granted)
      }
    }
  }

  @objc func toggleNotifications() {
    if notificationsEnabled {
      defaults.set(false, forKey: "notificationsEnabled")
      refreshReminderList()
      noteNotifications.removeAllPendingNotificationRequests()
      noteNotifications.removeAllDeliveredNotifications()
    } else {
      enableNotifications { [weak self] granted in if granted { self?.rescheduleReminders() } }
    }
  }

  @objc func contextReminder(_ sender: NSMenuItem) {
    guard let url = contextURL(sender) else { return }
    let alert = NSAlert()
    alert.messageText = "Напомнить о заметке"
    alert.informativeText = url.deletingPathExtension().lastPathComponent
    let savedTime = reminderRecords[relativePath(url)]?["time"] as? Double
    let previous = savedTime.map { Date(timeIntervalSince1970: $0) }
    let repeating = ReminderRepeat(
      rawValue: reminderRecords[relativePath(url)]?["repeat"] as? String ?? "") ?? .none
    let initial = previous.flatMap { repeating != .none || $0 > Date() ? $0 : nil }
      ?? Date().addingTimeInterval(3600)
    let input = ReminderDateInput(date: initial, repeating: repeating)
    alert.accessoryView = input
    alert.addButton(withTitle: "Напомнить")
    alert.addButton(withTitle: "Отмена")
    alert.window.initialFirstResponder = input.time
    var date: Date
    while true {
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      guard alert.window.makeFirstResponder(nil), let selected = input.selectedDate() else {
        showError(input.selectedRepeat == .hourly
          ? "Введи минуту каждого часа двумя цифрами от 00 до 59."
          : "Введи время в формате ЧЧ:ММ, например 18:30.")
        continue
      }
      guard selected > Date() else {
        showError("Выбери дату и время в будущем.")
        continue
      }
      date = selected
      break
    }
    let library = root
    let schedule = { [weak self] in
      guard let self = self, self.root == library,
        FileManager.default.fileExists(atPath: url.path)
      else { return }
      self.saveReminder(for: url, at: date, repeating: input.selectedRepeat)
    }
    if notificationsEnabled {
      schedule()
    } else {
      enableNotifications { granted in if granted { schedule() } }
    }
  }

  func saveReminder(for url: URL, at date: Date, repeating: ReminderRepeat = .none) {
    let path = relativePath(url)
    var records = reminderRecords
    let previous = records[path]
    let identifier = previous?["id"] as? String ?? UUID().uuidString
    let record: [String: Any] = [
      "id": identifier, "time": date.timeIntervalSince1970, "repeat": repeating.rawValue,
      "revision": UUID().uuidString,
    ]
    let library = root
    records[path] = record
    defaults.set(records, forKey: "reminders")
    scheduleReminder(path: path, record: record) { [weak self] error in
      guard let self = self else { return }
      let result = self.finishReminderSchedule(
        path: path, library: library, record: record, previous: previous, error: error)
      if result == .orphaned {
        self.noteNotifications.removePendingNotificationRequests(withIdentifiers: [identifier])
      } else if result == .failed, let error = error {
        self.showError(error.localizedDescription)
      }
    }
  }

  func finishReminderSchedule(
    path: String, library: URL, record: [String: Any], previous: [String: Any]?, error: Error?
  ) -> ReminderScheduleResult {
    var latest = reminderRecords
    guard let identifier = record["id"] as? String else { return .ignored }
    guard root == library, let revision = record["revision"] as? String,
      latest[path]?["id"] as? String == identifier,
      latest[path]?["revision"] as? String == revision
    else {
      // A renamed note keeps its notification identifier under a new path.
      let stillUsed = latest.values.contains { $0["id"] as? String == identifier }
      return stillUsed ? .ignored : .orphaned
    }
    if error != nil {
      latest[path] = previous
      defaults.set(latest, forKey: "reminders")
      refreshReminderList()
      return .failed
    }
    guard notificationsEnabled else { return .orphaned }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    if let time = record["time"] as? Double {
      status.stringValue = "Напоминание — " + formatter.string(from: Date(timeIntervalSince1970: time))
    }
    refreshReminderList()
    return .saved
  }

  func scheduleReminder(
    path: String, record: [String: Any], completion: @escaping (Error?) -> Void = { _ in }
  ) {
    guard let identifier = record["id"] as? String, let time = record["time"] as? Double, time.isFinite else {
      completion(ReminderSchedulingError.invalidRecord)
      return
    }
    let date = Date(timeIntervalSince1970: time)
    let repeating = ReminderRepeat(rawValue: record["repeat"] as? String ?? "") ?? .none
    guard repeating != .none || date > Date() else {
      completion(ReminderSchedulingError.pastDate)
      return
    }
    let content = UNMutableNotificationContent()
    content.title = root.appendingPathComponent(path).deletingPathExtension().lastPathComponent
    content.body = "Пора вернуться к заметке."
    content.sound = .default
    content.userInfo = ["notePath": path, "notesDirectory": root.path]
    let trigger = repeating.trigger(for: date)
    noteNotifications.add(
      UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    ) { error in DispatchQueue.main.async { completion(error) } }
  }

  func rescheduleReminders() {
    for (path, record) in reminderRecords
    where FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) {
      scheduleReminder(path: path, record: record)
    }
  }

  @objc func contextCancelReminder(_ sender: NSMenuItem) {
    guard let url = contextURL(sender) else { return }
    cancelReminders(in: url)
    status.stringValue = "Напоминание отменено"
  }

  func cancelReminders(in url: URL) {
    let prefix = relativePath(url)
    var records = reminderRecords
    var identifiers: [String] = []
    for key in Array(records.keys) where key == prefix || key.hasPrefix(prefix + "/") {
      if let identifier = records[key]?["id"] as? String { identifiers.append(identifier) }
      records.removeValue(forKey: key)
    }
    noteNotifications.removePendingNotificationRequests(withIdentifiers: identifiers)
    noteNotifications.removeDeliveredNotifications(withIdentifiers: identifiers)
    defaults.set(records, forKey: "reminders")
    refreshReminderList()
  }

  func remapReminders(from source: URL, to target: URL) {
    guard source != target else { return }
    let old = relativePath(source)
    let new = relativePath(target)
    var records = reminderRecords
    for key in Array(records.keys) where key == old || key.hasPrefix(old + "/") {
      let updated = new + key.dropFirst(old.count)
      records[updated] = records.removeValue(forKey: key)
      if notificationsEnabled, let record = records[updated] {
        scheduleReminder(path: updated, record: record)
      }
    }
    defaults.set(records, forKey: "reminders")
    refreshReminderList()
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    DispatchQueue.main.async { [weak self] in self?.refreshReminderList() }
    completionHandler([.banner, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let info = response.notification.request.content.userInfo
    DispatchQueue.main.async { [weak self] in
      defer { completionHandler() }
      guard let self = self, let path = info["notePath"] as? String,
        let folder = info["notesDirectory"] as? String
      else { return }
      let url = URL(fileURLWithPath: folder).appendingPathComponent(path)
      self.showWindow()
      if folder == self.root.path {
        self.openNote(url)
      } else {
        NSWorkspace.shared.activateFileViewerSelecting([url])
      }
    }
  }
}
