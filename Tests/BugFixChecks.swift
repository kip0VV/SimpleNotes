import Cocoa

func runBugFixChecks(notes: NotesApp, fixture: URL) throws {
  let fm = FileManager.default
  let library = fixture.appendingPathComponent("BugFixes")
  let other = fixture.appendingPathComponent("OtherBugFixes")
  try fm.createDirectory(at: library.appendingPathComponent("A"), withIntermediateDirectories: true)
  try fm.createDirectory(at: other.appendingPathComponent("B"), withIntermediateDirectories: true)
  notes.root = library
  notes.dirty = false
  notes.resetNoteForWriting()
  notes.refreshTopics(select: "")
  notes.openQuickNote()
  notes.editor.string = "К"
  notes.textDidChange(Notification(name: NSText.didChangeNotification))
  notes.flushQuickSave()
  let earlyURL = notes.currentURL!
  precondition(earlyURL.lastPathComponent == "К.md")
  notes.editor.string = "Купить продукты"
  notes.textDidChange(Notification(name: NSText.didChangeNotification))
  notes.flushQuickSave()
  precondition(notes.titleField.stringValue == "Купить продукты"
    && notes.currentURL!.lastPathComponent == "Купить продукты.md"
    && !fm.fileExists(atPath: earlyURL.path), "Automatic title follows first line after initial save")
  let collision = library.appendingPathComponent("Купить продукты завтра.md")
  try "Do not overwrite".write(to: collision, atomically: true, encoding: .utf8)
  notes.editor.string = "Купить продукты завтра"
  notes.textDidChange(Notification(name: NSText.didChangeNotification))
  notes.flushQuickSave()
  precondition(notes.currentURL!.lastPathComponent == "Купить продукты завтра (2).md"
    && (try! String(contentsOf: collision, encoding: .utf8)) == "Do not overwrite",
    "Automatic retitle respects existing files")
  notes.expandQuickNote()
  notes.titleField.stringValue = "Моё название"
  notes.editor.string = "Другой текст"
  notes.dirty = true
  precondition(notes.saveCurrent() && notes.titleField.stringValue == "Моё название",
    "Normal editor keeps a manual title")

  notes.openQuickNote()
  notes.quickTopics.selectItem(withTitle: "A")
  notes.selectQuickTopic()
  notes.flushQuickSave()
  precondition(notes.quickStatus.stringValue == "Сохраняется автоматически"
    && notes.quickSaveTimer == nil && notes.currentURL == nil,
    "Choosing a folder for an empty capture does not claim to be saving")
  notes.root = other
  notes.refreshTopics(select: "")
  precondition(notes.quickTopics.itemTitles == notes.topics.itemTitles
    && !notes.quickTopics.itemTitles.contains("A") && notes.quickTopics.itemTitles.contains("B"),
    "Refreshing library topics synchronizes the visible quick picker")
  notes.quickTopics.selectItem(withTitle: "B")
  notes.selectQuickTopic()
  notes.editor.string = "Запись в новой библиотеке"
  notes.textDidChange(Notification(name: NSText.didChangeNotification))
  notes.flushQuickSave()
  precondition(notes.currentURL!.deletingLastPathComponent().standardizedFileURL
    == other.appendingPathComponent("B").standardizedFileURL,
    "Visible quick folder matches actual save destination")
  notes.expandQuickNote()

  let text = "План\nВступление\nТема — поездка\nСписок вещей"
  for ext in ["txt", "md"] {
    let url = other.appendingPathComponent("plain.\(ext)")
    try text.write(to: url, atomically: true, encoding: .utf8)
    notes.loadNote(text, url: url)
    precondition(notes.editor.string == text && notes.noteDate.isEmpty,
      "An ordinary topic line is not enough to recognize app metadata")
    precondition(notes.contentWithTitle("Renamed", content: text) == text,
      "Renaming plain text must not alter its first line")
    notes.editor.string += "\nДополнение"
    notes.dirty = true
    precondition(notes.saveCurrent(), "Plain text saves from the normal editor")
    precondition((try! String(contentsOf: url, encoding: .utf8)) == text + "\nДополнение",
      "Saving an imported file preserves plain text without injecting metadata")
    var scanner = NoteIndexScanner(root: other, order: [:], cache: [:])
    let tree = try scanner.scan()
    precondition(tree.first(where: { $0.url.lastPathComponent == url.lastPathComponent })?.searchBody
      == text + "\nДополнение", "Search indexes all lines of ordinary files")
  }
  for separator in ["\n\n", "\n"] {
    let legacy = "Заметка\n10.11.2026 12:00\nТема — B" + separator + "Текст"
    notes.loadNote(legacy, url: other.appendingPathComponent("legacy.md"))
    precondition(notes.editor.string == "Текст" && notes.titleField.stringValue == "Заметка",
      "Previously saved app headers remain readable")
  }
  precondition(!NoteMetadata.hasHeader(["План", "31.02.2026 12:00", "Тема — X", "Текст"]),
    "Invalid dates cannot turn plain text into metadata")
  notes.dirty = false
  print("Bug fix checks passed — quick folders, automatic titles, idle status, plain text preservation and legacy metadata")
}
