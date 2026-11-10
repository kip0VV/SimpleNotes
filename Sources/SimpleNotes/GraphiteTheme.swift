import Cocoa

// Muted blue accents on neutral graphite; colors stay local to this theme.
enum GraphitePalette {
  static let canvas = EditorStyle.color("#171B22")!
  static let surface = EditorStyle.color("#1D232C")!
  static let sidebar = EditorStyle.color("#14191F")!
  static let line = EditorStyle.color("#303C49")!
  static let text = EditorStyle.color("#DFE7EF")!
  static let muted = EditorStyle.color("#93A5B6")!
  static let accent = EditorStyle.color("#9BCBE7")!
  static let selection = EditorStyle.color("#2C4355")!
}

final class GraphiteRowView: NSTableRowView {
  override func drawSelection(in dirtyRect: NSRect) {
    guard UserDefaults.standard.string(forKey: "appearance") == "graphite" else {
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
  var editorBackgroundHex: String { editorStyle?.background ?? (isGraphite ? "#171B22" : "") }
  var editorForegroundHex: String { editorStyle?.foreground ?? (isGraphite ? "#DFE7EF" : "") }

  func applyGraphiteChrome() {
    guard let window = window else { return }
    let graphite = isGraphite
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
