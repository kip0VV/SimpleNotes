import Cocoa

DispatchQueue.global().asyncAfter(deadline: .now() + 90) {
  FileHandle.standardError.write(Data("Test timeout: possible deadlock or save loop\n".utf8))
  exit(1)
}
let application = NSApplication.shared
let testDomain = Bundle.main.bundleIdentifier!
UserDefaults.standard.removePersistentDomain(forName: testDomain)
defer { UserDefaults.standard.removePersistentDomain(forName: testDomain) }
let notes = NotesApp()
notes.window = NSWindow(
  contentRect: NSRect(x: 0, y: 0, width: 700, height: 550), styleMask: [.titled],
  backing: .buffered, defer: false)
notes.editorScroll = NSScrollView(frame: notes.window.contentView!.bounds)
notes.window.contentView!.addSubview(notes.editorScroll)
notes.editorScroll.documentView = notes.editor
notes.editor.allowsUndo = true
notes.window.makeFirstResponder(notes.editor)
notes.buildMenu()
precondition(notes.preview == nil, "Preview should be lazy")
notes.setNoteZoom(1.5)
precondition(notes.editor.font!.pointSize == 24 && notes.zoomLabel.title == "150%")
notes.setNoteZoom(5)
precondition(notes.noteZoom == 2)
notes.setNoteZoom(0.1)
precondition(notes.noteZoom == 0.5)
notes.resetZoom()
precondition(notes.noteZoom == 1 && notes.preview == nil)
precondition(notes.shortcutConflict(key: "q", modifiers: [.command], excluding: "bold") != nil)
precondition(notes.shortcutConflict(key: "i", modifiers: [.command], excluding: "bold") == "Курсив")
precondition(
  notes.shortcutConflict(key: "=", modifiers: [.command, .shift], excluding: "bold")
    == "Увеличить масштаб")
precondition(
  notes.shortcutConflict(key: "z", modifiers: [.command, .shift], excluding: "bold") == "Повторить")
precondition(Set(notes.noteActions.map(\.id)).count == notes.noteActions.count)
notes.defaults.set(
  ["bold": ["key": "b", "modifiers": NSEvent.ModifierFlags([.command, .shift]).rawValue]],
  forKey: "actionShortcuts")
notes.updateActionShortcuts()
precondition(notes.shortcutMenuItems["bold"]!.keyEquivalentModifierMask == [.command, .shift])
notes.defaults.removeObject(forKey: "actionShortcuts")
notes.updateActionShortcuts()
notes.editor.string = "🙂Привет"
notes.editor.setSelectedRange(NSRange(location: 2, length: 6))
let format = NSMenuItem()
format.representedObject = "bold"
notes.performNoteAction(format)
precondition(notes.editor.string == "🙂**Привет**")
precondition(notes.preview == nil)

let manager = FileManager.default
let fixture = manager.temporaryDirectory.appendingPathComponent(
  "SimpleNotes-index-" + UUID().uuidString)
try manager.createDirectory(at: fixture, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: fixture) }
let folder = fixture.appendingPathComponent("Тема")
try manager.createDirectory(at: folder, withIntermediateDirectories: true)
let file = folder.appendingPathComponent("Тест.md")
try "Тест\nДата\nТема — Тема\n\nПервый текст".write(to: file, atomically: true, encoding: .utf8)
let junk = fixture.appendingPathComponent("Ignored.app")
try manager.createDirectory(at: junk, withIntermediateDirectories: true)
try "private".write(to: junk.appendingPathComponent("Hidden.md"), atomically: true, encoding: .utf8)
var scanner = NoteIndexScanner(root: fixture, order: [:], cache: [:])
var tree = try scanner.scan()
precondition(tree.count == 1 && tree[0].children[0].searchBody == "Первый текст")
let cachedURL = scanner.cache.keys.first!
let cached = scanner.cache[cachedURL]!
scanner.cache[cachedURL] = CachedNoteBody(
  modified: cached.modified, size: cached.size, changed: cached.changed, identity: cached.identity,
  generation: cached.generation, body: "CACHE HIT")
tree = try scanner.scan()
precondition(tree[0].children[0].searchBody == "CACHE HIT", "Unchanged body should come from cache")
try "Тест\nДата\nТема — Тема\n\nВторой текст".write(to: file, atomically: true, encoding: .utf8)
try manager.setAttributes(
  [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: file.path)
tree = try scanner.scan()
precondition(tree[0].children[0].searchBody == "Второй текст")
let preservedDate = scanner.cache.values.first!.modified!
let replacement = "Тест\nДата\nТема — Тема\n\nТретий текст"
precondition(replacement.utf8.count == (try! String(contentsOf: file, encoding: .utf8)).utf8.count)
try replacement.write(to: file, atomically: true, encoding: .utf8)
try manager.setAttributes([.modificationDate: preservedDate], ofItemAtPath: file.path)
tree = try scanner.scan()
precondition(
  tree[0].children[0].searchBody == "Третий текст",
  "Atomic replacement with preserved size and timestamp must invalidate cache")
try manager.removeItem(at: file)
_ = try scanner.scan()
precondition(scanner.cache.isEmpty)
notes.root = fixture
let folders = try notes.folderNodes(in: fixture)
precondition(folders.count == 1)
let later = fixture.appendingPathComponent("Вторая.md")
try "Новая".write(to: later, atomically: true, encoding: .utf8)
notes.refreshTree()
let newest = fixture.appendingPathComponent("Третья.md")
try "Последняя".write(to: newest, atomically: true, encoding: .utf8)
notes.refreshTree()
let deadline = Date().addingTimeInterval(5)
while Date() < deadline && notes.allNotes.count != 3 {
  RunLoop.current.run(until: Date().addingTimeInterval(0.02))
}
precondition(notes.allNotes.count == 3, "Latest asynchronous scan must win")
notes.defaults.removeObject(forKey: "noteZoom")
for separator in ["\n", "\r\n", "\r"] {
  let text = "🙂Заголовок" + separator + "  > - [ ] Задача"
  let marker = NotesApp.taskMarkerRange(in: text, line: 1)!
  precondition((text as NSString).substring(with: marker) == " ")
}
precondition(NotesApp.taskMarkerRange(in: "- `[ ]` код", line: 0) == nil)
precondition(NotesApp.taskMarkerRange(in: "- [ ] задача", line: 100) == nil)
let unusualNewline = "Строка\u{2028}продолжение\n- [ ] Задача"
precondition(
  NotesApp.taskMarkerRange(in: unusualNewline, line: 1) != nil,
  "Task lines must match Markdown newline rules")

// Task toggles must preserve imported Markdown bytes and the original filename.
notes.root = fixture.resolvingSymlinksInPath()
let plainFile = notes.root.appendingPathComponent("original-name.md")
let plainText = "# Обычный Markdown\r\n\r\n- [ ] задача 🙂\r\n"
try plainText.write(to: plainFile, atomically: true, encoding: .utf8)
notes.currentURL = plainFile
notes.loadedContent = plainText
notes.editor.string = plainText
notes.editor.delegate = notes
notes.titleField.stringValue = "Другое название"
notes.dirty = false
notes.topics.removeAllItems()
notes.topics.addItem(withTitle: "Без папки")
notes.topics.lastItem?.representedObject = ""
notes.toggleMarkdownTask(line: 2, checked: true)
precondition(
  try! String(contentsOf: plainFile, encoding: .utf8)
    == plainText.replacingOccurrences(of: "[ ]", with: "[x]"))
precondition(notes.currentURL == plainFile && !notes.dirty)
precondition(
  !manager.fileExists(atPath: notes.root.appendingPathComponent("Другое название.md").path))

// Reordering and moving use an immediate snapshot, then verify it asynchronously.
notes.root = notes.root.resolvingSymlinksInPath()
let alpha = notes.root.appendingPathComponent("A", isDirectory: true)
let beta = notes.root.appendingPathComponent("B", isDirectory: true)
let first = alpha.appendingPathComponent("first.md")
let nested = alpha.appendingPathComponent("nested", isDirectory: true)
try manager.createDirectory(at: nested, withIntermediateDirectories: true)
try manager.createDirectory(at: beta, withIntermediateDirectories: true)
try "first body".write(to: first, atomically: true, encoding: .utf8)
try "nested body".write(
  to: nested.appendingPathComponent("inside.md"), atomically: true, encoding: .utf8)
var moveScanner = NoteIndexScanner(root: notes.root, order: [:], cache: [:])
notes.allNotes = try moveScanner.scan()
let moved = beta.appendingPathComponent("nested", isDirectory: true)
precondition(notes.applyMovedSnapshot(from: nested, to: moved))
precondition(notes.findNode(nested, in: notes.allNotes) == nil)
precondition(
  notes.findNode(moved.appendingPathComponent("inside.md"), in: notes.allNotes)?.searchBody
    == "nested body")
precondition(notes.findNode(alpha, in: notes.allNotes)?.noteCount == 1)
precondition(notes.findNode(beta, in: notes.allNotes)?.noteCount == 1)
notes.defaults.set(["": ["B", "A"]], forKey: "treeOrder")
precondition(notes.applyMovedSnapshot(from: beta, to: beta))
precondition(notes.allNotes.first!.url.resolvingSymlinksInPath().path == beta.resolvingSymlinksInPath().path)
notes.defaults.removeObject(forKey: "treeOrder")

// A switched library must stop showing the previous library immediately.
notes.root = beta
notes.refreshTree()
precondition(notes.allNotes.isEmpty && notes.noteBodyCache.isEmpty)
let switchDeadline = Date().addingTimeInterval(5)
while Date() < switchDeadline && notes.indexQueue.operationCount > 0 {
  RunLoop.current.run(until: Date().addingTimeInterval(0.02))
}
RunLoop.current.run(until: Date().addingTimeInterval(0.05))
precondition(notes.root == beta && notes.allNotes.isEmpty)
print("Optimization, zoom, shortcut and cache regression checks passed")

try runFeatureChecks(notes: notes, fixture: fixture)

try runMarkdownChecks(notes: notes, fixture: fixture)

runLayoutChecks(notes: notes)

runReminderChecks()

try runReminderListChecks(notes: notes, fixture: fixture)

try runManyRemindersChecks(notes: notes, fixture: fixture)

try runCriticalChecks(notes: notes, fixture: fixture)
