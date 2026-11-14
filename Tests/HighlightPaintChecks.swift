import Cocoa
import WebKit

func runHighlightPaintChecks() throws {
  let notes = NotesApp()
  notes.window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
  notes.window.contentView!.addSubview(notes.previewContainer)
  notes.previewContainer.frame = notes.window.contentView!.bounds
  notes.editor.string = "Найти слово и найти слово."
  notes.mode.selectedSegment = 1
  notes.renderMarkdown()
  func wait(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(6)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    precondition(condition(), "Highlight paint timeout")
  }
  wait { notes.previewReady }
  func find(_ query: String) {
    var done = false
    let data = try! JSONSerialization.data(withJSONObject: [query, 0, false])
    notes.preview!.evaluateJavaScript("window.findInNote(..." + String(decoding: data, as: UTF8.self) + ")") { _, error in
      precondition(error == nil)
      done = true
    }
    wait { done }
    RunLoop.current.run(until: Date().addingTimeInterval(0.06))
  }
  func coloredPixels(_ name: String) throws -> Int {
    var done = false
    var snapshot: NSImage?
    notes.preview!.takeSnapshot(with: nil) { image, error in precondition(error == nil); snapshot = image; done = true }
    wait { done }
    let bitmap = NSBitmapImageRep(data: snapshot!.tiffRepresentation!)!
    let png = bitmap.representation(using: .png, properties: [:])!
    try png.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("highlight-\(name).png"))
    var colored = 0
    for y in 0..<bitmap.pixelsHigh {
      for x in 0..<bitmap.pixelsWide {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if color.redComponent > color.blueComponent + 0.12 && color.greenComponent > color.blueComponent + 0.06 { colored += 1 }
      }
    }
    return colored
  }
  find("")
  let baseline = try coloredPixels("baseline")
  find("найти слово")
  let active = try coloredPixels("active")
  find("нет совпадений")
  let noMatch = try coloredPixels("no-match")
  find("найти слово")
  find("")
  let cleared = try coloredPixels("cleared")
  let report = "Highlight pixels: baseline=\(baseline), active=\(active), noMatch=\(noMatch), cleared=\(cleared)"
  try report.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("highlight-paint-results.txt"), atomically: true, encoding: .utf8)
  print(report)
  precondition(active > baseline + 100, "Positive control: search highlight is actually painted")
  precondition(noMatch <= baseline + 10 && cleared <= baseline + 10, "No-match and clear must remove PAINTED highlight, not just registry entries")
}
