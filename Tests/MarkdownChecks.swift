import Cocoa
import WebKit

private func javascript(_ expression: String, in view: WKWebView) -> Any? {
  var completed = false
  var result: Any?
  var failure: Error?
  view.evaluateJavaScript(expression) { value, error in
    result = value
    failure = error
    completed = true
  }
  let deadline = Date().addingTimeInterval(10)
  while !completed && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
  }
  precondition(completed && failure == nil, "JavaScript evaluation failed: \(String(describing: failure))")
  return result
}

func runMarkdownChecks(notes: NotesApp, fixture: URL) throws {
  notes.dirty = false
  notes.currentURL = nil
  notes.loadedContent = nil
  notes.titleField.stringValue = "Markdown 🙂"
  notes.noteDate = "10.11.2026 12:00"
  notes.editor.string = """
    # Заголовок
    **Жирный** и *курсив*

    - [ ] Простая задача
    - [x] Готовая задача
      - [ ] Вложенная задача

    > - [ ] Цитата-задача

    1. [ ] Нумерованная задача

    | Раз | Два |
    | --- | --- |
    | A | B |

    ```swift
    - [ ] Это код
    ```

    <script>window.unwanted = true</script>
    """
  notes.mode.selectedSegment = 1
  notes.window.contentView!.addSubview(notes.previewContainer)
  notes.previewContainer.frame = notes.window.contentView!.bounds
  notes.renderMarkdown()
  let deadline = Date().addingTimeInterval(10)
  while !notes.previewReady && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
  }
  precondition(notes.previewReady, "Markdown document must finish loading")
  let view = notes.preview!
  precondition(javascript("document.querySelectorAll('#body input[type=checkbox]').length", in: view) as? Int == 5,
               "All supported task list variants render interactively")
  precondition(javascript("document.querySelectorAll('#body input:checked').length", in: view) as? Int == 1,
               "Checked task state renders")
  precondition(javascript("document.querySelector('#body table') !== null && document.querySelector('#body strong') !== null && document.querySelector('#body em') !== null && document.querySelector('#body pre code') !== null", in: view) as? Bool == true,
               "Tables, bold, italic and fenced code render")
  precondition(javascript("window.unwanted === undefined && document.querySelector('#body script') === null", in: view) as? Bool == true,
               "Raw note HTML stays inert")
  let taskLines = javascript("JSON.stringify(Array.from(document.querySelectorAll('#body input')).map(x => Number(x.dataset.line)))", in: view) as! String
  let lines = try JSONSerialization.jsonObject(with: Data(taskLines.utf8)) as! [Int]
  for line in lines {
    precondition(NotesApp.taskMarkerRange(in: notes.editor.string, line: line) != nil,
                 "Native task edit and renderer agree on every line")
  }
  precondition(javascript("document.getElementById('title').textContent", in: view) as? String == "Markdown 🙂",
               "Title rendered safely")
  notes.defaults.set(false, forKey: "showDates")
  notes.renderMarkdown()
  precondition(javascript("document.getElementById('date').textContent", in: view) as? String == "",
               "Date can be hidden in preview")
  notes.defaults.set(true, forKey: "showDates")
  notes.renderMarkdown()
  precondition(javascript("document.getElementById('date').textContent", in: view) as? String == notes.noteDate,
               "Date can be shown again")
  notes.setNoteZoom(1.4)
  precondition(view.pageZoom == 1.4 && notes.editor.font!.pointSize == 22.4,
               "Editor and WebKit zoom agree")
  let revision = notes.previewRevision
  notes.titleField.stringValue = "Следующая"
  notes.editor.string = "Совсем другой текст"
  notes.renderMarkdown()
  precondition(notes.preview === view && notes.previewRevision != revision,
               "Preview reuses WebView but invalidates previous task callbacks")
  precondition(javascript("document.getElementById('body').textContent.trim()", in: view) as? String == "Совсем другой текст",
               "Reused preview updates content")
  notes.defaults.set("light", forKey: "appearance")
  notes.applyTheme()
  precondition(javascript("document.documentElement.style.colorScheme", in: view) as? String == "light",
               "Theme changes update existing preview")
  notes.defaults.set("dark", forKey: "appearance")
  notes.applyTheme()
  precondition(javascript("document.documentElement.style.colorScheme", in: view) as? String == "dark",
               "Dark preview theme")

  // Draft tasks stay dirty until saving. Undo restores source and dirty state.
  notes.mode.selectedSegment = 0
  notes.editor.string = "- [ ] Черновая задача"
  notes.currentURL = nil
  notes.dirty = true
  notes.editor.undoManager?.removeAllActions()
  notes.toggleMarkdownTask(line: 0, checked: true)
  precondition(notes.editor.string == "- [x] Черновая задача" && notes.dirty && notes.currentURL == nil,
               "Task changes in draft do not save prematurely")
  notes.dirty = false
  notes.editor.undo(nil)
  precondition(notes.dirty, "Undo must mark a previously saved note dirty")
  precondition(notes.editor.string == "- [ ] Черновая задача", "Task toggle is undoable")
  notes.editor.redo(nil)
  precondition(notes.editor.string == "- [x] Черновая задача", "Task toggle is redoable")
  notes.dirty = false
  notes.defaults.removeObject(forKey: "appearance")
  notes.applyTheme()
  notes.resetZoom()
  print("Markdown checks passed — actual WebKit load, formatting, task line mapping, inert HTML, date/theme/zoom, reuse, task undo/redo")
}
