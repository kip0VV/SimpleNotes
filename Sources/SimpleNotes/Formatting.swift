import Cocoa

extension NotesApp {
  func makeFormattingBar() -> NSStackView {
    let groups: [(String, [(String, Int)])] = [
      ("Текст", [("Жирный", 1), ("Курсив", 2)]),
      (
        "Заголовок",
        [("Крупный заголовок", 101), ("Средний заголовок", 102), ("Малый заголовок", 103)]
      ),
      ("Список", [("Маркированный список", 3), ("Нумерованный список", 4), ("Список задач", 5)]),
      ("Вставить", [("Цитата", 6), ("Код", 7), ("Ссылка…", 8)]),
    ]
    let controls: [NSView] = groups.map { title, items in
      let popup = NSPopUpButton(frame: .zero, pullsDown: true)
      popup.addItem(withTitle: title)
      for (name, tag) in items {
        popup.addItem(withTitle: name)
        popup.lastItem?.tag = tag
      }
      popup.target = self
      popup.action = #selector(formatText(_:))
      popup.setAccessibilityLabel(title)
      return popup
    }
    let bar = NSStackView(views: controls)
    bar.spacing = 8
    bar.alignment = .centerY
    bar.setAccessibilityLabel("Форматирование заметки")
    return bar
  }

  @objc func formatText(_ sender: NSControl) {
    let tag = (sender as? NSPopUpButton)?.selectedItem?.tag ?? sender.tag
    guard tag > 0 else { return }
    mode.selectedSegment = 0
    changeMode()
    let text = editor.string as NSString
    var range = editor.selectedRange()
    guard NSMaxRange(range) <= text.length else { return }
    var selected = text.substring(with: range)
    var replacement = ""
    var selection = NSRange(location: 0, length: 0)
    if tag >= 100 || (3...6).contains(tag) {
      range = text.lineRange(for: range)
      selected = text.substring(with: range)
      let trailingNewline = selected.hasSuffix("\n")
      var lines = selected.components(separatedBy: "\n")
      if trailingNewline { lines.removeLast() }
      if lines == [""] { lines = [tag >= 100 ? "Заголовок" : "Текст"] }
      let prefixes: [Int: String] = [3: "- ", 5: "- [ ] ", 6: "> "]
      replacement =
        lines.enumerated().map { index, line in
          let prefix: String
          if tag >= 100 {
            prefix = String(repeating: "#", count: tag - 100) + " "
          } else if tag == 4 {
            prefix = "\(index + 1). "
          } else {
            prefix = prefixes[tag] ?? ""
          }
          return prefix + line
        }.joined(separator: "\n") + (trailingNewline ? "\n" : "")
      selection = NSRange(location: 0, length: (replacement as NSString).length)
    } else {
      if selected.isEmpty { selected = tag == 8 ? "Текст ссылки" : "Текст" }
      let prefix: String
      let suffix: String
      switch tag {
      case 1:
        prefix = "**"
        suffix = "**"
      case 2:
        prefix = "*"
        suffix = "*"
      case 7:
        prefix = selected.contains("\n") ? "```\n" : "`"
        suffix = selected.contains("\n") ? "\n```" : "`"
      default:
        let alert = NSAlert()
        alert.messageText = "Добавить ссылку"
        alert.informativeText = "Введи адрес страницы"
        let address = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 26))
        address.placeholderString = "https://example.com"
        alert.accessoryView = address
        alert.addButton(withTitle: "Вставить")
        alert.addButton(withTitle: "Отмена")
        alert.window.initialFirstResponder = address
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let url = address.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        prefix = "["
        suffix = "](<" + url.replacingOccurrences(of: ">", with: "%3E") + ">)"
      }
      replacement = prefix + selected + suffix
      selection = NSRange(
        location: (prefix as NSString).length, length: (selected as NSString).length)
    }
    editor.insertText(replacement, replacementRange: range)
    editor.setSelectedRange(
      NSRange(location: range.location + selection.location, length: selection.length))
    editor.scrollRangeToVisible(editor.selectedRange())
    window.makeFirstResponder(editor)
  }
}
