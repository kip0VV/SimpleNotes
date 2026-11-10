import Cocoa

final class RemindersWindowController: NSWindowController, NSTableViewDataSource,
  NSTableViewDelegate, NSSearchFieldDelegate, NSMenuDelegate
{
  unowned let app: NotesApp
  let search = NSSearchField()
  let filter = NSSegmentedControl(
    labels: ["Все", "Сегодня", "7 дней", "С повтором"], trackingMode: .selectOne,
    target: nil, action: nil)
  let sort = NSPopUpButton()
  let table = NSTableView()
  let count = NSTextField(labelWithString: "")
  let openButton = NSButton(title: "Открыть заметку", target: nil, action: nil)
  let editButton = NSButton(title: "Изменить…", target: nil, action: nil)
  let cancelButton = NSButton(title: "Отменить напоминание", target: nil, action: nil)
  private(set) var reminders: [ActiveReminder] = []
  private(set) var displayed: [ActiveReminder] = []
  private var searchWork: DispatchWorkItem?
  private let formatter = DateFormatter()

  init(app: NotesApp) {
    self.app = app
    let window = RemindersWindow(
      contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.title = "Напоминания"
    window.minSize = NSSize(width: 700, height: 400)
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.center()
    window.setFrameAutosaveName("SimpleNotes.Reminders")
    window.searchField = search
    formatter.dateFormat = "dd.MM.yyyy · HH:mm"
    search.placeholderString = "Поиск по заметке или папке"
    search.setAccessibilityLabel("Поиск напоминаний")
    search.delegate = self
    filter.selectedSegment = 0
    filter.target = self
    filter.action = #selector(changeFilter)
    sort.addItems(withTitles: ["Ближайшие сначала", "По названию"])
    sort.target = self
    sort.action = #selector(changeFilter)
    sort.setAccessibilityLabel("Сортировка напоминаний")
    let controls = NSStackView(views: [filter, NSView(), sort])
    controls.distribution = .fill
    controls.spacing = 12
    table.rowHeight = 48
    table.usesAlternatingRowBackgroundColors = true
    table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    for (id, title, width) in [("note", "Заметка", CGFloat(360)), ("date", "Когда", 170), ("repeat", "Повтор", 140)] {
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
      column.title = title
      column.width = width
      column.minWidth = id == "note" ? 180 : 110
      table.addTableColumn(column)
    }
    table.dataSource = self
    table.delegate = self
    table.target = self
    table.doubleAction = #selector(openSelected)
    table.setAccessibilityLabel("Все активные напоминания")
    let menu = NSMenu()
    menu.delegate = self
    table.menu = menu
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.documentView = table
    openButton.target = self
    openButton.action = #selector(openSelected)
    editButton.target = self
    editButton.action = #selector(editSelected)
    cancelButton.target = self
    cancelButton.action = #selector(cancelSelected)
    let buttons = NSStackView(views: [openButton, editButton, NSView(), cancelButton])
    buttons.distribution = .fill
    buttons.spacing = 10
    count.font = .systemFont(ofSize: 12)
    count.textColor = .secondaryLabelColor
    let content = window.contentView!
    for view in [search, controls, scroll, count, buttons] {
      view.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(view)
      view.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20).isActive = true
      view.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20).isActive = true
    }
    NSLayoutConstraint.activate([
      search.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
      search.heightAnchor.constraint(equalToConstant: 28),
      controls.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
      scroll.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 12),
      scroll.bottomAnchor.constraint(equalTo: count.topAnchor, constant: -10),
      count.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -10),
      buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
    ])
    updateButtons()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func refresh(_ reminders: [ActiveReminder]) {
    self.reminders = reminders
    applyFilter()
  }

  @objc func changeFilter() { applyFilter() }

  func controlTextDidChange(_ notification: Notification) {
    searchWork?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.applyFilter() }
    searchWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
  }

  func applyFilter(now: Date = Date()) {
    let selected = selectedReminder?.path
    let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let calendar = Calendar.current
    let weekEnd = calendar.date(byAdding: .day, value: 7, to: now) ?? now
    displayed = reminders.filter { reminder in
      let dateMatches: Bool
      switch filter.selectedSegment {
      case 1: dateMatches = calendar.isDate(reminder.date, inSameDayAs: now)
      case 2: dateMatches = reminder.date < weekEnd
      case 3: dateMatches = reminder.repetition != .none
      default: dateMatches = true
      }
      return dateMatches && (query.isEmpty || reminder.path.range(
        of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
    }.sorted {
      if sort.indexOfSelectedItem == 1 {
        let first = URL(fileURLWithPath: $0.path).deletingPathExtension().lastPathComponent
        let second = URL(fileURLWithPath: $1.path).deletingPathExtension().lastPathComponent
        let comparison = first.localizedStandardCompare(second)
        if comparison != .orderedSame { return comparison == .orderedAscending }
      }
      return $0.date == $1.date
        ? $0.path.localizedStandardCompare($1.path) == .orderedAscending : $0.date < $1.date
    }
    table.reloadData()
    if let selected = selected, let row = displayed.firstIndex(where: { $0.path == selected }) {
      table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    } else {
      table.deselectAll(nil)
    }
    count.stringValue = displayed.isEmpty
      ? (reminders.isEmpty ? "Нет активных напоминаний" : "Ничего не найдено")
      : "Показано \(displayed.count) из \(reminders.count)"
    updateButtons()
  }

  var selectedReminder: ActiveReminder? {
    displayed.indices.contains(table.selectedRow) ? displayed[table.selectedRow] : nil
  }

  func numberOfRows(in tableView: NSTableView) -> Int { displayed.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard displayed.indices.contains(row), let id = tableColumn?.identifier else { return nil }
    let reminder = displayed[row]
    if id.rawValue == "note" {
      let cell: NSTableCellView
      if let reused = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView {
        cell = reused
      } else {
        cell = NSTableCellView()
        cell.identifier = id
        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        let folder = NSTextField(labelWithString: "")
        folder.tag = 1
        folder.font = .systemFont(ofSize: 11)
        folder.textColor = .secondaryLabelColor
        for label in [title, folder] {
          label.lineBreakMode = .byTruncatingTail
          label.translatesAutoresizingMaskIntoConstraints = false
          cell.addSubview(label)
          label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8).isActive = true
          label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8).isActive = true
        }
        NSLayoutConstraint.activate([
          title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 6),
          folder.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
        ])
        cell.textField = title
      }
      let url = URL(fileURLWithPath: reminder.path)
      cell.textField?.stringValue = url.deletingPathExtension().lastPathComponent
      let folder = (reminder.path as NSString).deletingLastPathComponent
      (cell.viewWithTag(1) as? NSTextField)?.stringValue = folder.isEmpty ? "Без папки" : folder
      cell.toolTip = reminder.path
      return cell
    }
    let label = tableView.makeView(withIdentifier: id, owner: self) as? NSTextField
      ?? NSTextField(labelWithString: "")
    label.identifier = id
    label.font = .systemFont(ofSize: 12)
    label.lineBreakMode = .byTruncatingTail
    label.stringValue = id.rawValue == "date" ? formatter.string(from: reminder.date) : reminder.repetition.title
    label.toolTip = label.stringValue
    return label
  }

  func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }

  private func updateButtons() {
    for button in [openButton, editButton, cancelButton] { button.isEnabled = selectedReminder != nil }
  }

  private func item(for path: String) -> NSMenuItem {
    let item = NSMenuItem()
    item.representedObject = ["path": path]
    return item
  }

  @objc func openSelected() {
    guard let reminder = selectedReminder else { return }
    let button = NSButton()
    button.identifier = NSUserInterfaceItemIdentifier(reminder.path)
    app.openListedReminder(button)
    if app.currentURL?.path == app.root.appendingPathComponent(reminder.path).path { app.showWindow() }
  }

  @objc func editSelected() {
    guard let reminder = selectedReminder else { return }
    app.contextReminder(item(for: reminder.path))
  }

  @objc func cancelSelected() {
    guard let reminder = selectedReminder else { return }
    app.contextCancelReminder(item(for: reminder.path))
    refresh(app.activeReminders())
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
    guard displayed.indices.contains(row) else { return }
    table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    for (title, action) in [
      ("Открыть заметку", #selector(openSelected)),
      ("Изменить время и повтор…", #selector(editSelected)),
      ("Отменить напоминание", #selector(cancelSelected)),
    ] {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
  }
}

private final class RemindersWindow: NSWindow {
  weak var searchField: NSSearchField?

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.modifierFlags.intersection([.command, .shift, .option, .control]) == [.command],
      NotesApp.shortcutCharacter(keyCode: UInt32(event.keyCode)) == "f"
    {
      makeFirstResponder(searchField)
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}
