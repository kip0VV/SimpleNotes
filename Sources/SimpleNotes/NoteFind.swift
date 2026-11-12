import Cocoa
import QuartzCore

extension NotesApp {
  func makeNoteFindBar() -> NSView {
    noteFindField.placeholderString = "Поиск в этой заметке"
    noteFindField.setAccessibilityLabel("Поиск в этой заметке")
    noteFindField.delegate = self
    noteFindField.target = self
    noteFindField.action = #selector(noteFindChanged)
    noteFindField.sendsSearchStringImmediately = true
    noteFindField.sendsWholeSearchString = false
    noteFindField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    noteFindCounter.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    noteFindCounter.textColor = .secondaryLabelColor
    noteFindCounter.setContentCompressionResistancePriority(.required, for: .horizontal)
    for (button, symbol, label, action) in [
      (noteFindPrevious, "chevron.up", "Предыдущее совпадение · Shift+Enter", #selector(previousNoteMatch)),
      (noteFindNext, "chevron.down", "Следующее совпадение · Enter", #selector(nextNoteMatch)),
    ] {
      button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
      button.toolTip = label
      button.target = self
      button.action = action
      button.bezelStyle = .rounded
      button.isEnabled = false
      button.widthAnchor.constraint(equalToConstant: 28).isActive = true
    }
    let bar = NSStackView(views: [noteFindField, noteFindCounter, noteFindPrevious, noteFindNext])
    bar.orientation = .horizontal
    bar.spacing = 6
    bar.alignment = .centerY
    noteFindField.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
    noteFindCounter.widthAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
    let container = NSView()
    let clip = NSView()
    clip.wantsLayer = true
    clip.layer?.masksToBounds = true
    noteFindToggle.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Поиск в заметке")
    noteFindToggle.bezelStyle = .rounded
    noteFindToggle.target = self
    noteFindToggle.action = #selector(toggleNoteFind)
    noteFindToggle.toolTip = "Поиск в заметке · ⌘F"
    noteFindToggle.setAccessibilityLabel("Открыть поиск в заметке")
    for child in [noteFindToggle, clip] {
      child.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(child)
    }
    bar.translatesAutoresizingMaskIntoConstraints = false
    clip.addSubview(bar)
    let closed = clip.widthAnchor.constraint(equalToConstant: 0)
    let opened = clip.trailingAnchor.constraint(equalTo: container.trailingAnchor)
    NSLayoutConstraint.activate([
      noteFindToggle.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      noteFindToggle.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      noteFindToggle.widthAnchor.constraint(equalToConstant: 28),
      noteFindToggle.heightAnchor.constraint(equalToConstant: 24),
      clip.leadingAnchor.constraint(equalTo: noteFindToggle.trailingAnchor, constant: 6),
      clip.topAnchor.constraint(equalTo: container.topAnchor),
      clip.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      closed,
      bar.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
      bar.centerYAnchor.constraint(equalTo: clip.centerYAnchor),
      bar.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -34),
    ])
    noteFindClip = clip
    noteFindContents = bar
    noteFindClosedWidth = closed
    noteFindOpenTrailing = opened
    bar.isHidden = true
    bar.alphaValue = 0
    return container
  }

  @objc func toggleNoteFind() {
    if noteFindExpanded { setNoteFindExpanded(false) }
    else { focusNoteFind() }
  }

  func setNoteFindExpanded(_ expanded: Bool, animated: Bool = true) {
    guard let clip = noteFindClip, let contents = noteFindContents,
      let closed = noteFindClosedWidth, let opened = noteFindOpenTrailing else { return }
    noteFindAnimation += 1
    let animation = noteFindAnimation
    let parent = clip.superview!
    parent.layoutSubtreeIfNeeded()
    noteFindExpanded = expanded
    noteFindToggle.setAccessibilityLabel(expanded ? "Закрыть поиск в заметке" : "Открыть поиск в заметке")
    noteFindToggle.toolTip = expanded ? "Закрыть поиск · Escape" : "Поиск в заметке · ⌘F"
    if expanded { contents.isHidden = false }
    else {
      noteFindField.stringValue = ""
      updateNoteFind(reset: true)
      if window?.firstResponder === noteFindField.currentEditor() {
        window?.makeFirstResponder(mode.selectedSegment == 0 ? editor : preview)
      }
    }
    let duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.22 : 0
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = duration
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      context.allowsImplicitAnimation = duration > 0
      if expanded { closed.isActive = false; opened.isActive = true }
      else { opened.isActive = false; closed.isActive = true }
      contents.animator().alphaValue = expanded ? 1 : 0
      parent.layoutSubtreeIfNeeded()
    }, completionHandler: { [weak self] in
      guard let self = self, self.noteFindAnimation == animation else { return }
      contents.isHidden = !expanded
    })
  }

  @objc func noteFindChanged() {
    updateNoteFind(reset: true, scroll: true)
  }

  @objc func focusNoteFind() {
    if quickMode { expandQuickNote() }
    setNoteFindExpanded(true)
    window.makeFirstResponder(noteFindField)
    noteFindField.selectText(nil)
  }

  func updateNoteFind(reset: Bool = false, scroll: Bool = false) {
    noteFindGeneration += 1
    let generation = noteFindGeneration
    let query = noteFindField.stringValue
    if reset { noteFindIndex = 0 }
    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      editor.layoutManager?.removeTemporaryAttribute(.backgroundColor,
        forCharacterRange: NSRange(location: 0, length: (editor.string as NSString).length))
      if previewReady { preview?.evaluateJavaScript("window.findInNote('',0,false)", completionHandler: nil) }
      noteFindIndex = 0
      showNoteFindCount(0)
      return
    }
    if mode.selectedSegment == 1, previewReady, let preview = preview {
      guard let data = try? JSONSerialization.data(withJSONObject: [query, noteFindIndex, scroll]),
        let json = String(data: data, encoding: .utf8) else { return }
      preview.evaluateJavaScript("window.findInNote(..." + json.replacingOccurrences(of: "<", with: "\\u003c") + ")") { [weak self] value, error in
        guard let self = self, generation == self.noteFindGeneration else { return }
        let result = value as? [String: Int]
        self.noteFindIndex = result?["index"] ?? 0
        self.showNoteFindCount(result?["count"] ?? 0)
      }
      return
    }
    guard mode.selectedSegment == 0 else { return }
    let source = editor.string as NSString
    let words = query.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    let pattern = words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "\\s+")
    let ranges: [NSRange]
    if !pattern.isEmpty, let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
      ranges = expression.matches(in: editor.string, range: NSRange(location: 0, length: source.length)).map(\.range)
    } else {
      ranges = []
    }
    let whole = NSRange(location: 0, length: source.length)
    editor.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: whole)
    noteFindIndex = ranges.isEmpty ? 0 : ((noteFindIndex % ranges.count) + ranges.count) % ranges.count
    for (index, range) in ranges.enumerated() {
      editor.layoutManager?.addTemporaryAttribute(.backgroundColor,
        value: (index == noteFindIndex ? NSColor.systemOrange : NSColor.systemYellow).withAlphaComponent(0.35),
        forCharacterRange: range)
    }
    if scroll, !ranges.isEmpty {
      editor.scrollRangeToVisible(ranges[noteFindIndex])
    }
    showNoteFindCount(ranges.count)
  }

  func showNoteFindCount(_ count: Int) {
    noteFindCount = count
    noteFindCounter.stringValue = noteFindField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : "\(count == 0 ? 0 : noteFindIndex + 1)/\(count)"
    noteFindCounter.setAccessibilityLabel(count == 0 ? "Совпадений нет" : "Совпадение \(noteFindIndex + 1) из \(count)")
    noteFindPrevious.isEnabled = count > 0
    noteFindNext.isEnabled = count > 0
  }

  @objc func nextNoteMatch() {
    if noteFindCount > 0 { noteFindIndex = (noteFindIndex + 1) % noteFindCount }
    updateNoteFind(scroll: true)
  }
  @objc func previousNoteMatch() {
    if noteFindCount > 0 { noteFindIndex = (noteFindIndex - 1 + noteFindCount) % noteFindCount }
    updateNoteFind(scroll: true)
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    guard control === noteFindField else { return false }
    if commandSelector == #selector(NSResponder.insertNewline(_:)) {
      if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { previousNoteMatch() }
      else { nextNoteMatch() }
      return true
    }
    if commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
      previousNoteMatch()
      return true
    }
    if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
      setNoteFindExpanded(false)
      return true
    }
    return false
  }
}
