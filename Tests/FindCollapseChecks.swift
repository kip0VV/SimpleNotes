import Cocoa

func runFindCollapseChecks() {
  let notes = NotesApp()
  notes.window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 550), styleMask: [.titled], backing: .buffered, defer: false)
  notes.editorScroll = NSScrollView()
  notes.editorScroll.documentView = notes.editor
  let bar = notes.makeNoteFindBar()
  bar.frame = NSRect(x: 0, y: 0, width: 600, height: 24)
  notes.window.contentView!.addSubview(bar)
  notes.editor.string = "текст и текст"
  notes.mode.selectedSegment = 0
  notes.setNoteFindExpanded(true, animated: false)
  notes.noteFindField.stringValue = "текст"
  notes.updateNoteFind(reset: true)
  precondition(notes.noteFindCount == 2)
  precondition(notes.editor.layoutManager!.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil) != nil)
  notes.toggleNoteFind()
  precondition(!notes.noteFindExpanded && notes.noteFindCount == 0 && notes.noteFindField.stringValue.isEmpty)
  precondition(notes.editor.layoutManager!.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil) == nil,
               "Clicking magnifier removes native editor highlights")
  notes.window.contentView!.addSubview(notes.previewContainer)
  notes.previewContainer.frame = NSRect(x: 0, y: 30, width: 600, height: 400)
  notes.mode.selectedSegment = 1
  notes.renderMarkdown()
  let readyDeadline = Date().addingTimeInterval(8)
  while !notes.previewReady && Date() < readyDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
  precondition(notes.previewReady)
  notes.setNoteFindExpanded(true, animated: false)
  notes.noteFindField.stringValue = "текст"
  notes.updateNoteFind(reset: true)
  let findDeadline = Date().addingTimeInterval(5)
  while notes.noteFindCount != 2 && Date() < findDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
  precondition(notes.noteFindCount == 2)
  precondition(notes.control(notes.noteFindField, textView: notes.editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
  var cleared: Bool?
  notes.preview!.evaluateJavaScript("(!window.CSS || !CSS.highlights || (!CSS.highlights.has('note-matches') && !CSS.highlights.has('note-current'))) && window.getSelection().rangeCount === 0") { value, _ in cleared = value as? Bool }
  let clearDeadline = Date().addingTimeInterval(5)
  while cleared == nil && Date() < clearDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
  precondition(cleared == true && !notes.noteFindExpanded && notes.noteFindCount == 0,
               "Escape collapses magnifier and clears rendered highlights and selection")
  precondition(notes.editor.string == "текст и текст" && !notes.dirty)
  print("Find collapse checks passed — magnifier, Escape, native and rendered highlight removal")
}
