import Cocoa

func runExternalNoteUpdateChecks(fixture: URL) throws {
  let notes = NotesApp()
  notes.window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 550), styleMask: [.titled], backing: .buffered, defer: false)
  notes.editorScroll = NSScrollView()
  notes.editorScroll.documentView = notes.editor
  notes.root = fixture
  let file = fixture.appendingPathComponent("external-update.md")
  try "Before".write(to: file, atomically: true, encoding: .utf8)
  notes.loadNote("Before", url: file)
  notes.dirty = false
  func waitForRead() {
    let deadline = Date().addingTimeInterval(5)
    while notes.externalReadInFlight && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    precondition(!notes.externalReadInFlight)
  }
  notes.refreshOpenNoteFromDisk()
  waitForRead()
  try "After external replacement".write(to: file, atomically: true, encoding: .utf8)
  notes.refreshOpenNoteFromDisk()
  waitForRead()
  precondition(notes.editor.string == "After external replacement" && notes.loadedContent == notes.editor.string && !notes.dirty)
  notes.editor.string = "Unsaved local changes"
  notes.dirty = true
  try "Another external version".write(to: file, atomically: true, encoding: .utf8)
  notes.refreshOpenNoteFromDisk(force: true)
  precondition(notes.editor.string == "Unsaved local changes" && notes.dirty, "Never replace unsaved changes")
  notes.dirty = false
  notes.openNote(file)
  waitForRead()
  precondition(notes.editor.string == "Another external version", "Reopening same note rereads disk")
  try "Do not apply this to another note".write(to: file, atomically: true, encoding: .utf8)
  notes.refreshOpenNoteFromDisk(force: true)
  notes.currentURL = nil
  notes.editor.string = "New draft"
  waitForRead()
  precondition(notes.editor.string == "New draft", "Late reads cannot overwrite a different note")
  notes.loadNote(try String(contentsOf: file, encoding: .utf8), url: file)
  notes.dirty = false
  notes.startExternalNoteUpdates()
  precondition(notes.externalFileWatch != nil && notes.externalDirectoryWatch != nil)
  try "Event-driven update".write(to: file, atomically: true, encoding: .utf8)
  let eventDeadline = Date().addingTimeInterval(5)
  while notes.editor.string != "Event-driven update" && Date() < eventDeadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
  }
  precondition(notes.editor.string == "Event-driven update", "Filesystem events reload atomic replacement without polling")
  notes.window.contentView!.addSubview(notes.previewContainer)
  notes.previewContainer.frame = notes.window.contentView!.bounds
  notes.mode.selectedSegment = 1
  notes.renderMarkdown()
  let readyDeadline = Date().addingTimeInterval(8)
  while !notes.previewReady && Date() < readyDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
  precondition(notes.previewReady)
  let finalContent = "# Новая версия\n\nТекст после внешнего изменения.\n\n$$x^2$$"
  try "Intermediate version".write(to: file, atomically: true, encoding: .utf8)
  try finalContent.write(to: file, atomically: true, encoding: .utf8)
  let finalDeadline = Date().addingTimeInterval(5)
  while notes.editor.string != finalContent && Date() < finalDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
  precondition(notes.editor.string == finalContent && notes.loadedContent == finalContent)
  var rendered = false
  var completed = false
  notes.preview?.evaluateJavaScript("document.querySelector('#body h1')?.textContent === 'Новая версия' && document.querySelectorAll('#body .katex').length === 1") { value, _ in
    rendered = value as? Bool == true
    completed = true
  }
  let renderDeadline = Date().addingTimeInterval(5)
  while !completed && Date() < renderDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
  precondition(rendered, "External changes refresh actual WebKit text and math rendering")
  notes.currentURL = nil
  precondition(notes.externalFileWatch == nil && notes.externalDirectoryWatch == nil,
               "Closing note releases both watchers")
  print("External updates passed — atomic replacement, same-note reopen, unsaved edits and stale read protection")
}
