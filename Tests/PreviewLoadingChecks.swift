import Cocoa
import WebKit

func runPreviewLoadingChecks() throws {
  let notes = NotesApp()
  notes.window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 450), styleMask: [.titled], backing: .buffered, defer: false)
  notes.window.contentView!.addSubview(notes.previewContainer)
  notes.previewContainer.frame = notes.window.contentView!.bounds
  notes.mode.selectedSegment = 1
  let unit = "## Формулы\n\n$$\\int_0^1 x^2\\,dx=\\frac{1}{3}$$\n\n"
  notes.editor.string = String(repeating: unit, count: 1000)
  let source = notes.editor.string
  func wait(_ condition: () -> Bool, timeout: TimeInterval = 15) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    precondition(condition(), "Preview loading timeout")
  }
  func js(_ expression: String) -> Any? {
    var result: Any?
    var done = false
    notes.preview!.evaluateJavaScript(expression) { value, error in precondition(error == nil); result = value; done = true }
    wait { done }
    return result
  }
  let started = Date()
  notes.renderMarkdown()
  notes.window.contentView!.layoutSubtreeIfNeeded()
  precondition(!notes.previewStatus.isHidden && notes.previewStatus.retry.isHidden)
  precondition(notes.previewStatus.message.stringValue == "Загружаем заметку…")
  precondition(notes.previewStatus.bounds.width == notes.previewContainer.bounds.width && notes.previewStatus.bounds.height > 100,
               "Loading overlay must have a visible frame, not only a hidden label")
  precondition(notes.previewStatus.message.window === notes.window && notes.previewStatus.message.bounds.width > 0)
  wait { notes.previewReady && notes.previewStatus.isHidden }
  precondition(js("document.querySelectorAll('#body .katex').length") as? Int == 1000)
  precondition(js("document.querySelectorAll('#body .math-error').length") as? Int == 0)
  let heavySeconds = Date().timeIntervalSince(started)
  let first = notes.preview!
  notes.renderMarkdown()
  precondition(notes.preview === first && notes.previewStatus.isHidden, "Cached render must not flash loading")
  // Deliberate runtime fault, not a substitute renderer: exercise the genuine
  // JavaScript exception callback, visible error state, and native Retry button.
  _ = js("window.renderNote = null")
  notes.editor.string = "# Восстановленная заметка\n\n$$a^2+b^2=c^2$$"
  let recoveredSource = notes.editor.string
  notes.renderMarkdown()
  wait { !notes.previewStatus.retry.isHidden && !notes.previewStatus.isHidden }
  precondition(notes.previewStatus.message.stringValue == "Не удалось отобразить заметку")
  precondition(notes.editor.string == recoveredSource, "Render error must preserve source")
  notes.previewStatus.retry.performClick(nil)
  notes.window.contentView!.layoutSubtreeIfNeeded()
  precondition(notes.preview !== first && !notes.previewStatus.isHidden && notes.previewStatus.bounds.width > 100)
  wait { notes.previewReady && notes.previewStatus.isHidden }
  precondition(js("document.querySelector('#body h1')?.textContent === 'Восстановленная заметка' && document.querySelectorAll('#body .katex').length === 1") as? Bool == true)
  precondition(notes.editor.string == recoveredSource)
  // A rapid series of genuine renders cannot let an older completion hide a
  // newer load, or restore the previous note's contents.
  for version in 1...12 {
    notes.editor.string = "# Последняя версия \(version)\n\n$$x_\(version)$$"
    notes.renderMarkdown()
  }
  wait { notes.previewStatus.isHidden }
  precondition(js("document.querySelector('#body h1')?.textContent === 'Последняя версия 12'") as? Bool == true)
  let report = "PASS: native loading view has visible bounds; 1000 real formulas (\(source.utf8.count) bytes) painted in \(String(format: "%.3f", heavySeconds)) s; no cached-render flash; genuine JS exception shows error; native Retry reloads bundled renderer and preserves source; latest completion wins"
  try report.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("preview-loading-results.txt"), atomically: true, encoding: .utf8)
  print(report)
}
