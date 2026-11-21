import Cocoa

final class NoteHistoryController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
  let versions: [NoteVersion]
  let current: NoteVersion
  let restoreVersion: (NoteVersion) throws -> Void
  let table = NSTableView()
  let diff = NSTextView()
  let restore = NSButton(title: "Восстановить", target: nil, action: nil)
  let caption = NSTextField(labelWithString: "")
  let formatter = DateFormatter()

  init(versions: [NoteVersion], current: NoteVersion, restore: @escaping (NoteVersion) throws -> Void) {
    self.versions = versions.reversed()
    self.current = current
    restoreVersion = restore
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = "История — \(current.title)"
    window.minSize = NSSize(width: 700, height: 400)
    window.isReleasedWhenClosed = false
    super.init(window: window)
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    let content = window.contentView!
    let list = NSScrollView()
    list.hasVerticalScroller = true
    list.documentView = table
    table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("version")))
    table.headerView = nil
    table.rowHeight = 52
    table.dataSource = self
    table.delegate = self
    table.setAccessibilityLabel("Сохранённые версии, сначала новые")
    let preview = NSScrollView()
    preview.hasVerticalScroller = true
    preview.documentView = diff
    diff.isEditable = false
    diff.isRichText = true
    diff.isVerticallyResizable = true
    diff.autoresizingMask = [.width]
    diff.textContainer?.widthTracksTextView = true
    diff.textContainerInset = NSSize(width: 12, height: 12)
    caption.stringValue = versions.isEmpty ? "Версии появятся после сохранения заметки." : "Выбранная версия → текущая заметка"
    caption.lineBreakMode = .byTruncatingTail
    self.restore.target = self
    self.restore.action = #selector(restoreSelected)
    let close = NSButton(title: "Закрыть", target: self, action: #selector(closeHistory))
    for item in [list, preview, caption, self.restore, close] {
      item.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(item)
    }
    NSLayoutConstraint.activate([
      list.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
      list.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
      list.bottomAnchor.constraint(equalTo: close.topAnchor, constant: -12),
      list.widthAnchor.constraint(equalToConstant: 235),
      self.restore.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
      self.restore.topAnchor.constraint(equalTo: list.topAnchor),
      caption.leadingAnchor.constraint(equalTo: list.trailingAnchor, constant: 16),
      caption.trailingAnchor.constraint(lessThanOrEqualTo: self.restore.leadingAnchor, constant: -12),
      caption.centerYAnchor.constraint(equalTo: self.restore.centerYAnchor),
      preview.leadingAnchor.constraint(equalTo: caption.leadingAnchor),
      preview.trailingAnchor.constraint(equalTo: self.restore.trailingAnchor),
      preview.topAnchor.constraint(equalTo: self.restore.bottomAnchor, constant: 12),
      preview.bottomAnchor.constraint(equalTo: list.bottomAnchor),
      close.trailingAnchor.constraint(equalTo: self.restore.trailingAnchor),
      close.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
    ])
    table.reloadData()
    if !versions.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
    updatePreview()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func numberOfRows(in tableView: NSTableView) -> Int { versions.count }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let label = NSTextField(wrappingLabelWithString: formatter.string(from: versions[row].timestamp) + "\n" + versions[row].title)
    label.font = .systemFont(ofSize: 12)
    label.maximumNumberOfLines = 2
    return label
  }
  func tableViewSelectionDidChange(_ notification: Notification) { updatePreview() }
  func updatePreview() {
    let row = table.selectedRow
    restore.isEnabled = versions.indices.contains(row)
    guard restore.isEnabled else { return }
    let version = versions[row]
    restore.isEnabled = version.title != current.title || version.body != current.body
    let result = NSMutableAttributedString(string: "")
    let title = "− выбранная версия: \(version.title)\n+ текущая заметка: \(current.title)\n\n"
    result.append(NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
    for line in NoteVersionDiff.lines(from: version.body, to: current.body) {
      let sign = line.kind == .added ? "+ " : line.kind == .removed ? "− " : "  "
      let color: NSColor = line.kind == .added ? .systemGreen : line.kind == .removed ? .systemRed : .labelColor
      result.append(NSAttributedString(string: sign + line.text + "\n", attributes: [
        .foregroundColor: color,
        .backgroundColor: line.kind == .unchanged ? NSColor.clear : color.withAlphaComponent(0.12),
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
      ]))
    }
    diff.textStorage?.setAttributedString(result)
    diff.scrollToBeginningOfDocument(nil)
  }
  @objc func restoreSelected() {
    guard versions.indices.contains(table.selectedRow), restore.isEnabled else { return }
    do {
      try restoreVersion(versions[table.selectedRow])
      closeHistory()
    } catch {
      let alert = NSAlert(error: error)
      if let window = window { alert.beginSheetModal(for: window) }
    }
  }
  @objc func closeHistory() {
    if let window = window, let parent = window.sheetParent { parent.endSheet(window) }
    close()
  }
}
