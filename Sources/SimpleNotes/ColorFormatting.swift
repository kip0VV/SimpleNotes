import Cocoa
import JavaScriptCore

extension NotesApp {
  static func makeColorTransformContext() -> JSContext? {
    guard let context = JSContext() else { return nil }
    for name in ["markdown-it.min", "markdown-math", "note-colors"] {
      guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
        let script = try? String(contentsOf: url, encoding: .utf8) else { return nil }
      context.evaluateScript(script)
      if context.exception != nil { return nil }
    }
    return context
  }

  func makeColorControls() -> [NSView] {
    let control = NSPopUpButton(frame: .zero, pullsDown: true)
    control.addItem(withTitle: "Раскрасить")
    control.setAccessibilityLabel("Раскрасить выделенный текст")
    control.toolTip = "Выдели слова → Раскрасить: стиль, цвет текста или фон."
    func item(_ title: String, _ style: String) -> NSMenuItem {
      let entry = NSMenuItem(title: title, action: #selector(colorText(_:)), keyEquivalent: "")
      entry.target = self
      entry.representedObject = style
      return entry
    }
    func submenu(_ title: String, _ entries: [(String, String)]) {
      let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      let menu = NSMenu(title: title)
      entries.forEach { menu.addItem(item($0.0, $0.1)) }
      parent.submenu = menu
      control.menu?.addItem(parent)
    }
    let colors = [("Оранжевый", "orange"), ("Голубой", "blue"), ("Зелёный", "green"),
                  ("Жёлтый", "yellow"), ("Розовый", "pink"), ("Сиреневый", "purple")]
    submenu("Смысловой стиль", [("Тема · оранжевый текст", "topic"),
      ("Определение · голубой фон", "definition"), ("Важно · жёлтый фон", "important"),
      ("Пример · зелёный текст", "example")])
    submenu("Цвет текста", colors.map { ($0.0, "text-" + $0.1) })
    submenu("Цвет фона", colors.map { ($0.0, "bg-" + $0.1) })
    control.menu?.addItem(.separator())
    control.menu?.addItem(item("Убрать цвет и фон", "clear"))
    return [control]
  }

  @objc func colorText(_ sender: NSMenuItem) {
    guard let style = sender.representedObject as? String else { return }
    if mode.selectedSegment == 1 {
      let source = editor.string
      let note = currentURL
      preview?.evaluateJavaScript("window.getSelection().toString()") { [weak self] value, _ in
        guard let self = self, self.editor.string == source, self.currentURL == note else { return }
        guard let selected = value as? String, !selected.isEmpty,
          let range = source.range(of: selected),
          source.range(of: selected, range: range.upperBound..<source.endIndex) == nil else {
          self.showError("Выдели нужные слова в редакторе. В рендере можно раскрасить уникальный фрагмент обычного текста.")
          return
        }
        self.applyNoteColor(style, range: NSRange(range, in: source))
      }
    } else {
      applyNoteColor(style, range: editor.selectedRange())
    }
  }

  func applyNoteColor(_ style: String, range original: NSRange) {
    let source = editor.string as NSString
    guard original.length > 0, NSMaxRange(original) <= source.length else {
      showError("Сначала выдели слова, которые нужно раскрасить.")
      return
    }
    guard let context = colorTransformContext else {
      showError("Не удалось загрузить обработчик Markdown.")
      return
    }
    guard let result = context.objectForKeyedSubscript("transformNoteColor")?
      .call(withArguments: [source as String, original.location, original.length, style])?.toDictionary() else {
      showError("Не удалось обработать выделение.")
      return
    }
    if let error = result["error"] as? String { showError(error); return }
    guard let replacement = result["text"] as? String, replacement != source as String,
      let start = result["start"] as? Int, let length = result["length"] as? Int else { return }
    mode.selectedSegment = 0
    changeMode()
    let oldUnits = Array((source as String).utf16), newUnits = Array(replacement.utf16)
    var prefix = 0, suffix = 0
    while prefix < min(oldUnits.count, newUnits.count), oldUnits[prefix] == newUnits[prefix] { prefix += 1 }
    while suffix < min(oldUnits.count, newUnits.count) - prefix,
      oldUnits[oldUnits.count - suffix - 1] == newUnits[newUnits.count - suffix - 1] { suffix += 1 }
    let changed = NSRange(location: prefix, length: oldUnits.count - prefix - suffix)
    let fragment = (replacement as NSString).substring(with: NSRange(location: prefix, length: newUnits.count - prefix - suffix))
    editor.insertText(fragment, replacementRange: changed)
    editor.setSelectedRange(NSRange(location: start, length: min(length, (replacement as NSString).length - start)))
    editor.scrollRangeToVisible(editor.selectedRange())
    window.makeFirstResponder(editor)
  }
}
