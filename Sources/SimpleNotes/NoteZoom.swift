import Cocoa

extension NotesApp {
  var noteZoom: Double {
    min(2, max(0.5, defaults.object(forKey: "noteZoom") as? Double ?? 1))
  }

  func makeZoomControls() -> NSStackView {
    let icon = NSImageView(
      image: NSImage(
        systemSymbolName: "magnifyingglass", accessibilityDescription: "Масштаб заметки")!)
    let minus = NSButton(title: "−", target: self, action: #selector(zoomOut))
    let plus = NSButton(title: "+", target: self, action: #selector(zoomIn))
    minus.toolTip = "Уменьшить текст заметки"
    plus.toolTip = "Увеличить текст заметки"
    minus.setAccessibilityLabel("Уменьшить масштаб")
    plus.setAccessibilityLabel("Увеличить масштаб")
    zoomLabel.target = self
    zoomLabel.action = #selector(resetZoom)
    zoomLabel.toolTip = "Вернуть масштаб 100%"
    zoomLabel.widthAnchor.constraint(equalToConstant: 62).isActive = true
    let stack = NSStackView(views: [icon, minus, zoomLabel, plus])
    stack.spacing = 4
    return stack
  }

  func applyNoteZoom() {
    applyEditorStyle()
    preview?.pageZoom = noteZoom
    zoomLabel.title = "\(Int((noteZoom * 100).rounded()))%"
  }
  func setNoteZoom(_ value: Double) {
    defaults.set(min(2, max(0.5, value)), forKey: "noteZoom")
    applyNoteZoom()
  }
  @objc func zoomIn() { setNoteZoom((noteZoom * 10).rounded() / 10 + 0.1) }
  @objc func zoomOut() { setNoteZoom((noteZoom * 10).rounded() / 10 - 0.1) }
  @objc func resetZoom() { setNoteZoom(1) }
}
