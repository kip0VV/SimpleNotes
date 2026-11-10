import Cocoa

final class NotesSettingsController: NSWindowController {
  unowned let app: NotesApp
  let theme = NSPopUpButton()
  let dates = NSButton(checkboxWithTitle: "Показывать дату заметки", target: nil, action: nil)
  let hide = NSButton(
    checkboxWithTitle: "Скрывать меню при уходе курсора", target: nil, action: nil)
  let reverse = NSButton(checkboxWithTitle: "Обратное направление свайпа", target: nil, action: nil)
  let notifications = NSButton(
    checkboxWithTitle: "Уведомления о заметках", target: nil, action: nil)
  let shortcut = NSTextField(labelWithString: "")
  var actionLabels: [String: NSTextField] = [:]
  let folder = NSTextField(wrappingLabelWithString: "")

  init(app: NotesApp) {
    self.app = app
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 700, height: 650),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.minSize = NSSize(width: 650, height: 560)
    window.title = "Настройки SimpleNotes"
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.center()
    let tabs = NSTabView()
    tabs.translatesAutoresizingMaskIntoConstraints = false
    let contentView = NSView()
    window.contentView = contentView
    contentView.addSubview(tabs)
    NSLayoutConstraint.activate([
      tabs.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      tabs.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
      tabs.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
      tabs.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
    ])
    func tab(_ title: String) -> NSStackView {
      let item = NSTabViewItem(identifier: title)
      item.label = title
      let scroll = NSScrollView()
      scroll.hasVerticalScroller = true
      scroll.drawsBackground = false
      let document = SettingsDocumentView()
      document.translatesAutoresizingMaskIntoConstraints = false
      scroll.documentView = document
      let stack = NSStackView()
      stack.orientation = .vertical
      stack.alignment = .leading
      stack.spacing = 12
      stack.translatesAutoresizingMaskIntoConstraints = false
      document.addSubview(stack)
      NSLayoutConstraint.activate([
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
        stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -20),
        stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
        stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
      ])
      item.view = scroll
      tabs.addTabViewItem(item)
      return stack
    }
    let stack = tab("Основные")
    func heading(_ title: String) {
      let label = NSTextField(labelWithString: title)
      label.font = .boldSystemFont(ofSize: 14)
      stack.addArrangedSubview(label)
    }
    func row(_ views: NSView...) {
      let row = NSStackView(views: views)
      row.spacing = 12
      row.alignment = .centerY
      stack.addArrangedSubview(row)
    }
    func button(_ title: String, _ action: Selector) -> NSButton {
      NSButton(title: title, target: self, action: action)
    }
    func divider() {
      let line = NSBox()
      line.boxType = .separator
      stack.addArrangedSubview(line)
      line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    heading("Оформление")
    theme.addItems(withTitles: ["Системная", "Светлая", "Тёмная"])
    theme.target = self
    theme.action = #selector(changeTheme)
    row(NSTextField(labelWithString: "Тема приложения"), theme)
    stack.addArrangedSubview(dates)
    divider()
    heading("Боковое меню")
    stack.addArrangedSubview(hide)
    stack.addArrangedSubview(reverse)
    let hint = NSTextField(labelWithString: "Два пальца влево — открыть, вправо — скрыть.")
    hint.textColor = .secondaryLabelColor
    stack.addArrangedSubview(hint)
    divider()
    heading("Напоминания")
    stack.addArrangedSubview(notifications)
    divider()
    heading("Папка заметок")
    folder.isSelectable = true
    folder.font = .systemFont(ofSize: 12)
    folder.textColor = .secondaryLabelColor
    stack.addArrangedSubview(folder)
    folder.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    row(
      button("Выбрать папку…", #selector(changeFolder)),
      button("Открыть в Finder", #selector(openFolder)),
      button("Папка выбранной темы", #selector(openTopic)))
    for control in [dates, hide, reverse, notifications] {
      control.target = self
      control.action = #selector(toggle(_:))
    }
    let keyboard = tab("Горячие клавиши")
    let description = NSTextField(
      wrappingLabelWithString:
        "Быстрая заметка запускает приложение из других окон. Остальные сочетания действуют внутри SimpleNotes. Нажми «Изменить», чтобы назначить своё сочетание или вернуть стандартное."
    )
    description.textColor = .secondaryLabelColor
    keyboard.addArrangedSubview(description)
    description.widthAnchor.constraint(equalTo: keyboard.widthAnchor).isActive = true
    let globalRow = NSStackView(views: [
      NSTextField(labelWithString: "Быстрая заметка из любого приложения"),
      shortcut, button("Изменить…", #selector(changeShortcut)),
    ])
    shortcut.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
    shortcut.textColor = .secondaryLabelColor
    globalRow.spacing = 12
    keyboard.addArrangedSubview(globalRow)
    var group = ""
    for action in app.noteActions {
      if action.group != group {
        let heading = NSTextField(labelWithString: action.group)
        heading.font = .boldSystemFont(ofSize: 14)
        keyboard.addArrangedSubview(heading)
        keyboard.setCustomSpacing(8, after: heading)
        group = action.group
      }
      let title = NSTextField(labelWithString: action.title)
      title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      let label = NSTextField(labelWithString: app.bindingLabel(action))
      label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
      label.textColor = .secondaryLabelColor
      label.alignment = .right
      label.widthAnchor.constraint(equalToConstant: 110).isActive = true
      actionLabels[action.id] = label
      let edit = button("Изменить…", #selector(changeActionShortcut(_:)))
      edit.identifier = NSUserInterfaceItemIdentifier(action.id)
      let row = NSStackView(views: [title, NSView(), label, edit])
      row.spacing = 12
      keyboard.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: keyboard.widthAnchor).isActive = true
    }
    let reset = button("Вернуть стандартные сочетания приложения", #selector(resetActionShortcuts))
    keyboard.addArrangedSubview(reset)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func refresh() {
    theme.selectItem(
      at: ["system", "light", "dark"].firstIndex(
        of: app.defaults.string(forKey: "appearance") ?? "system") ?? 0)
    dates.state = app.showDates ? .on : .off
    hide.state = app.autoHide.state
    reverse.state = app.defaults.bool(forKey: "reverseSidebarSwipe") ? .on : .off
    notifications.state = app.notificationsEnabled ? .on : .off
    shortcut.stringValue =
      (app.defaults.string(forKey: "quickNoteLabel") ?? "Не назначено")
    folder.stringValue = app.root.path
    for action in app.noteActions {
      actionLabels[action.id]?.stringValue = app.bindingLabel(action)
    }
  }

  @objc func changeTheme() {
    let item = NSMenuItem()
    item.representedObject = ["system", "light", "dark"][theme.indexOfSelectedItem]
    app.changeTheme(item)
  }
  @objc func toggle(_ sender: NSButton) {
    switch sender {
    case dates: app.toggleDate()
    case hide: app.toggleAutoHide()
    case reverse: app.defaults.set(sender.state == .on, forKey: "reverseSidebarSwipe")
    default:
      if sender.state == .on {
        app.enableNotifications { [weak self] granted in
          if granted { self?.app.rescheduleReminders() }
          self?.refresh()
        }
      } else {
        app.toggleNotifications()
      }
    }
    refresh()
  }
  @objc func changeShortcut() {
    app.configureQuickNoteShortcut()
    refresh()
  }
  @objc func changeFolder() {
    app.chooseStorage()
    refresh()
  }
  @objc func changeActionShortcut(_ sender: NSButton) {
    guard let id = sender.identifier?.rawValue else { return }
    app.configureActionShortcut(id)
    refresh()
  }
  @objc func resetActionShortcuts() {
    if let key = app.defaults.string(forKey: "quickNoteServiceCharacter"),
      let conflict = app.noteActions.first(where: {
        $0.key == key
          && $0.modifiers
            == app.eventModifiers(UInt32(app.defaults.integer(forKey: "quickNoteModifiers")))
      })
    {
      app.showError(
        "Стандартное сочетание «\(conflict.title)» занято быстрой заметкой. Сначала измени её сочетание."
      )
      return
    }
    app.defaults.removeObject(forKey: "actionShortcuts")
    app.updateActionShortcuts()
    refresh()
  }
  @objc func openFolder() { app.openAllNotes() }
  @objc func openTopic() { app.openFolder() }
}

private final class SettingsDocumentView: NSView {
  override var isFlipped: Bool { true }
}
