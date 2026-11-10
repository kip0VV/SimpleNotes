import Carbon
import Cocoa
import WebKit

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message)
}

private func waitForIndex(_ notes: NotesApp) {
  notes.indexQueue.waitUntilAllOperationsAreFinished()
  RunLoop.current.run(until: Date().addingTimeInterval(0.08))
}

func runFeatureChecks(notes: NotesApp, fixture: URL) throws {
  let fm = FileManager.default
  let library = fixture.appendingPathComponent("Features", isDirectory: true)
  try fm.createDirectory(at: library, withIntermediateDirectories: true)
  notes.root = library
  notes.currentURL = nil
  notes.loadedContent = nil
  notes.dirty = false
  notes.searchField.stringValue = ""
  notes.mode.selectedSegment = 0
  notes.defaults.removeObject(forKey: "treeOrder")
  notes.defaults.removeObject(forKey: "collapsedFolders")
  let school = notes.root.appendingPathComponent("Учёба", isDirectory: true)
  let nested = school.appendingPathComponent("ДЗ", isDirectory: true)
  let other = notes.root.appendingPathComponent("Разное", isDirectory: true)
  try fm.createDirectory(at: nested, withIntermediateDirectories: true)
  try fm.createDirectory(at: other, withIntermediateDirectories: true)
  notes.refreshTopics(select: "Учёба/ДЗ")
  expect(notes.selectedTopicPath == "Учёба/ДЗ", "Nested topic selection")
  expect(notes.topics.itemArray.compactMap { $0.representedObject as? String }.contains("Разное"),
         "Folder enumeration includes new topics")
  notes.titleField.stringValue = "Физика"
  notes.editor.string = "Первая строка\nЭлектричество и ток\nэлектричество снова"
  notes.dirty = true
  expect(notes.saveCurrent(), "New note saves successfully")
  let saved = notes.currentURL!
  expect(saved.lastPathComponent == "Физика.md", "Filename contains title without date")
  expect(saved.deletingLastPathComponent().path == nested.path, "Save selected topic")
  let original = try String(contentsOf: saved, encoding: .utf8)
  expect(original.hasPrefix("Физика\n") && original.contains("Тема — Учёба/ДЗ\n\n"),
         "Title, date, topic and body persisted")
  expect(!notes.noteDate.isEmpty && !notes.dirty, "Save clears dirty state and assigns date")
  let date = notes.noteDate
  notes.editor.string += "\nДополнение"
  notes.dirty = true
  expect(notes.saveCurrent() && notes.currentURL == saved && notes.noteDate == date,
         "Update overwrites current note and keeps creation date")
  notes.newNote()
  notes.titleField.stringValue = "Физика"
  notes.editor.string = "Другая запись"
  expect(notes.saveCurrent(), "Duplicate title saves")
  expect(notes.currentURL?.lastPathComponent == "Физика (2).md", "Title collision creates numbered file")
  expect(try! String(contentsOf: saved, encoding: .utf8) != notes.loadedContent,
         "Collision leaves original note untouched")
  notes.dirty = false
  notes.openNote(saved)
  expect(notes.editor.string.contains("Дополнение") && notes.titleField.stringValue == "Физика",
         "Opening parses generated metadata")
  expect(notes.selectedTopicPath == "Учёба/ДЗ", "Opening selects real folder")

  notes.titleField.stringValue = "Новый заголовок"
  notes.dirty = true
  expect(notes.saveCurrent(), "Retitle via editor saves")
  let renamed = notes.currentURL!
  expect(renamed.lastPathComponent == "Новый заголовок.md" && !fm.fileExists(atPath: saved.path),
         "Retitle removes previous filename")
  notes.persistDraft()
  expect(notes.defaults.string(forKey: "draftBaseline") == notes.loadedContent,
         "Draft tracks external-change baseline")
  notes.editor.string += "\nЧерновик"
  notes.textDidChange(Notification(name: NSText.didChangeNotification))
  expect(notes.defaults.bool(forKey: "draftDirty") && notes.defaults.string(forKey: "draftBody") == notes.editor.string,
         "Draft persists edit immediately")
  notes.currentURL = nil
  notes.loadedContent = nil
  notes.dirty = false
  notes.restoreEditingState()
  expect(notes.currentURL == renamed && notes.dirty, "Draft restores saved-note identity and unsaved flag")
  notes.dirty = false
  notes.openNote(renamed)
  notes.loadNote(try String(contentsOf: renamed, encoding: .utf8), url: renamed)

  // Imported extensions and hidden/symlink/app entries.
  let txt = other.appendingPathComponent("Текст.txt")
  let markdown = other.appendingPathComponent("Длинное.markdown")
  try "Обычный TXT".write(to: txt, atomically: true, encoding: .utf8)
  try "Café и задачи\n- [ ] первый\n- [x] второй".write(to: markdown, atomically: true, encoding: .utf8)
  try "secret".write(to: other.appendingPathComponent(".hidden.md"), atomically: true, encoding: .utf8)
  try "ignored".write(to: other.appendingPathComponent("image.png"), atomically: true, encoding: .utf8)
  try fm.createSymbolicLink(at: other.appendingPathComponent("Link.md"), withDestinationURL: txt)
  notes.refreshTree()
  waitForIndex(notes)
  expect(notes.findNode(school, in: notes.allNotes)?.noteCount == 2, "Recursive folder counts")
  expect(notes.findNode(other, in: notes.allNotes)?.noteCount == 2, "Only supported visible nonsymlink files indexed")
  notes.searchField.stringValue = "ЭЛЕКТРИЧЕСТВО"
  notes.applySearch()
  expect(notes.tree.count == 1 && notes.tree[0].children[0].children.count == 1,
         "Body search keeps folder hierarchy")
  let result = notes.tree[0].children[0].children[0]
  expect(result.snippet.contains("Электричество и ток"), "First occurrence supplies search context")
  notes.searchField.stringValue = "cafe"
  notes.applySearch()
  expect(notes.tree.count == 1 && notes.tree[0].children[0].url == markdown,
         "Search ignores case and diacritics")
  notes.searchField.stringValue = "несуществующее слово"
  notes.applySearch()
  expect(notes.tree.isEmpty && notes.searchStatus.stringValue == "Ничего не найдено", "Empty search state")
  notes.searchField.stringValue = "Новый заголовок"
  notes.applySearch()
  expect(notes.tree[0].children[0].children[0].snippet == "Совпадение в названии", "Title-only search")
  notes.searchField.stringValue = ""
  notes.applySearch()
  notes.openNote(txt)
  expect(notes.editor.string == "Обычный TXT" && notes.noteDate.isEmpty, "TXT loads without metadata")
  notes.openNote(markdown)
  expect(notes.editor.string.hasPrefix("Café"), "Long Markdown extension loads")

  // All noninteractive formatting actions, including empty selection and Unicode offsets.
  let cases: [(Int, String, String)] = [
    (1, "слово", "**слово**"), (2, "слово", "*слово*"),
    (101, "раз\nдва\n", "# раз\n# два\n"),
    (102, "раз", "## раз"), (103, "раз", "### раз"),
    (3, "раз\nдва", "- раз\n- два"), (4, "раз\nдва", "1. раз\n2. два"),
    (5, "раз\nдва", "- [ ] раз\n- [ ] два"), (6, "раз", "> раз"),
    (7, "код", "`код`"), (7, "раз\nдва", "```\nраз\nдва\n```"),
    (1, "", "**Текст**"), (101, "", "# Заголовок"),
  ]
  for (tag, source, expected) in cases {
    notes.editor.string = source
    notes.editor.setSelectedRange(NSRange(location: 0, length: (source as NSString).length))
    let sender = NSButton()
    sender.tag = tag
    notes.dirty = false
    notes.formatText(sender)
    expect(notes.dirty, "Formatting marks the note dirty")
    expect(notes.editor.string == expected, "Formatting tag \(tag) with \(source.debugDescription)")
  }
  expect(notes.makeFormattingBar().arrangedSubviews.count == 4, "Four labeled formatting groups")
  for invalid in ["", ".hidden", "../bad", "a/b", "a:b", "a\nb", "a.app", String(repeating: "я", count: 101)] {
    expect(!notes.validEntryName(invalid), "Reject invalid name \(invalid.debugDescription)")
  }
  expect(notes.validEntryName("Учёба 🙂"), "Unicode names supported")

  // Colors, history, ordering, collapsed folders and reminders must follow a moved subtree.
  notes.dirty = false
  notes.loadNote(try String(contentsOf: renamed, encoding: .utf8), url: renamed)
  notes.recordRecent(txt)
  notes.recordRecent(renamed)
  notes.recordRecent(txt)
  let history = notes.defaults.stringArray(forKey: "recentNotes")!
  expect(history.first == notes.relativePath(txt) && Set(history).count == history.count,
         "History deduplicates and puts latest first")
  let oldFolderKey = notes.relativePath(school)
  let oldNoteKey = notes.relativePath(renamed)
  notes.defaults.set([oldFolderKey: "blue", oldNoteKey: "red"], forKey: "itemColors")
  notes.defaults.set([oldFolderKey, oldFolderKey + "/ДЗ"], forKey: "collapsedFolders")
  notes.defaults.set(["": ["Учёба", "Разное"], oldFolderKey: ["ДЗ"]], forKey: "treeOrder")
  notes.defaults.set([oldNoteKey: ["id": "test-reminder", "time": Date().addingTimeInterval(3600).timeIntervalSince1970]],
                     forKey: "reminders")
  notes.defaults.set(false, forKey: "notificationsEnabled")
  let movedSchool = notes.root.appendingPathComponent("Занятия")
  try notes.moveEntry(school, to: movedSchool)
  let movedNote = movedSchool.appendingPathComponent("ДЗ/Новый заголовок.md")
  expect(notes.currentURL?.path == movedNote.path && notes.editor.string.contains("Дополнение"),
         "Moving parent keeps open child and content")
  expect(notes.itemColors["Занятия"] == "blue" && notes.itemColors["Занятия/ДЗ/Новый заголовок.md"] == "red",
         "Colors follow folder and descendants")
  expect(notes.defaults.stringArray(forKey: "collapsedFolders")!.contains("Занятия/ДЗ"),
         "Expansion state follows moved folder")
  expect(notes.reminderRecords["Занятия/ДЗ/Новый заголовок.md"]?["id"] as? String == "test-reminder",
         "Reminder identity follows moved note")
  expect(notes.customOrder[""]?.first == "Занятия" && notes.customOrder["Занятия"] == ["ДЗ"],
         "Custom order remaps folder names")
  let renamedNote = movedNote.deletingLastPathComponent().appendingPathComponent("Переименовано.md")
  try notes.moveEntry(movedNote, to: renamedNote, newTitle: "Переименовано")
  expect(notes.titleField.stringValue == "Переименовано", "Context rename updates open title")
  expect((try! String(contentsOf: renamedNote, encoding: .utf8)).hasPrefix("Переименовано\n"),
         "Context rename updates stored metadata")
  let duplicate = try notes.duplicateEntry(renamedNote)
  let duplicate2 = try notes.duplicateEntry(renamedNote)
  expect(duplicate.lastPathComponent == "Переименовано — копия.md" && duplicate2.lastPathComponent.contains("(2)"),
         "Duplicate generates unique readable names")
  expect((try! String(contentsOf: duplicate, encoding: .utf8)).hasPrefix("Переименовано — копия\n"),
         "Duplicate updates copied title")
  expect(notes.itemColors[notes.relativePath(duplicate)] == "red", "Duplicate copies color")
  let folderCopy = try notes.duplicateEntry(movedSchool)
  expect(fm.fileExists(atPath: folderCopy.appendingPathComponent("ДЗ/Переименовано.md").path),
         "Folder duplicate copies descendants")
  expect(notes.itemColors[notes.relativePath(folderCopy)] == "blue", "Folder duplicate copies own color")
  do {
    try notes.moveEntry(duplicate, to: renamedNote)
    preconditionFailure("Move must reject overwriting a different file")
  } catch { expect(fm.fileExists(atPath: duplicate.path), "Failed move retains source") }
  do {
    try notes.moveEntry(movedSchool, to: movedSchool.appendingPathComponent("ДЗ/recursive"))
    preconditionFailure("Move must reject nesting a folder in itself")
  } catch { expect(fm.fileExists(atPath: renamedNote.path), "Rejected recursive move retains descendants") }

  notes.refreshTree()
  waitForIndex(notes)
  notes.keyboardContextURL = renamedNote
  let context = NSMenu()
  notes.menuNeedsUpdate(context)
  expect(context.items.contains { $0.title == "Переименовать…" }, "Note context rename action")
  expect(context.items.contains { $0.title == "Отменить напоминание" }, "Note reminder cancellation action")
  expect(context.items.first { $0.title == "Цвет" }?.submenu?.items.count == 9, "Color palette and reset")
  let destinations = context.items.first { $0.title == "Переместить в…" }!.submenu!
  expect(destinations.items.contains {
    ($0.representedObject as? [String: String])?["destination"] == ""
  }, "A note can move from a topic to the library root")
  notes.keyboardContextURL = movedSchool
  notes.menuNeedsUpdate(context)
  expect(context.items.contains { $0.title == "Новая подпапка…" }, "Folder context has nested creation")
  expect(!context.items.contains { $0.title == "Напомнить…" }, "Folder context omits note-only reminders")
  notes.keyboardContextURL = nil

  notes.cancelReminders(in: movedSchool)
  expect(notes.reminderRecords.isEmpty, "Cancel reminders recursively")
  notes.removeEntryPreferences(movedSchool)
  expect(!notes.itemColors.keys.contains { $0 == "Занятия" || $0.hasPrefix("Занятия/") },
         "Delete cleans descendant colors")
  expect(!notes.customOrder.keys.contains { $0 == "Занятия" || $0.hasPrefix("Занятия/") },
         "Delete cleans descendant order")

  // Every published action has a menu entry and settings row, and modifier encodings agree.
  expect(notes.noteActions.count == 35 && notes.shortcutMenuItems.count == 35, "All 35 actions registered")
  let settings = NotesSettingsController(app: notes)
  settings.refresh()
  expect(settings.actionLabels.count == 35, "All 35 actions configurable")
  settings.theme.selectItem(at: 2)
  settings.changeTheme()
  expect(notes.defaults.string(forKey: "appearance") == "dark" && NSApp.appearance?.name == .darkAqua,
         "Theme setting applies")
  settings.theme.selectItem(at: 0)
  settings.changeTheme()
  expect(NSApp.appearance == nil, "System theme restores")
  let previousDate = notes.showDates
  notes.toggleDate()
  expect(notes.showDates != previousDate, "Date visibility persists")
  notes.toggleDate()
  expect(notes.serviceKeyEquivalent(character: "1", modifiers: UInt32(cmdKey | shiftKey)) == "$@1",
         "Service shortcut modifier encoding")
  expect(notes.eventModifiers(UInt32(cmdKey | shiftKey | optionKey | controlKey)) == [.command, .shift, .option, .control],
         "Carbon to native modifier conversion")
  var swipe = HorizontalSwipe()
  expect(swipe.update(x: 8, y: 1, time: 1, began: true, ended: false) == nil, "Swipe threshold")
  expect(swipe.update(x: 9, y: 1, time: 1.02, began: false, ended: false) == 17, "Swipe accumulates")
  expect(swipe.update(x: 30, y: 0, time: 1.04, began: false, ended: false) == nil, "One recognition per gesture")
  _ = swipe.update(x: 0, y: 0, time: 1.05, began: false, ended: true)
  expect(swipe.update(x: -20, y: 1, time: 1.1, began: true, ended: false) == -20, "Reverse swipe after ending")
  expect(swipe.update(x: 20, y: 40, time: 2, began: true, ended: false) == nil, "Vertical scroll leaves sidebar alone")
  print("Feature checks passed — save/open/draft, folders/search, formatting, file operations, metadata, settings, actions, gesture recognition")
}
