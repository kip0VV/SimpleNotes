import Cocoa
import WebKit

func runColorRenderChecks() {
  let notes = NotesApp()
  notes.window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 450), styleMask: [.titled], backing: .buffered, defer: false)
  notes.window.contentView!.addSubview(notes.previewContainer)
  notes.previewContainer.frame = notes.window.contentView!.bounds
  let previous = notes.defaults.string(forKey: "appearance")
  defer { notes.defaults.set(previous, forKey: "appearance") }
  notes.defaults.set("graphite", forKey: "appearance")
  notes.applyTheme()
  notes.editor.string = "[# **Заголовок** $x^2$]{topic}\n\n## [Второй]{text-blue}\n\n[Тема]{topic} [определение]{definition} [[Цветное слово]{text-green}]{bg-yellow} $x^2$"
  notes.mode.selectedSegment = 1
  notes.renderMarkdown()
  func wait(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(6)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    precondition(condition(), "Color render timeout")
  }
  wait { notes.previewReady }
  func js(_ script: String) -> Any? {
    var done = false
    var result: Any?
    notes.preview!.evaluateJavaScript(script) { value, error in
      precondition(error == nil, "Color renderer JS error: \(String(describing: error))")
      result = value; done = true
    }
    wait { done }
    return result
  }
  precondition(js("document.querySelectorAll('.note-color').length") as? Int == 6)
  precondition(js("document.querySelectorAll('.katex').length") as? Int == 2)
  precondition(js("getComputedStyle(document.querySelector('.note-topic')).color !== getComputedStyle(document.body).color") as? Bool == true)
  precondition(js("getComputedStyle(document.querySelector('.note-definition')).backgroundColor !== 'rgba(0, 0, 0, 0)'") as? Bool == true)
  precondition(js("document.querySelector('#body h1 .note-topic strong').textContent") as? String == "Заголовок", "Wrapped source heading is a real colored h1 with bold text")
  precondition(js("document.querySelector('#body h2 .note-text-blue').textContent") as? String == "Второй")
  let webView = notes.preview
  for (theme, color) in [("matteOrange", "rgb(33, 28, 24)"), ("graphite", "rgb(23, 27, 34)"), ("matteOrange", "rgb(33, 28, 24)")] {
    notes.defaults.set(theme, forKey: "appearance")
    notes.applyTheme()
    precondition(notes.preview === webView, "Theme change keeps existing document")
    precondition(js("getComputedStyle(document.documentElement).backgroundColor") as? String == color, "Root background updates with theme")
    precondition(js("getComputedStyle(document.body).backgroundColor") as? String == color)
    precondition(js("window.findInNote('Цветное слово',0,false).count") as? Int == 1)
    _ = js("window.findInNote('',0,false)")
    precondition(js("document.querySelectorAll('.note-color').length") as? Int == 6, "Search clearing preserves permanent colors")
  }
  print("PASS: actual WebKit color styles, nested foreground/background, formulas, search clearing, live theme changes including root background")
}
