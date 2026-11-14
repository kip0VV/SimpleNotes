import Cocoa
import WebKit

// Real files, DispatchSource events, AppKit controls and the bundled WKWebView renderer.
// No replacement filesystem, renderer, or notification scheduler.
func runLiveRuntimeChecks(fixture: URL) throws {
  let notes = NotesApp()
  notes.window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
  notes.editorScroll = NSScrollView()
  notes.window.contentView!.addSubview(notes.editorScroll)
  notes.editorScroll.documentView = notes.editor
  notes.editor.delegate = notes
  notes.editor.allowsUndo = true
  notes.window.contentView!.addSubview(notes.previewContainer)
  notes.previewContainer.frame = notes.window.contentView!.bounds
  let bar = notes.makeNoteFindBar()
  bar.frame = NSRect(x: 0, y: 0, width: 800, height: 24)
  notes.window.contentView!.addSubview(bar)
  let library = fixture.appendingPathComponent("LiveRuntime")
  try FileManager.default.createDirectory(at: library.appendingPathComponent("Folder"), withIntermediateDirectories: true)
  notes.root = library
  let file = library.appendingPathComponent("Live.md")
  var failures: [String] = []
  var results: [String] = []
  func check(_ ok: Bool, _ message: String) {
    results.append("\(ok ? "PASS" : "FAIL"): \(message)")
    if !ok { failures.append(message) }
  }
  func spin(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
  func wait(_ condition: () -> Bool, timeout: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { spin(0.01) }
    return condition()
  }
  func js(_ source: String) -> Any? {
    var done = false
    var result: Any?
    var failure: Error?
    notes.preview?.evaluateJavaScript(source) { value, error in result = value; failure = error; done = true }
    let completed = wait({ done })
    check(completed && failure == nil, "WebKit JavaScript completed")
    return result
  }
  func reset(_ content: String) throws {
    notes.currentURL = nil
    try content.write(to: file, atomically: true, encoding: .utf8)
    notes.loadNote(content, url: file)
    notes.dirty = false
  }
  notes.startExternalNoteUpdates()
  try reset("Исходный текст")
  notes.titleField.stringValue = "Несохранённое название"
  notes.dirty = true
  try "Внешняя версия".write(to: file, atomically: true, encoding: .utf8)
  spin(0.5)
  check(notes.titleField.stringValue == "Несохранённое название" && notes.dirty && notes.editor.string == "Исходный текст", "External event preserves unsaved TITLE of a plain note")
  try reset("Исходный текст")
  notes.refreshTopics(select: "Folder")
  notes.topicChanged()
  try "Внешняя версия папки".write(to: file, atomically: true, encoding: .utf8)
  spin(0.5)
  check(notes.selectedTopicPath == "Folder" && notes.dirty, "External event preserves unsaved FOLDER of a plain note")
  let legacy = "Заголовок\n14.11.2026 12:00\nТема — Без папки\n\nИсходный текст"
  try reset(legacy)
  notes.dirty = true // A redundant AppKit edit notification, no actual edit.
  let changedLegacy = legacy.replacingOccurrences(of: "Исходный текст", with: "Обновлённый текст")
  try changedLegacy.write(to: file, atomically: true, encoding: .utf8)
  check(wait({ notes.loadedContent == changedLegacy }), "Unchanged legacy note with stale dirty flag refreshes from a real filesystem event")

  try reset("# Версия 0\n\nнайти слово\n\n$$x^2$$")
  notes.mode.selectedSegment = 1
  notes.renderMarkdown()
  check(wait({ notes.previewReady }), "Real WebKit document loaded")
  _ = js("document.getElementById('body').firstElementChild.auditIdentity = 42")
  notes.renderMarkdown()
  check(js("document.getElementById('body').firstElementChild.auditIdentity === 42") as? Bool == true, "Unchanged render preserves DOM and avoids re-parsing the note")
  notes.setNoteFindExpanded(true, animated: false)
  notes.noteFindField.stringValue = "найти слово"
  notes.updateNoteFind(reset: true)
  check(wait({ notes.noteFindCount == 1 }), "Initial live search found phrase")
  let start = Date()
  for version in 1...30 {
    let text = "# Версия \(version)\n\n" + String(repeating: "найти **слово** ", count: version) + "\n\n$$\\frac{\(version)}{2}$$"
    try text.write(to: file, atomically: true, encoding: .utf8)
    spin(0.015)
  }
  check(wait({ notes.editor.string.hasPrefix("# Версия 30") && notes.noteFindCount == 30 }), "Thirty real atomic saves update active preview and search without reopening note")
  check(js("document.querySelector('#body h1')?.textContent === 'Версия 30' && document.querySelectorAll('#body .katex').length === 1 && document.querySelectorAll('.math-error').length === 0") as? Bool == true, "Latest external text AND formula reached actual DOM")
  results.append("INFO: burst of 30 external writes settled in \(String(format: "%.3f", Date().timeIntervalSince(start))) s")
  let handle = try FileHandle(forWritingTo: file)
  try handle.truncate(atOffset: 0)
  try handle.write(contentsOf: Data("# In-place\n\nНет совпадений\n\n$$y_1$$".utf8))
  try handle.close()
  check(wait({ notes.editor.string.hasPrefix("# In-place") && notes.noteFindCount == 0 }), "In-place file write updates preview and removes obsolete matches")
  check(js("!CSS.highlights || ((!CSS.highlights.get('note-matches') || CSS.highlights.get('note-matches').size === 0) && (!CSS.highlights.get('note-current') || CSS.highlights.get('note-current').size === 0))") as? Bool == true, "No obsolete highlights after replacing all matched text")
  notes.setNoteFindExpanded(false, animated: false)
  try "# После закрытия поиска\n\nнайти слово\n\n$$z^2$$".write(to: file, atomically: true, encoding: .utf8)
  check(wait({ notes.editor.string.hasPrefix("# После закрытия") }), "External update continues after closing find")
  check(js("document.querySelector('#body h1')?.textContent === 'После закрытия поиска' && !CSS.highlights.has('note-matches') && !CSS.highlights.has('note-current')") as? Bool == true, "Closed find stays cleared after live rerender")

  // A continuous stream must not starve the renderer until the writer stops.
  var sawIntermediateUpdate = false
  for version in 1...60 {
    try "# Stream \(version)\n\n$$x_\(version)$$".write(to: file, atomically: true, encoding: .utf8)
    spin(0.025)
    if notes.editor.string.hasPrefix("# Stream") { sawIntermediateUpdate = true }
  }
  check(sawIntermediateUpdate, "Continuous external saves update the open note before the writer stops")
  check(wait({ notes.editor.string.hasPrefix("# Stream 60\n") }), "Continuous stream ends on its newest version")
  check(js("document.querySelector('#body h1')?.textContent === 'Stream 60'") as? Bool == true, "Newest streaming version reaches actual renderer")

  // Genuine NSTextView edit and undo while the preview is active.
  notes.editor.setSelectedRange(NSRange(location: (notes.editor.string as NSString).length, length: 0))
  notes.editor.insertText("\n\nLIVE-EDITOR-CHANGE", replacementRange: notes.editor.selectedRange())
  spin(0.3)
  check(js("document.getElementById('body').textContent.includes('LIVE-EDITOR-CHANGE')") as? Bool == true, "Native editor change refreshes active render automatically")
  check(notes.editor.undoManager?.canUndo == true, "Native edit registered with actual window undo manager")
  notes.editor.undo(nil)
  spin(0.3)
  check(js("!document.getElementById('body').textContent.includes('LIVE-EDITOR-CHANGE')") as? Bool == true, "Undo refreshes active render automatically")

  // Exact same file length and preserved mtime still invalidate the filesystem stamp.
  try reset("# SAME-A\n\n$$a^2$$")
  notes.renderMarkdown()
  let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
  try "# SAME-B\n\n$$b^2$$".write(to: file, atomically: true, encoding: .utf8)
  try FileManager.default.setAttributes([.modificationDate: attrs[.modificationDate]!], ofItemAtPath: file.path)
  check(wait({ notes.editor.string.hasPrefix("# SAME-B") }), "Atomic replacement with same size and mtime still refreshes")
  check(js("document.querySelector('#body h1')?.textContent === 'SAME-B'") as? Bool == true, "Same-stamp update reaches renderer")
  try FileManager.default.removeItem(at: file)
  spin(0.3)
  check(notes.editor.string.hasPrefix("# SAME-B"), "Temporary external deletion preserves the visible note")
  try "# Recreated\n\n$$c^2$$".write(to: file, atomically: true, encoding: .utf8)
  check(wait({ notes.editor.string.hasPrefix("# Recreated") }), "Directory watcher recovers after delete and recreate")
  let other = library.appendingPathComponent("Other.md")
  try "# Other note".write(to: other, atomically: true, encoding: .utf8)
  notes.openNote(other)
  try "# Old file changed".write(to: file, atomically: true, encoding: .utf8)
  spin(0.4)
  check(notes.editor.string == "# Other note" && notes.currentURL == other, "Events from previous note cannot replace newly opened note")
  check(js("document.querySelector('#body h1')?.textContent === 'Other note'") as? Bool == true, "Renderer also stays on newly opened note")
  notes.currentURL = nil
  let report = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("live-runtime-results.txt")
  try results.joined(separator: "\n").write(to: report, atomically: true, encoding: .utf8)
  print(results.filter { !$0.hasSuffix("WebKit JavaScript completed") }.joined(separator: "\n"))
  precondition(failures.isEmpty, "Live runtime failures: \(failures.joined(separator: "; "))")
}
