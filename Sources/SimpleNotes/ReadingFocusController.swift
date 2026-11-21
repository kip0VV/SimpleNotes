import Cocoa

/// Reuse the live preview, preserving its scroll position, tasks and zoom.
final class ReadingFocusController {
  private(set) var isActive = false
  private var host: NSView?
  private var overlay: NSView?
  private var preview: NSView?
  private var button: NSView?
  private var originalParent: NSView?
  private var savedConstraints: [NSLayoutConstraint] = []
  private var hiddenViews: [(NSView, Bool)] = []

  func enter(preview: NSView, button: NSView, in host: NSView) {
    guard !isActive, let parent = preview.superview, button.superview === parent else { return }
    self.host = host
    self.preview = preview
    self.button = button
    originalParent = parent
    savedConstraints = parent.constraints.filter {
      ($0.firstItem as? NSView) === preview || ($0.secondItem as? NSView) === preview
        || ($0.firstItem as? NSView) === button || ($0.secondItem as? NSView) === button
    }
    hiddenViews = host.subviews.map { ($0, $0.isHidden) }
    NSLayoutConstraint.deactivate(savedConstraints)
    preview.removeFromSuperview()
    button.removeFromSuperview()
    hiddenViews.forEach { $0.0.isHidden = true }
    let overlay = NSView()
    overlay.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(overlay)
    overlay.addSubview(preview)
    overlay.addSubview(button)
    NSLayoutConstraint.activate([
      overlay.leadingAnchor.constraint(equalTo: host.leadingAnchor),
      overlay.trailingAnchor.constraint(equalTo: host.trailingAnchor),
      overlay.topAnchor.constraint(equalTo: host.topAnchor),
      overlay.bottomAnchor.constraint(equalTo: host.bottomAnchor),
      preview.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
      preview.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
      preview.topAnchor.constraint(equalTo: overlay.topAnchor),
      preview.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),
      button.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -12),
      button.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -12),
    ])
    self.overlay = overlay
    isActive = true
    host.layoutSubtreeIfNeeded()
  }

  func exit() {
    guard isActive, let parent = originalParent, let preview = preview, let button = button else { return }
    if let overlay = overlay { NSLayoutConstraint.deactivate(overlay.constraints) }
    preview.removeFromSuperview()
    button.removeFromSuperview()
    overlay?.removeFromSuperview()
    parent.addSubview(preview)
    parent.addSubview(button)
    NSLayoutConstraint.activate(savedConstraints)
    hiddenViews.forEach { $0.0.isHidden = $0.1 }
    isActive = false
    host?.layoutSubtreeIfNeeded()
    host = nil; overlay = nil; self.preview = nil; self.button = nil; originalParent = nil
    savedConstraints = []; hiddenViews = []
  }
}
