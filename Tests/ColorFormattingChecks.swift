import Cocoa

func runColorFormattingChecks(notes: NotesApp) {
  notes.mode.selectedSegment = 0
  notes.editor.string = "Тема и определение 😀"
  notes.applyNoteColor("topic", range: NSRange(location: 0, length: 4))
  precondition(notes.editor.string == "[Тема]{topic} и определение 😀")
  notes.applyNoteColor("definition", range: notes.editor.selectedRange())
  precondition(notes.editor.string == "[Тема]{definition} и определение 😀", "Semantic styles replace one another")
  notes.applyNoteColor("text-orange", range: notes.editor.selectedRange())
  precondition(notes.editor.string == "[[Тема]{text-orange}]{definition} и определение 😀")
  notes.applyNoteColor("clear", range: notes.editor.selectedRange())
  precondition(notes.editor.string == "Тема и определение 😀", "Clear removes all adjacent nested color annotations")
  notes.editor.string = "[Тема]{topic} и [термин]{definition}"
  notes.applyNoteColor("clear", range: NSRange(location: 0, length: (notes.editor.string as NSString).length))
  precondition(notes.editor.string == "Тема и термин")
  notes.editor.string = "## *Заголовок*\n\nДальше текст"
  let heading = "## *Заголовок*\n" as NSString
  notes.applyNoteColor("topic", range: NSRange(location: 0, length: heading.length))
  precondition(notes.editor.string == "## [*Заголовок*]{topic}\n\nДальше текст", "Heading marker and trailing newline stay outside color")
  notes.applyNoteColor("clear", range: notes.editor.selectedRange())
  precondition(notes.editor.string == "## *Заголовок*\n\nДальше текст")
  notes.defaults.set("matteOrange", forKey: "appearance")
  notes.applyTheme()
  precondition(notes.isCustomTheme && !notes.isGraphite)
  precondition(notes.editor.backgroundColor == EditorStyle.color("#211C18"))
  notes.defaults.set("graphite", forKey: "appearance")
  notes.applyTheme()
  precondition(notes.isGraphite && notes.editor.backgroundColor == EditorStyle.color("#171B22"))
  notes.defaults.removeObject(forKey: "appearance")
  notes.applyTheme()
  print("Color formatting and both matte themes passed")
}
