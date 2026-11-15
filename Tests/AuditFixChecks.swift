import Cocoa

func runAuditFixChecks() throws {
  let fm = FileManager.default
  let root = fm.temporaryDirectory.appendingPathComponent("SimpleNotes-audit-" + UUID().uuidString)
  try fm.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? fm.removeItem(at: root) }
  let file = root.appendingPathComponent("Note.md")
  try Data("old".utf8).write(to: file)
  let reader = try FileHandle(forWritingTo: file)
  try SafeNoteWrite.replace(file, expected: "old", content: "new", root: root)
  // Simulate a CLI editor that opened the old inode before the save transaction.
  try reader.truncate(atOffset: 0)
  try reader.write(contentsOf: Data("external".utf8))
  try reader.close()
  let actual = try String(contentsOf: file, encoding: .utf8)
  precondition(actual == "new")
  let history = try fm.contentsOfDirectory(at: root.appendingPathComponent(".simplenotes-history"), includingPropertiesForKeys: nil)
  let versions = try history.map { try String(contentsOf: $0, encoding: .utf8) }
  precondition(versions.contains("external") && versions.contains("new"), "Both external and app versions survive")
  do {
    try SafeNoteWrite.replace(file, expected: "old", content: "wrong", root: root)
    preconditionFailure("Conflicting save must fail")
  } catch { let actual = try String(contentsOf: file, encoding: .utf8); precondition(actual == "new") }
  let bad = root.appendingPathComponent("Bad.md")
  try Data([0xff,0xfe,0x80]).write(to: bad)
  var scanner = NoteIndexScanner(root: root, order: [:], cache: [:])
  let nodes = try scanner.scan()
  precondition(scanner.issues.count == 1 && nodes.contains { $0.url == bad })
  precondition(nodes.count == 2, "Recovery history stays out of the note index")
  scanner.isCancelled = { true }
  do { _ = try scanner.scan(); preconditionFailure("Scan must cancel") } catch is CancellationError { }
  let notes = NotesApp()
  notes.window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
  notes.root = root
  notes.currentURL = file
  notes.loadedContent = "new"
  notes.editor.string = "snapshot"
  notes.titleField.stringValue = "Note"
  notes.dirty = true
  notes.saveQueue.suspend()
  precondition(notes.saveCurrent(preservingExistingFile: true, asynchronously: true))
  precondition(notes.saveInProgress && !notes.canLeaveNote())
  notes.editor.string = "snapshot plus continued typing"
  notes.saveQueue.resume()
  let deadline = Date().addingTimeInterval(5)
  while notes.saveInProgress && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
  precondition(!notes.saveInProgress && notes.dirty && notes.loadedContent == "snapshot")
  precondition(notes.editor.string == "snapshot plus continued typing", "Save completion cannot discard edits made during IO")
  let saved = try String(contentsOf: file, encoding: .utf8)
  precondition(saved == "snapshot")
  notes.mode.selectedSegment = 0
  notes.noteFindExpanded = true
  notes.editor.string = String(repeating: "word ", count: 25_000)
  notes.noteFindField.stringValue = "word"
  notes.updateNoteFind(reset: true)
  notes.editor.string = "tiny"
  notes.noteFindField.stringValue = ""
  notes.updateNoteFind(reset: true)
  RunLoop.current.run(until: Date().addingTimeInterval(0.1))
  precondition(notes.noteFindCount == 0, "Old background matches cannot reach a newer document")
  let other = root.appendingPathComponent("Other")
  notes.defaults.set("unsaved", forKey: "draftBody")
  notes.defaults.set(["Note.md": "blue"], forKey: "itemColors")
  notes.defaults.set(["Note.md": ["time": 123.0]], forKey: "reminders")
  notes.storeLibraryState(at: root)
  notes.restoreLibraryState(at: other)
  precondition(notes.defaults.object(forKey: "draftBody") == nil)
  notes.defaults.set("other", forKey: "draftBody")
  notes.storeLibraryState(at: other)
  notes.restoreLibraryState(at: root)
  precondition(notes.defaults.string(forKey: "draftBody") == "unsaved")
  precondition(notes.reminderRecords["Note.md"] != nil)
  notes.restoreLibraryState(at: other)
  precondition(notes.defaults.string(forKey: "draftBody") == "other")
  for key in NotesApp.libraryKeys + ["libraryStates"] { notes.defaults.removeObject(forKey: key) }
  print("PASS: external-writer recovery, save conflicts, invalid UTF8 diagnostics, cancellation and per-library drafts/settings")
}
