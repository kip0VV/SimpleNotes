import Cocoa

func runNoteFindChecks(notes: NotesApp) {
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
  precondition(notes.editor.string == renderedSource && !notes.dirty)
  notes.noteFindField.stringValue = ""
  notes.mode.selectedSegment = 0
  notes.updateNoteFind()
  print("Note find checks passed — counts, wrap, literal search, Cmd F, rendered text, unchanged source")
}
