import Cocoa

extension NotesApp {
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
    var range = original
    // Keep block heading markers outside the inline color annotation.
    // A line selected with its final newline should not put the closing marker
    // on the following line.
    if style != "clear" {
      while range.length > 0 && ["\n", "\r"].contains(source.substring(with: NSRange(location: NSMaxRange(range) - 1, length: 1))) {
        range.length -= 1
      }
      let line = source.lineRange(for: NSRange(location: range.location, length: 0))
      if line.location == range.location {
        let candidate = source.substring(with: range) as NSString
        let heading = try! NSRegularExpression(pattern: "^ {0,3}#{1,6}[ \t]+")
        if let prefix = heading.firstMatch(in: candidate as String, range: NSRange(location: 0, length: candidate.length)) {
          range.location += prefix.range.length
          range.length -= prefix.range.length
        }
      }
      guard range.length > 0 else { return }
    }
    var selected = source.substring(with: range)
    let pattern = "^\\{(?:topic|definition|important|example|(?:text|bg)-(?:orange|blue|green|yellow|pink|purple))\\}"
    // Changing a style replaces the same kind of surrounding annotation;
    // text and background can be combined by nesting.
    while range.location > 0, source.substring(with: NSRange(location: range.location - 1, length: 1)) == "[",
      NSMaxRange(range) < source.length,
      source.substring(with: NSRange(location: NSMaxRange(range), length: 1)) == "]" {
      let tail = source.substring(from: NSMaxRange(range) + 1)
      guard let suffix = tail.range(of: pattern, options: .regularExpression) else { break }
      let marker = String(tail[suffix])
      let sameKind = style == "clear" || (style.hasPrefix("text-") && marker.hasPrefix("{text-"))
        || (style.hasPrefix("bg-") && marker.hasPrefix("{bg-"))
        || (!["text-", "bg-"].contains(where: { style.hasPrefix($0) }) && !marker.hasPrefix("{text-") && !marker.hasPrefix("{bg-"))
      guard sameKind else { break }
      range = NSRange(location: range.location - 1, length: range.length + 2 + (marker as NSString).length)
    }
    if style == "clear" {
      let regex = try! NSRegularExpression(pattern: "\\[([^\\[\\]]+)\\]\\{(?:topic|definition|important|example|(?:text|bg)-(?:orange|blue|green|yellow|pink|purple))\\}")
      while true {
        let cleaned = regex.stringByReplacingMatches(in: selected, range: NSRange(location: 0, length: (selected as NSString).length), withTemplate: "$1")
        if cleaned == selected { break }
        selected = cleaned
      }
    }
    mode.selectedSegment = 0
    changeMode()
    let replacement = style == "clear" ? selected : "[\(selected)]{\(style)}"
    editor.insertText(replacement, replacementRange: range)
    editor.setSelectedRange(NSRange(location: range.location + (style == "clear" ? 0 : 1), length: (selected as NSString).length))
    editor.scrollRangeToVisible(editor.selectedRange())
    window.makeFirstResponder(editor)
  }
}
