import Cocoa

let application = NSApplication.shared
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
  modified: cached.modified, size: cached.size, body: "CACHE HIT")
tree = try scanner.scan()
precondition(tree[0].children[0].searchBody == "CACHE HIT", "Unchanged body should come from cache")
try "Тест\nДата\nТема — Тема\n\nВторой текст".write(to: file, atomically: true, encoding: .utf8)
try manager.setAttributes(
  [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: file.path)
tree = try scanner.scan()
precondition(tree[0].children[0].searchBody == "Второй текст")
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
print("Optimization, zoom, shortcut and cache regression checks passed")
