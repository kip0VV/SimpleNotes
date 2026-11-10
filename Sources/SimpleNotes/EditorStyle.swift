import Cocoa
import UniformTypeIdentifiers

struct EditorStyle: Codable {
  var fontName: String
  var fontSize: Double
  var background: String?
  var foreground: String?

  var valid: Bool {
    (10...28).contains(fontSize) && fontSize.isFinite
      && NSFont(name: fontName, size: fontSize) != nil
      && [background, foreground].allSatisfy { $0 == nil || Self.color($0!) != nil }
  }
  static func color(_ hex: String) -> NSColor? {
    guard hex.count == 7, hex.first == "#", let rgb = UInt32(hex.dropFirst(), radix: 16) else { return nil }
    return NSColor(srgbRed: Double((rgb >> 16) & 255) / 255,
      green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, alpha: 1)
  }
}

extension NotesApp {
  var editorStyle: EditorStyle? {
    guard let data = defaults.data(forKey: "editorStyle"),
      let style = try? JSONDecoder().decode(EditorStyle.self, from: data), style.valid else { return nil }
    return style
  }
  func applyEditorStyle() {
    let style = editorStyle
    editor.font = style.flatMap { NSFont(name: $0.fontName, size: $0.fontSize * noteZoom) }
      ?? .systemFont(ofSize: 16 * noteZoom)
    editor.backgroundColor = style?.background.flatMap(EditorStyle.color) ?? .textBackgroundColor
    editor.textColor = style?.foreground.flatMap(EditorStyle.color) ?? .textColor
    editor.insertionPointColor = editor.textColor ?? .textColor
    lastPreviewPayload = nil
    if mode.selectedSegment == 1 { renderMarkdown() }
  }
  @objc func chooseEditorFont() {
    NSFontManager.shared.target = self
    NSFontManager.shared.setSelectedFont(editor.font ?? .systemFont(ofSize: 16), isMultiple: false)
    NSFontManager.shared.orderFrontFontPanel(nil)
  }
  @objc func changeFont(_ sender: NSFontManager) {
    let current = editorStyle
    let base = current.flatMap { NSFont(name: $0.fontName, size: $0.fontSize) } ?? .systemFont(ofSize: 16)
    let font = sender.convert(base)
    let style = EditorStyle(fontName: font.fontName, fontSize: min(28, max(10, font.pointSize)),
      background: current?.background, foreground: current?.foreground)
    defaults.set(try? JSONEncoder().encode(style), forKey: "editorStyle")
    applyEditorStyle()
  }
  @objc func importEditorStyle() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.message = "Стиль редактора: JSON с fontName, fontSize и необязательными background / foreground (#RRGGBB)."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let data = try Data(contentsOf: url)
      let style = try JSONDecoder().decode(EditorStyle.self, from: data)
      guard style.valid else { showError("Проверь шрифт, размер от 10 до 28 и цвета #RRGGBB."); return }
      defaults.set(try JSONEncoder().encode(style), forKey: "editorStyle")
      applyEditorStyle()
    } catch { showError("Не удалось загрузить стиль: \(error.localizedDescription)") }
  }
  @objc func resetEditorStyle() {
    defaults.removeObject(forKey: "editorStyle")
    applyEditorStyle()
  }
}
