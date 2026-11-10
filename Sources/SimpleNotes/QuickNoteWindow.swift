import Cocoa

extension NotesApp {
  func configureQuickChrome(in view: NSView) {
    expandButton.target = self
    expandButton.action = #selector(expandQuickNote)
    expandButton.bezelStyle = .inline
    expandButton.controlSize = .small
    expandButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    expandButton.setContentHuggingPriority(.required, for: .horizontal)
    quickTopics.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    (quickTopics.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
    quickTopics.target = self
    quickTopics.action = #selector(selectQuickTopic)
    quickTopics.setAccessibilityLabel("Папка быстрой записи")
    quickTopics.bezelStyle = .inline
    quickMore.addItem(withTitle: "⋯")
    quickMore.addItem(withTitle: "Открыть обычное окно")
    quickMore.lastItem?.target = self
    quickMore.lastItem?.action = #selector(expandQuickNote)
    quickMore.addItem(withTitle: "Новая быстрая запись")
    quickMore.lastItem?.target = self
    quickMore.lastItem?.action = #selector(startNextQuickNote)
    quickMore.addItem(withTitle: "Настройки…")
    quickMore.lastItem?.target = self
    quickMore.lastItem?.action = #selector(showSettings)
    quickMore.bezelStyle = .inline
    quickMore.setAccessibilityLabel("Действия быстрой записи")
    let formatting = NSMenu(title: "Форматирование")
    for (title, tag) in [("Жирный", 1), ("Курсив", 2), ("Список", 3),
                          ("Задачи", 5), ("Цитата", 6), ("Ссылка…", 8)] {
      let item = NSMenuItem(title: title, action: #selector(quickFormatAction(_:)), keyEquivalent: "")
      item.tag = tag
      item.target = self
      formatting.addItem(item)
    }
    let formattingItem = NSMenuItem(title: "Форматирование", action: nil, keyEquivalent: "")
    formattingItem.submenu = formatting
    quickMore.menu?.addItem(formattingItem)
    quickStatus.font = .systemFont(ofSize: 11)
    quickStatus.textColor = .secondaryLabelColor
    quickStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    quickStatus.lineBreakMode = .byTruncatingTail
    quickChrome = [quickTopics, expandButton, quickMore, quickStatus]
    for control in quickChrome {
      control.translatesAutoresizingMaskIntoConstraints = false
      control.isHidden = true
      view.addSubview(control)
    }
  }

  @objc func quickFormatAction(_ sender: NSMenuItem) {
    let control = NSButton()
    control.tag = sender.tag
    formatText(control)
  }

  @objc func startNextQuickNote() { openQuickNote() }

  func syncQuickTopics() {
    quickTopics.menu = topics.menu?.copy() as? NSMenu
    quickTopics.selectItem(at: topics.indexOfSelectedItem)
  }

  @objc func selectQuickTopic() {
    guard let path = quickTopics.selectedItem?.representedObject as? String,
      let item = topics.itemArray.first(where: { $0.representedObject as? String == path }) else {
      syncQuickTopics()
      return
    }
    topics.select(item)
    topicChanged()
    quickTopicChanged = true
    persistDraft()
    scheduleQuickSave()
  }

  func scheduleQuickSave() {
    guard quickMode else { return }
    quickSaveTimer?.invalidate()
    quickSaveTimer = nil
    guard dirty, !editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || currentURL != nil else {
      quickStatus.stringValue = currentURL == nil ? "Сохраняется автоматически" : "✓ Сохранено"
      return
    }
    quickStatus.stringValue = "Сохранение…"
    quickSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
      self?.flushQuickSave()
    }
  }

  func flushQuickSave() {
    quickSaveTimer?.invalidate()
    quickSaveTimer = nil
    guard quickMode else { return }
    guard dirty else {
      quickStatus.stringValue = currentURL == nil ? "Сохраняется автоматически" : "✓ Сохранено"
      return
    }
    guard !editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || currentURL != nil else {
      quickStatus.stringValue = "Сохраняется автоматически"
      return
    }
    let selection = editor.selectedRange()
    if saveCurrent(preservingExistingFile: !quickTopicChanged) {
      quickTopicChanged = false
      quickStatus.stringValue = "✓ Сохранено"
    } else {
      quickStatus.stringValue = "Не сохранено · ⌘↩"
    }
    editor.setSelectedRange(selection)
    editor.needsDisplay = true
  }

  func openQuickNote() {
    guard startupComplete, window != nil else {
      pendingQuickNote = true
      return
    }
    if quickMode { flushQuickSave() }
    guard canLeaveNote() else { return }
    resetNoteForWriting()
    quickAutomaticTitle = true
    quickTopicChanged = false
    syncQuickTopics()
    quickStatus.stringValue = "Сохраняется автоматически"
    editor.quickPlaceholder = true
    guard !quickMode, let main = editorScroll.superview else {
      showWindow()
      window.makeFirstResponder(editor)
      return
    }
    regularFrame = window.frame
    window.setFrameAutosaveName("")
    hoverTimer?.invalidate()
    animationGeneration += 1
    quickMode = true
    NSLayoutConstraint.deactivate(regularConstraints)
    titleHeight.isActive = false
    regularHiddenViews.forEach { $0.isHidden = true }
    sidebarView.isHidden = true
    sideHandle.isHidden = true
    mainTrailing.constant = 0
    quickChrome.forEach { $0.isHidden = false }
    editorScroll.isHidden = false
    editorScroll.borderType = .noBorder
    editor.textContainerInset = NSSize(width: 16, height: 14)
    NSLayoutConstraint.activate(quickConstraints)
    window.minSize = NSSize(width: 380, height: 260)
    window.title = "Быстрая запись"
    window.setContentSize(NSSize(width: 470, height: 340))
    main.layoutSubtreeIfNeeded()
    showWindow()
    window.makeFirstResponder(editor)
  }

  @objc func expandQuickNote() {
    guard quickMode else { return }
    flushQuickSave()
    quickAutomaticTitle = false
    quickMode = false
    editor.quickPlaceholder = false
    NSLayoutConstraint.deactivate(quickConstraints)
    quickChrome.forEach { $0.isHidden = true }
    regularHiddenViews.forEach { $0.isHidden = false }
    NSLayoutConstraint.activate(regularConstraints)
    titleHeight.isActive = true
    editorScroll.borderType = .bezelBorder
    editor.textContainerInset = NSSize(width: 12, height: 12)
    window.minSize = NSSize(width: 850, height: 500)
    window.title = "SimpleNotes"
    window.setFrame(regularFrame, display: true)
    window.setFrameAutosaveName("NotesWindowLayout")
    setMenuVisible(!defaults.bool(forKey: "sidebarHidden"))
    changeMode()
    window.makeFirstResponder(editor)
  }
}
