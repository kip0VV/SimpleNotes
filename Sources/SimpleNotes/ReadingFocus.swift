import Cocoa

extension NotesApp {
  func configureReadingFocusButton() {
    readingFocusButton.target = self
    readingFocusButton.action = #selector(toggleReadingFocus)
    readingFocusButton.imagePosition = .imageOnly
    readingFocusButton.isBordered = false
    readingFocusButton.wantsLayer = true
    readingFocusButton.layer?.cornerRadius = 7
    NSLayoutConstraint.activate([
      readingFocusButton.widthAnchor.constraint(equalToConstant: 30),
      readingFocusButton.heightAnchor.constraint(equalToConstant: 28),
    ])
    updateReadingFocusButton()
  }

  func updateReadingFocusButton() {
    let active = readingFocus.isActive
    let title = active ? "Вернуться к заметке" : "Рендер на всё окно"
    readingFocusButton.image = NSImage(systemSymbolName:
      active ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
      accessibilityDescription: title)
    readingFocusButton.contentTintColor = .secondaryLabelColor
    readingFocusButton.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.9).cgColor
    readingFocusButton.setAccessibilityLabel(title)
    let action = noteActions.first { $0.id == "readingFocus" }
    let binding = action.map { actionBinding($0).0.isEmpty ? "" : " · " + bindingLabel($0) } ?? ""
    readingFocusButton.toolTip = title + binding + (active ? " · Esc" : "")
  }

  @objc func toggleReadingFocus() {
    if readingFocus.isActive { leaveReadingFocus(); return }
    if quickMode { expandQuickNote() }
    guard let host = window.contentView else { return }
    readingFocusPreviousMode = mode.selectedSegment
    mode.selectedSegment = 1
    changeMode()
    hoverTimer?.invalidate()
    hoverTimer = nil
    pendingVisibility = nil
    animationGeneration += 1
    readingFocus.enter(preview: previewContainer, button: readingFocusButton, in: host)
    updateReadingFocusButton()
    updateReadingFocusStyle()
    window.makeFirstResponder((preview as NSView?) ?? readingFocusButton)
  }

  func leaveReadingFocus() {
    guard readingFocus.isActive else { return }
    readingFocus.exit()
    mode.selectedSegment = readingFocusPreviousMode
    updateReadingFocusButton()
    updateReadingFocusStyle()
    changeMode()
    windowDidResize(Notification(name: NSWindow.didResizeNotification, object: window))
    window.makeFirstResponder(mode.selectedSegment == 0 ? editor : ((preview as NSView?) ?? readingFocusButton))
  }

  func updateReadingFocusStyle() {
    preview?.evaluateJavaScript("document.body.classList.toggle('reading-focus', \(readingFocus.isActive ? "true" : "false"))", completionHandler: nil)
  }
}
