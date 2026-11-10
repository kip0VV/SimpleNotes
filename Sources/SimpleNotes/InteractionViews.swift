import Cocoa
import QuartzCore
import WebKit

struct HorizontalSwipe {
  var horizontal: CGFloat = 0
  var vertical: CGFloat = 0
  var recognized = false
  var lastTime: TimeInterval = 0
  mutating func update(x: CGFloat, y: CGFloat, time: TimeInterval, began: Bool, ended: Bool)
    -> CGFloat?
  {
    if began || time - lastTime > 0.3 {
      horizontal = 0
      vertical = 0
      recognized = false
    }
    lastTime = time
    if ended {
      horizontal = 0
      vertical = 0
      recognized = false
      return nil
    }
    horizontal += x
    vertical += y
    guard !recognized, abs(horizontal) >= 16, abs(horizontal) > abs(vertical) * 1.35 else {
      return nil
    }
    recognized = true
    return horizontal
  }
}

final class ResizeHandle: NSView {
  var vertical = true
  var beginResize: (() -> Void)?
  var resize: ((CGFloat) -> Void)?
  override func resetCursorRects() {
    addCursorRect(bounds, cursor: vertical ? .resizeLeftRight : .resizeUpDown)
  }
  override func draw(_ dirtyRect: NSRect) {
    NSColor.separatorColor.setFill()
    let bar =
      vertical
      ? NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height)
      : NSRect(x: 0, y: bounds.midY - 0.5, width: bounds.width, height: 1)
    bar.fill()
    NSColor.tertiaryLabelColor.setFill()
    let grip =
      vertical
      ? NSRect(x: bounds.midX - 1.5, y: bounds.midY - 18, width: 3, height: 36)
      : NSRect(x: bounds.midX - 18, y: bounds.midY - 1.5, width: 36, height: 3)
    NSBezierPath(roundedRect: grip, xRadius: 1.5, yRadius: 1.5).fill()
  }
  override func mouseDown(with event: NSEvent) {
    let start = event.locationInWindow
    beginResize?()
    while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
      if next.type == .leftMouseUp { break }
      let current = next.locationInWindow
      resize?(vertical ? current.x - start.x : current.y - start.y)
    }
  }
}
final class HoverContent: NSView {
  var moved: ((NSPoint) -> Void)?
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach { removeTrackingArea($0) }
    addTrackingArea(
      NSTrackingArea(
        rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
  }
  override func mouseMoved(with event: NSEvent) {
    moved?(convert(event.locationInWindow, from: nil))
  }
}

final class DropGuide: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
final class SnapOutline: NSOutlineView {
  let guide = DropGuide()
  func showGuide(at y: CGFloat, indent: CGFloat) {
    if guide.superview == nil {
      guide.wantsLayer = true
      guide.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
      guide.layer?.cornerRadius = 1.5
      addSubview(guide)
    }
    let frame = NSRect(x: indent, y: y - 1.5, width: max(30, bounds.width - indent - 8), height: 3)
    let wasHidden = guide.isHidden || guide.frame == .zero
    guide.isHidden = false
    if wasHidden {
      guide.frame = frame
    } else {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.12
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        guide.animator().frame = frame
      }
    }
  }
  override func draggingExited(_ sender: NSDraggingInfo?) {
    guide.isHidden = true
    super.draggingExited(sender)
  }
}

// Text views receive touch events directly, including while editing or selecting text.
final class NotesTextView: NSTextView {
  var gestureHandler: ((NSEvent) -> Bool)?
  @objc func undo(_ sender: Any?) {
    guard undoManager?.canUndo == true else { return }
    undoManager?.undo()
    didChangeText()
  }
  @objc func redo(_ sender: Any?) {
    guard undoManager?.canRedo == true else { return }
    undoManager?.redo()
    didChangeText()
  }
  override func scrollWheel(with event: NSEvent) {
    if gestureHandler?(event) != true { super.scrollWheel(with: event) }
  }
  override func swipe(with event: NSEvent) {
    if gestureHandler?(event) != true { super.swipe(with: event) }
  }
  override func touchesBegan(with event: NSEvent) {
    _ = gestureHandler?(event)
    super.touchesBegan(with: event)
  }
  override func touchesMoved(with event: NSEvent) {
    _ = gestureHandler?(event)
    super.touchesMoved(with: event)
  }
  override func touchesEnded(with event: NSEvent) {
    _ = gestureHandler?(event)
    super.touchesEnded(with: event)
  }
  override func touchesCancelled(with event: NSEvent) {
    _ = gestureHandler?(event)
    super.touchesCancelled(with: event)
  }
}
