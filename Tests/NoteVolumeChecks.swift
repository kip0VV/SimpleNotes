import Cocoa
import WebKit

// Exercise real WebKit rendering and find at several note sizes.
func runNoteVolumeChecks() {
  let notes = NotesApp()
  notes.window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
  notes.editorScroll = NSScrollView()
  notes.editorScroll.documentView = notes.editor
  notes.window.contentView!.addSubview(notes.previewContainer)
  notes.previewContainer.frame = notes.window.contentView!.bounds
  let bar = notes.makeNoteFindBar()
  bar.frame = NSRect(x: 0, y: 0, width: 700, height: 24)
  notes.window.contentView!.addSubview(bar)
  notes.mode.selectedSegment = 1
  notes.renderMarkdown()
  func wait(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(20)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    precondition(condition(), "Volume check timed out")
  }
  wait { notes.previewReady }
  let view = notes.preview!
  func js(_ script: String) -> Any? {
    var done = false
    var result: Any?
    var failure: Error?
    view.evaluateJavaScript(script) { value, error in result = value; failure = error; done = true }
    wait { done }
    precondition(failure == nil, "Volume JavaScript failed: \(String(describing: failure))")
    return result
  }
  let paragraph = """
  ## Проверка заметки
  Най**ти** слово и найти слово. Русский текст, Unicode 🙂, **жирный**, *курсив* и `код`.

  > Строка цитаты с пояснением и дополнительным текстом для проверки объёма.

  - [ ] Проверить отображение

  | Столбец | Значение |
  | --- | --- |
  | Текст | 123 |

  """
  for repeats in [1, 16, 128, 1024] {
    let source = String(repeating: paragraph + "\n\n", count: repeats) + "\n$$x^2 + \\frac{1}{2}$$\n"
    notes.editor.string = source
    notes.renderMarkdown()
    precondition(js("document.querySelectorAll('#body h2').length") as? Int == repeats)
    precondition(js("document.querySelector('#body .katex') !== null && document.querySelectorAll('#body .math-error').length === 0") as? Bool == true)
    let html = js("document.getElementById('body').innerHTML") as! String
    notes.setNoteFindExpanded(true, animated: false)
    notes.noteFindField.stringValue = "найти слово"
    notes.updateNoteFind(reset: true, scroll: true)
    wait { notes.noteFindCount == repeats * 2 }
    notes.previousNoteMatch()
    wait { notes.noteFindIndex == repeats * 2 - 1 }
    precondition(js("document.getElementById('body').getBoundingClientRect().height > 0") as? Bool == true)
    if repeats > 1 { precondition(js("document.scrollingElement.scrollTop > 0") as? Bool == true) }
    notes.setNoteFindExpanded(false, animated: false)
    precondition(js("(!window.CSS || !CSS.highlights || (!CSS.highlights.has('note-matches') && !CSS.highlights.has('note-current'))) && document.querySelectorAll('[data-note-find]').length === 0") as? Bool == true)
    precondition(js("document.getElementById('body').innerHTML") as? String == html, "Find must preserve rendered DOM")
    precondition(notes.editor.string == source && !notes.dirty)
    var snapshot: NSImage?
    var snapshotDone = false
    view.takeSnapshot(with: nil) { image, error in
      precondition(error == nil && image != nil, "WebKit must produce a snapshot after search")
      snapshot = image
      snapshotDone = true
    }
    wait { snapshotDone }
    let snapshotURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("volume-\(repeats).tiff")
    try! snapshot!.tiffRepresentation!.write(to: snapshotURL)
    print("Volume checks passed: \(source.utf8.count) bytes, \(repeats * 2) matches")
  }
}
