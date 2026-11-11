import Cocoa

func runRefreshFeedbackChecks(notes: NotesApp) {
  precondition(notes.mode.label(forSegment: 1) == "Рендер")
  notes.searchField.stringValue = ""
  let command = NSMenuItem()
  command.representedObject = "refresh"
  notes.performNoteAction(command)
  precondition(notes.refreshButton.title == "Обновление…" && !notes.refreshButton.isEnabled,
               "Explicit refresh immediately acknowledges the command")
  // A save or another scan may supersede the first generation while it runs.
  notes.refreshTree()
  let deadline = Date().addingTimeInterval(10)
  while notes.manualRefreshStarted != nil && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
  }
  precondition(notes.manualRefreshStarted == nil && notes.refreshButton.isEnabled)
  precondition(notes.refreshButton.title == "✓ Обновлено")
  precondition(notes.searchStatus.stringValue.hasPrefix("Обновлено в "))
  precondition(notes.refreshButton.toolTip?.contains("перечитаны с диска") == true)
  let original = notes.editor.string
  notes.performNoteAction(command)
  precondition(notes.refreshButton.title == "Обновление…")
  let repeatDeadline = Date().addingTimeInterval(10)
  while notes.manualRefreshStarted != nil && Date() < repeatDeadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
  }
  precondition(notes.refreshButton.title == "✓ Обновлено" && notes.editor.string == original,
               "Refreshing an unchanged folder confirms completion without touching the editor")
  print("Refresh feedback checks passed")
}
