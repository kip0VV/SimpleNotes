import Cocoa
import UserNotifications
import WebKit

func runFullWindowRuntimeChecks(fixture: URL) throws {
  let domain = Bundle.main.bundleIdentifier!
  let defaults = UserDefaults.standard
  let previous = defaults.persistentDomain(forName: domain)
  defaults.removePersistentDomain(forName: domain)
  defer {
    defaults.removePersistentDomain(forName: domain)
    if let previous = previous { defaults.setPersistentDomain(previous, forName: domain) }
  }
  let library = fixture.appendingPathComponent("FullWindow")
  try FileManager.default.createDirectory(at: library.appendingPathComponent("Nested/Child"), withIntermediateDirectories: true)
  let file = library.appendingPathComponent("Formulas.md")
  let math = #"""
  # Формулы и реальные элементы окна

  найти **это слово**, НАЙТИ это слово.

  $a_i^2$, $\sqrt{x}$, $\frac{a}{b}$, $\alpha+\beta$.

  $$\int_0^1 x^2\,dx=\frac{1}{3}$$

  \(\sum_{i=1}^n i\)

  \[
  \begin{pmatrix}1&2\\3&4\end{pmatrix}
  \]

  | Имя | Формула |
  | --- | --- |
  | A | $x_1^2$ |

  - [ ] Реальная задача

  `$не формула$`

  $\unknowncommand{x}$

  **После ошибочной формулы текст остаётся видимым.**
  """#
  try math.write(to: file, atomically: true, encoding: .utf8)
  defaults.set(library.path, forKey: "notesDirectory")
  // Recover an incomplete restored state rather than treating its empty body as loaded.
  defaults.set(file.path, forKey: "draftPath")
  defaults.set(false, forKey: "notificationsEnabled")
  let notes = NotesApp()
  notes.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
  defer {
    notes.currentURL = nil
    notes.reminderListTimer?.invalidate()
    notes.quickSaveTimer?.invalidate()
    notes.hoverTimer?.invalidate()
    notes.previewRenderWork?.cancel()
    notes.indexQueue.cancelAllOperations()
    if let monitor = notes.gestureMonitor { NSEvent.removeMonitor(monitor) }
    if let monitor = notes.actionKeyMonitor { NSEvent.removeMonitor(monitor) }
    notes.window.orderOut(nil)
  }
  func wait(_ condition: () -> Bool, timeout: TimeInterval = 8) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    precondition(condition(), "Full window runtime timeout")
  }
  func js(_ source: String) -> Any? {
    var done = false
    var result: Any?
    var failure: Error?
    notes.preview?.evaluateJavaScript(source) { value, error in result = value; failure = error; done = true }
    wait { done }
    precondition(failure == nil, "Full window JavaScript failed: \(String(describing: failure))")
    return result
  }
  precondition(notes.startupComplete && notes.editor.delegate === notes)
  notes.openNote(file)
  precondition(notes.editor.string == math && notes.loadedContent == math,
               "Opening restored path without a baseline must actually read the file")
  notes.mode.selectedSegment = 1
  notes.changeMode()
  wait { notes.previewReady }
  precondition(js("document.querySelectorAll('#body .katex').length") as? Int == 8)
  precondition(js("document.querySelectorAll('#body .math-error').length === 1 && document.querySelector('#body strong:last-child') !== null && document.querySelector('#body code').textContent.includes('$не формула$')") as? Bool == true)
  let webView = notes.preview!
  let sizes = [NSSize(width: 850, height: 500), NSSize(width: 1060, height: 680), NSSize(width: 1440, height: 900)]
  for (index, size) in sizes.enumerated() {
    notes.window.setContentSize(size)
    notes.window.contentView!.layoutSubtreeIfNeeded()
    notes.setNoteFindExpanded(true)
    notes.noteFindField.stringValue = "найти это слово"
    notes.noteFindChanged()
    wait { notes.noteFindCount == 2 }
    notes.setNoteFindExpanded(false)
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    notes.window.contentView!.layoutSubtreeIfNeeded()
    precondition(notes.preview === webView && webView.bounds.width > 200 && webView.bounds.height > 100)
    precondition(js("document.querySelector('#body h1').getBoundingClientRect().width > 100 && !CSS.highlights.has('note-current') && !CSS.highlights.has('note-matches')") as? Bool == true)
    var snapshot: NSImage?
    var done = false
    webView.takeSnapshot(with: nil) { image, error in precondition(error == nil); snapshot = image; done = true }
    wait { done }
    precondition(snapshot != nil && snapshot!.size.width > 200)
    try snapshot!.tiffRepresentation!.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("full-window-\(index).tiff"))
  }
  // Real JS change event -> WKScriptMessageHandler -> native edit -> atomic disk save.
  _ = js("document.querySelector('#body input').click()")
  wait { (try? String(contentsOf: file, encoding: .utf8))?.contains("- [x] Реальная задача") == true }
  precondition(!notes.dirty && notes.editor.string.contains("- [x] Реальная задача"))
  notes.editor.undo(nil)
  precondition(notes.dirty && notes.editor.string.contains("- [ ] Реальная задача"))
  RunLoop.current.run(until: Date().addingTimeInterval(0.2))
  precondition(js("document.querySelector('#body input').checked === false") as? Bool == true)
  precondition(notes.saveCurrent(preservingExistingFile: true))
  let formulaCount = js("document.querySelectorAll('#body .katex').length") as! Int
  for value in [0.5, 1.0, 2.0] {
    notes.setNoteZoom(value)
    precondition(webView.pageZoom == value)
    precondition(js("document.querySelectorAll('#body .katex').length") as? Int == formulaCount)
  }
  notes.resetZoom()
  for theme in ["light", "dark", "graphite", "system"] {
    defaults.set(theme, forKey: "appearance")
    notes.applyTheme()
    precondition(js("document.querySelectorAll('#body .katex').length") as? Int == formulaCount)
  }
  // Settings controller is real, not replaced with an empty test view.
  notes.showSettings()
  precondition(notes.settingsController?.window?.contentView != nil)
  notes.settingsController?.window?.orderOut(nil)
  notes.dirty = false
  notes.openQuickNote()
  precondition(notes.quickMode && notes.window.frame.width < 600)
  notes.editor.insertText("Быстрая проверка автосохранения 🙂", replacementRange: NSRange(location: 0, length: 0))
  wait { notes.currentURL != nil && !notes.dirty }
  let quickURL = notes.currentURL!
  let quickContent = try String(contentsOf: quickURL, encoding: .utf8)
  precondition(quickContent.contains("Быстрая проверка"))
  wait { (notes.outline.item(atRow: notes.outline.selectedRow) as? NoteNode)?.url == quickURL }
  notes.expandQuickNote()
  precondition(!notes.quickMode && notes.currentURL == quickURL && !notes.dirty)
  notes.openNote(file)
  notes.mode.selectedSegment = 1
  notes.changeMode()
  wait { notes.previewReady }
  // Check actual OS notification capability; do not replace it with a fake scheduler.
  var authorization: UNAuthorizationStatus?
  notes.noteNotifications.getNotificationSettings { settings in authorization = settings.authorizationStatus }
  wait { authorization != nil }
  let notificationReport: String
  if authorization == .authorized || authorization == .provisional {
    let id = "SimpleNotes-runtime-" + UUID().uuidString
    var completed = false
    var schedulingError: Error?
    let date = Date().addingTimeInterval(4)
    notes.scheduleReminder(path: "Formulas.md", record: ["id": id, "time": date.timeIntervalSince1970]) { error in schedulingError = error; completed = true }
    wait { completed }
    precondition(schedulingError == nil)
    var delivered = false
    let deadline = Date().addingTimeInterval(10)
    while !delivered && Date() < deadline {
      var queried = false
      notes.noteNotifications.getDeliveredNotifications { notifications in delivered = notifications.contains { $0.request.identifier == id }; queried = true }
      wait { queried }
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    notificationReport = delivered ? "PASS: actual OS notification delivered" : "UNVERIFIED: scheduled with OS but delivery not observed"
    notes.noteNotifications.removePendingNotificationRequests(withIdentifiers: [id])
    notes.noteNotifications.removeDeliveredNotifications(withIdentifiers: [id])
  } else {
    notificationReport = "UNVERIFIED: actual notification delivery; OS authorization status \(authorization!.rawValue) for isolated test bundle"
  }
  let report = "PASS: actual production window startup, three window sizes, search animation and clearing, mixed valid/invalid formulas, native checkbox bridge and disk save, undo, zoom, themes, settings, timed quick autosave and expansion\n" + notificationReport
  try report.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("full-window-results.txt"), atomically: true, encoding: .utf8)
  print(report)
}
