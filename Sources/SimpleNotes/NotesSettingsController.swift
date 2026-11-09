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
  let folder = NSTextField(wrappingLabelWithString: "")

  init(app: NotesApp) {
    self.app = app
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 570),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Настройки SimpleNotes"
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.center()
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    window.contentView!.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 26),
      stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -26),
      stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
    ])
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
    heading("Клавиши и напоминания")
    row(shortcut, button("Изменить…", #selector(changeShortcut)))
    stack.addArrangedSubview(notifications)
    let keys = NSTextField(
      labelWithString: "В приложении   ⌘N — новая заметка   ·   ⌘Enter — сохранить")
    keys.font = .systemFont(ofSize: 12)
    keys.textColor = .secondaryLabelColor
    stack.addArrangedSubview(keys)
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
      "Быстрая заметка — " + (app.defaults.string(forKey: "quickNoteLabel") ?? "не назначено")
    folder.stringValue = app.root.path
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
  @objc func openFolder() { app.openAllNotes() }
  @objc func openTopic() { app.openFolder() }
}
