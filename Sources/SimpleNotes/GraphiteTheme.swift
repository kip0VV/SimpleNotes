import Cocoa

// Two matte palettes: graphite/blue and warm charcoal/orange.
enum GraphitePalette {
  static var canvas: NSColor { EditorStyle.color(UserDefaults.standard.string(forKey: "appearance") == "matteOrange" ? "#211C18" : "#171B22")! }
  static var surface: NSColor { EditorStyle.color(UserDefaults.standard.string(forKey: "appearance") == "matteOrange" ? "#29221D" : "#1D232C")! }
  static var sidebar: NSColor { EditorStyle.color(UserDefaults.standard.string(forKey: "appearance") == "matteOrange" ? "#1B1714" : "#14191F")! }
  static var line: NSColor { EditorStyle.color(UserDefaults.standard.string(forKey: "appearance") == "matteOrange" ? "#514032" : "#303C49")! }
  static var text: NSColor { EditorStyle.color(UserDefaults.standard.string(forKey: "appearance") == "matteOrange" ? "#EEE2D6" : "#DFE7EF")! }
  static var muted: NSColor { EditorStyle.color(UserDefaults.standard.string(forKey: "appearance") == "matteOrange" ? "#B5A18E" : "#93A5B6")! }
  static var accent: NSColor { EditorStyle.color(UserDefaults.standard.string(forKey: "appearance") == "matteOrange" ? "#DCA16C" : "#9BCBE7")! }
  static var selection: NSColor { EditorStyle.color(UserDefaults.standard.string(forKey: "appearance") == "matteOrange" ? "#62442D" : "#2C4355")! }
}

final class GraphiteRowView: NSTableRowView {
  override func drawSelection(in dirtyRect: NSRect) {
    guard ["graphite", "matteOrange"].contains(UserDefaults.standard.string(forKey: "appearance") ?? "") else {
      super.drawSelection(in: dirtyRect)
      return
    }
    guard selectionHighlightStyle != .none else { return }
    let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 2), xRadius: 6, yRadius: 6)
    GraphitePalette.selection.setFill()
    shape.fill()
    GraphitePalette.accent.withAlphaComponent(0.2).setStroke()
    shape.lineWidth = 1
    shape.stroke()
  }
}

extension NotesApp {
  var isGraphite: Bool { defaults.string(forKey: "appearance") == "graphite" }
  var isCustomTheme: Bool { isGraphite || defaults.string(forKey: "appearance") == "matteOrange" }
  var editorBackgroundHex: String { editorStyle?.background ?? (isCustomTheme ? (isGraphite ? "#171B22" : "#211C18") : "") }
  var editorForegroundHex: String { editorStyle?.foreground ?? (isCustomTheme ? (isGraphite ? "#DFE7EF" : "#EEE2D6") : "") }

  func applyGraphiteChrome() {
    guard let window = window else { return }
    let graphite = isCustomTheme
    window.backgroundColor = graphite ? GraphitePalette.surface : .windowBackgroundColor
    window.titlebarAppearsTransparent = graphite
    let outer = window.contentView
    outer?.wantsLayer = true
    outer?.layer?.backgroundColor = graphite ? GraphitePalette.surface.cgColor : nil
    let main = editorScroll?.superview
    main?.wantsLayer = true
    main?.layer?.backgroundColor = graphite ? GraphitePalette.surface.cgColor : nil
    sidebarView?.wantsLayer = true
    sidebarView?.layer?.backgroundColor = graphite ? GraphitePalette.sidebar.cgColor : nil
    sidebarView?.layer?.borderColor = graphite ? GraphitePalette.line.cgColor : nil
    sidebarView?.layer?.borderWidth = graphite ? 1 : 0
    outline.backgroundColor = graphite ? GraphitePalette.sidebar : .controlBackgroundColor
    outline.needsDisplay = true
    outline.enumerateAvailableRowViews { row, _ in row.needsDisplay = true }
    titleField.backgroundColor = graphite ? GraphitePalette.canvas : .textBackgroundColor
    titleField.textColor = graphite ? GraphitePalette.text : .labelColor
    titleField.wantsLayer = true
    titleField.layer?.cornerRadius = graphite ? 7 : 0
    titleField.layer?.borderWidth = graphite ? 1 : 0
    titleField.layer?.borderColor = graphite ? GraphitePalette.line.cgColor : nil
    searchField.backgroundColor = graphite ? GraphitePalette.surface : .textBackgroundColor
    searchField.textColor = graphite ? GraphitePalette.text : .labelColor
    headingLabel?.textColor = graphite ? GraphitePalette.text : .labelColor
    status.textColor = graphite ? GraphitePalette.muted : .secondaryLabelColor
    quickStatus.textColor = graphite ? GraphitePalette.muted : .secondaryLabelColor
    func tintControls(_ view: NSView) {
      if let button = view as? NSButton {
        button.contentTintColor = graphite ? GraphitePalette.accent : nil
      }
      view.subviews.forEach(tintControls)
    }
    if let outer = outer { tintControls(outer) }
    mode.selectedSegmentBezelColor = graphite ? GraphitePalette.selection : nil
    editor.selectedTextAttributes = [
      .backgroundColor: graphite ? GraphitePalette.selection : NSColor.selectedTextBackgroundColor,
      .foregroundColor: graphite ? GraphitePalette.text : NSColor.selectedTextColor,
    ]
  }

  func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
    GraphiteRowView()
  }
}
