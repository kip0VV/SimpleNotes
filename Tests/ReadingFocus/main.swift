import Cocoa

let app = NSApplication.shared
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
  styleMask: [.titled, .resizable], backing: .buffered, defer: false)
let host = window.contentView!
let main = NSView()
let sidebar = NSView()
let hiddenHandle = NSView()
let preview = NSView()
let text = NSTextView()
text.string = "Unsaved text and scroll state must survive reading mode."
preview.addSubview(text)
let button = NSButton()
for view in [main, sidebar, hiddenHandle] {
  view.translatesAutoresizingMaskIntoConstraints = false
  host.addSubview(view)
}
hiddenHandle.isHidden = true
for view in [preview, button] {
  view.translatesAutoresizingMaskIntoConstraints = false
  main.addSubview(view)
}
let mainConstraints = [
  main.leadingAnchor.constraint(equalTo: host.leadingAnchor),
  main.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -250),
  main.topAnchor.constraint(equalTo: host.topAnchor),
  main.bottomAnchor.constraint(equalTo: host.bottomAnchor),
  preview.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 24),
  preview.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -24),
  preview.topAnchor.constraint(equalTo: main.topAnchor, constant: 200),
  preview.bottomAnchor.constraint(equalTo: main.bottomAnchor, constant: -100),
  button.trailingAnchor.constraint(equalTo: preview.trailingAnchor, constant: -8),
  button.bottomAnchor.constraint(equalTo: preview.bottomAnchor, constant: -8),
  button.widthAnchor.constraint(equalToConstant: 30),
  button.heightAnchor.constraint(equalToConstant: 28),
]
NSLayoutConstraint.activate(mainConstraints)
host.layoutSubtreeIfNeeded()
let focus = ReadingFocusController()
for index in 0..<4 {
  focus.enter(preview: preview, button: button, in: host)
  focus.enter(preview: preview, button: button, in: host) // repeated activation must be harmless
  precondition(focus.isActive && main.isHidden && sidebar.isHidden && hiddenHandle.isHidden)
  precondition(preview.superview !== main && preview.superview === button.superview)
  precondition(preview.bounds.size == host.bounds.size, "Reading must fill the content area")
  window.setContentSize(NSSize(width: 1100 + index * 10, height: 750 + index * 10))
  host.layoutSubtreeIfNeeded()
  precondition(preview.bounds.size == host.bounds.size, "Reading must track window resizing")
  focus.exit()
  focus.exit()
  host.layoutSubtreeIfNeeded()
  precondition(!focus.isActive && !main.isHidden && !sidebar.isHidden && hiddenHandle.isHidden)
  precondition(preview.superview === main && button.superview === main)
  precondition(mainConstraints.allSatisfy(\.isActive), "Restore the original constraints")
  precondition(abs(preview.frame.minY - 100) < 1)
  precondition(text.string == "Unsaved text and scroll state must survive reading mode.")
}
let detached = NSView()
focus.enter(preview: detached, button: button, in: host)
precondition(!focus.isActive && !main.isHidden)
print("PASS: full-window layout, resizing, repeated toggles, exact panel/constraint restoration, preserved note content")
