import Cocoa

func runNoteFindChecks(notes: NotesApp) {
  notes.noteFindExpanded = true
  notes.mode.selectedSegment = 0
  notes.editor.string = "Искать 🙂 текст, ТЕКСТ и текст."
  let source = notes.editor.string
  notes.dirty = false
  notes.noteFindField.stringValue = "текст"
  notes.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: notes.noteFindField))
  precondition(notes.noteFindCount == 3 && notes.noteFindCounter.stringValue == "1/3")
  precondition(!notes.dirty && notes.editor.string == source, "Find does not modify note or dirty state")
  notes.nextNoteMatch()
  precondition(notes.noteFindCounter.stringValue == "2/3")
  notes.previousNoteMatch()
  notes.previousNoteMatch()
  precondition(notes.noteFindCounter.stringValue == "3/3", "Previous wraps to last match")
  notes.nextNoteMatch()
  precondition(notes.noteFindCounter.stringValue == "1/3", "Next wraps to first match")
  notes.noteFindField.stringValue = "."
  notes.updateNoteFind(reset: true)
  precondition(notes.noteFindCount == 1, "Find uses literal text, not regex")
  notes.noteFindField.stringValue = "несуществующее"
  notes.updateNoteFind(reset: true)
  precondition(notes.noteFindCounter.stringValue == "0/0" && !notes.noteFindNext.isEnabled)
  notes.noteFindField.stringValue = ""
  notes.updateNoteFind()
  precondition(notes.noteFindCount == 0 && notes.noteFindCounter.stringValue == "—")
  precondition(notes.editor.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil) == nil,
               "Clearing find removes editor highlights")
  notes.editor.string = "🙂 Это   целое\nпредложение (с примером).\nЭто целое предложение (с примером)."
  notes.noteFindField.stringValue = "Это целое предложение (с примером)."
  notes.updateNoteFind(reset: true)
  precondition(notes.noteFindCount == 2, "Sentences match across line breaks and repeated spaces")
  notes.noteFindField.stringValue = "целое предложение"
  notes.updateNoteFind(reset: true)
  precondition(notes.noteFindCount == 2, "Multiword phrases match")
  notes.noteFindField.stringValue = "  \n "
  notes.updateNoteFind(reset: true)
  precondition(notes.noteFindCount == 0 && notes.noteFindCounter.stringValue == "—")
  let find = notes.noteActions.first { $0.id == "noteFind" }!
  let library = notes.noteActions.first { $0.id == "search" }!
  precondition(notes.actionBinding(find).0 == "f" && notes.actionBinding(library).0.isEmpty,
               "Cmd F searches the note; library search has no default shortcut")

  notes.editor.string = "най**ти** текст, найти текст\n\n$$x^2$$\n\n- [ ] найти решение"
  let renderedSource = notes.editor.string
  notes.mode.selectedSegment = 1
  notes.noteFindField.stringValue = "найти"
  notes.renderMarkdown()
  notes.updateNoteFind(reset: true)
  let deadline = Date().addingTimeInterval(5)
  while notes.noteFindCounter.stringValue != "1/3" && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
  }
  precondition(notes.noteFindCounter.stringValue == "1/3", "Rendered search crosses inline formatting")
  notes.nextNoteMatch()
  let nextDeadline = Date().addingTimeInterval(5)
  while notes.noteFindCounter.stringValue != "2/3" && Date() < nextDeadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
  }
  precondition(notes.noteFindCounter.stringValue == "2/3")
  notes.noteFindField.stringValue = "найти текст"
  notes.updateNoteFind(reset: true)
  let phraseDeadline = Date().addingTimeInterval(5)
  while notes.noteFindCounter.stringValue != "1/2" && Date() < phraseDeadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
  }
  precondition(notes.noteFindCounter.stringValue == "1/2", "Rendered multiword phrase crosses bold boundary")
  notes.editor.string = "Это **целое**   предложение\n(с примером).\n\nЭто целое предложение (с примером)."
  notes.noteFindField.stringValue = "Это целое предложение (с примером)."
  notes.renderMarkdown()
  notes.updateNoteFind(reset: true)
  let sentenceDeadline = Date().addingTimeInterval(5)
  while notes.noteFindCounter.stringValue != "1/2" && Date() < sentenceDeadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
  }
  RunLoop.current.run(until: Date().addingTimeInterval(0.1))
  precondition(notes.noteFindCounter.stringValue == "1/2", "Rendered sentences tolerate whitespace, newlines and literal punctuation")
  precondition(!notes.dirty)
  // The search field's cancel button can send its action rather than a text-change notification.
  notes.noteFindField.stringValue = ""
  notes.noteFindChanged()
  precondition(notes.noteFindCount == 0 && !notes.noteFindNext.isEnabled)
  var cleared: Bool?
  notes.preview?.evaluateJavaScript("!window.CSS || !CSS.highlights || (!CSS.highlights.has('note-matches') && !CSS.highlights.has('note-current'))") { value, _ in cleared = value as? Bool }
  let clearDeadline = Date().addingTimeInterval(5)
  while cleared == nil && Date() < clearDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
  precondition(cleared == true, "Cancel clears all rendered highlights")
  notes.editor.string = renderedSource
  precondition(notes.editor.string == renderedSource && !notes.dirty)
  notes.noteFindField.stringValue = ""
  notes.mode.selectedSegment = 0
  notes.updateNoteFind()
  print("Note find checks passed — counts, wrap, literal search, Cmd F, rendered text, unchanged source")
}
