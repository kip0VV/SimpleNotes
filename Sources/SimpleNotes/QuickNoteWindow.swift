import Cocoa

extension NotesApp {
  func openQuickNote() {
    showWindow()
    guard canLeaveNote() else { return }
    resetNoteForWriting()
    guard !quickMode, let main = editorScroll.superview else { return }
    regularFrame = window.frame
    window.setFrameAutosaveName("")
    hoverTimer?.invalidate()
    quickMode = true
    NSLayoutConstraint.deactivate(regularConstraints)
    titleHeight.isActive = false
    regularHiddenViews.forEach { $0.isHidden = true }
    sidebarView.isHidden = true
    sideHandle.isHidden = true
    mainTrailing.constant = 0
    expandButton.isHidden = false
    editorScroll.isHidden = false
    NSLayoutConstraint.activate(quickConstraints)
    window.minSize = NSSize(width: 500, height: 320)
    window.title = "Быстрая запись — SimpleNotes"
    window.setContentSize(NSSize(width: 560, height: 380))
    main.layoutSubtreeIfNeeded()
    window.makeFirstResponder(titleField)
  }

  @objc func expandQuickNote() {
    guard quickMode else { return }
    quickMode = false
    NSLayoutConstraint.deactivate(quickConstraints)
    regularHiddenViews.forEach { $0.isHidden = false }
    expandButton.isHidden = true
    NSLayoutConstraint.activate(regularConstraints)
    titleHeight.isActive = true
    window.minSize = NSSize(width: 850, height: 500)
    window.title = "SimpleNotes"
    window.setFrame(regularFrame, display: true)
    window.setFrameAutosaveName("NotesWindowLayout")
    setMenuVisible(!defaults.bool(forKey: "sidebarHidden"))
    changeMode()
    window.makeFirstResponder(editor)
  }
}
