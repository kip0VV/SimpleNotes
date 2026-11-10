import Cocoa

func runLayoutChecks(notes: NotesApp) {
  notes.window.setContentSize(NSSize(width: 1060, height: 680))
  let outer = notes.window.contentView!
  let sidebar = NSView()
  notes.sidebarView = sidebar
  outer.addSubview(sidebar)
  notes.sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: 280)
  notes.sidebarTrailing = sidebar.trailingAnchor.constraint(equalTo: outer.trailingAnchor)
  let main = NSView()
  outer.addSubview(main)
  notes.mainTrailing = main.trailingAnchor.constraint(equalTo: outer.trailingAnchor, constant: -280)
  notes.headingLabel = NSTextField(labelWithString: "SimpleNotes")
  notes.headerHeight = main.heightAnchor.constraint(equalToConstant: 220)
  notes.titleHeight = notes.titleField.heightAnchor.constraint(equalToConstant: 36)
  notes.rowHeight = notes.topics.heightAnchor.constraint(equalToConstant: 26)
  notes.topicRowWidth = notes.topics.widthAnchor.constraint(equalToConstant: 300)
  notes.savedSidebarWidth = 300
  notes.setMenuVisible(false)
  RunLoop.current.run(until: Date().addingTimeInterval(0.05))
  precondition(!notes.menuVisible && notes.defaults.bool(forKey: "sidebarHidden"), "Sidebar hidden state persists")
  precondition(notes.mainTrailing.constant == 0 && notes.sidebarTrailing.constant == 300,
               "Hiding releases editor width")
  notes.setMenuVisible(true)
  RunLoop.current.run(until: Date().addingTimeInterval(0.05))
  precondition(notes.menuVisible && !notes.defaults.bool(forKey: "sidebarHidden"), "Sidebar revealed state persists")
  precondition(notes.mainTrailing.constant == -300, "Showing reserves sidebar width")
  notes.autoHide.state = .off
  notes.toggleAutoHide()
  precondition(notes.autoHide.state == .on && notes.defaults.bool(forKey: "autoHideSidebar"),
               "Auto-hide setting persists")
  notes.toggleAutoHide()
  precondition(notes.autoHide.state == .off && notes.menuVisible, "Disabling auto-hide reveals sidebar")
  let frame = notes.window.frame
  notes.applyHeaderScale(1.2)
  precondition(abs(notes.headingLabel.font!.pointSize - 28.8) < 0.1 && abs(notes.titleField.font!.pointSize - 24) < 0.1,
               "Header fonts scale proportionally")
  precondition(notes.window.frame == frame && abs(notes.headerHeight.constant - 264) < 0.1,
               "Header resizing keeps outer window size")
  notes.applyTopicScale(1.4)
  precondition(abs(notes.topics.font!.pointSize - 21.84) < 0.01,
               "Topic picker and topic button scale with header")
  precondition(notes.defaults.double(forKey: "topicScale") == 1.4, "Topic scale persists")
  notes.handleHorizontalGesture(delta: 20)
  precondition(notes.menuVisible, "Default swipe reveals menu")
  notes.handleHorizontalGesture(delta: -20)
  precondition(!notes.menuVisible, "Opposite swipe hides menu")
  notes.defaults.set(true, forKey: "reverseSidebarSwipe")
  notes.handleHorizontalGesture(delta: -20)
  precondition(notes.menuVisible, "Reversed swipe preference applies")
  notes.defaults.set(false, forKey: "reverseSidebarSwipe")
  notes.suppressHoverUntil = .distantPast
  notes.manualRevealUntil = .distantPast
  notes.autoHide.state = .on
  notes.handleHover(NSPoint(x: 10, y: 20), in: outer)
  precondition(notes.pendingVisibility == false, "Leaving hold area schedules hide")
  RunLoop.current.run(until: Date().addingTimeInterval(0.85))
  precondition(!notes.menuVisible, "Hover leave delay hides sidebar")
  notes.handleHover(NSPoint(x: outer.bounds.width - 5, y: 20), in: outer)
  precondition(notes.pendingVisibility == true, "Right edge schedules reveal")
  RunLoop.current.run(until: Date().addingTimeInterval(0.5))
  precondition(notes.menuVisible, "Hover reveal delay shows sidebar")

  let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note"))
  notes.outline.addTableColumn(column)
  notes.outline.outlineTableColumn = column
  notes.outline.dataSource = notes
  notes.outline.delegate = notes
  notes.searchField.stringValue = ""
  notes.applySearch()
  let folder = notes.tree.first { $0.isFolder && !$0.children.isEmpty }!
  notes.outline.expandItem(folder, expandChildren: true)
  notes.outline.collapseItem(folder)
  precondition((notes.defaults.stringArray(forKey: "collapsedFolders") ?? []).contains(notes.relativePath(folder.url)),
               "Collapsing a folder saves its state")
  notes.applySearch()
  let restored = notes.findNode(folder.url, in: notes.tree)!
  precondition(!notes.outline.isItemExpanded(restored), "Refresh restores collapsed folders")
  notes.searchField.stringValue = "копия"
  notes.applySearch()
  precondition((notes.defaults.stringArray(forKey: "collapsedFolders") ?? []).contains(notes.relativePath(folder.url)),
               "Search expansion does not overwrite collapsed preference")
  notes.searchField.stringValue = ""
  notes.applySearch()
  let rootFolder = notes.findNode(folder.url, in: notes.tree)!
  let row = notes.outline.row(forItem: rootFolder)
  notes.outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
  notes.applySearch()
  precondition((notes.outline.item(atRow: notes.outline.selectedRow) as? NoteNode)?.url == rootFolder.url,
               "Refreshing preserves outline selection")

  // Every action round-trips a custom binding and a disabled binding to the menu.
  for action in notes.noteActions {
    notes.defaults.set([action.id: ["key": "9", "modifiers": NSEvent.ModifierFlags([.command, .control]).rawValue]],
                       forKey: "actionShortcuts")
    notes.updateActionShortcuts()
    precondition(notes.shortcutMenuItems[action.id]?.keyEquivalent == "9"
      && notes.bindingLabel(action) == "⌃⌘9", "Custom binding for \(action.id)")
    notes.defaults.set([action.id: ["key": "", "modifiers": UInt(0)]], forKey: "actionShortcuts")
    notes.updateActionShortcuts()
    precondition(notes.shortcutMenuItems[action.id]?.keyEquivalent == ""
      && notes.bindingLabel(action) == "Не назначено", "Disabled binding for \(action.id)")
  }
  notes.defaults.removeObject(forKey: "actionShortcuts")
  notes.updateActionShortcuts()
  notes.editor.string = ""
  notes.titleField.stringValue = ""
  notes.dirty = false
  notes.currentURL = nil
  let regularFrame = notes.window.frame
  notes.openQuickNote()
  precondition(notes.quickMode && notes.window.frame.width < regularFrame.width,
    "System command enters compact mode")
  notes.editor.string = "Быстрая мысль 🙂"
  notes.editor.setSelectedRange(NSRange(location: 3, length: 4))
  notes.dirty = true
  notes.expandQuickNote()
  precondition(!notes.quickMode && notes.editor.string == "Быстрая мысль 🙂" && !notes.dirty,
    "Expansion saves and preserves quick text")
  precondition(notes.editor.selectedRange() == NSRange(location: 3, length: 4)
    && notes.window.frame == regularFrame, "Expansion restores frame and selection")
  notes.defaults.set("graphite", forKey: "appearance")
  notes.applyTheme()
  precondition(notes.isGraphite && notes.editor.backgroundColor == GraphitePalette.canvas,
    "Graphite colors apply to editor")
  notes.defaults.set("light", forKey: "appearance")
  notes.applyTheme()
  precondition(!notes.isGraphite && notes.editor.backgroundColor == NSColor.textBackgroundColor,
    "Switching away from graphite restores system colors")
  precondition(EditorStyle(fontName: "Menlo-Regular", fontSize: 16,
    background: "#20242B", foreground: "#E8EAF0").valid, "Valid imported style")
  precondition(!EditorStyle(fontName: "MissingFontXYZ", fontSize: 16).valid
    && !EditorStyle(fontName: "Menlo-Regular", fontSize: 100).valid,
    "Invalid style cannot be applied")
  print("Layout/action checks passed — sidebar, hover delays, swipe direction, proportional sizing, folder expansion/selection, all 35 custom/disabled bindings")
}
