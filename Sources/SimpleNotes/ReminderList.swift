import Cocoa

final class ReminderListStack: NSStackView {
  override var isFlipped: Bool { true }
}

extension NotesApp {
  func activeReminders(now: Date = Date()) -> [ActiveReminder] {
    guard notificationsEnabled else { return [] }
    return reminderRecords.compactMap { path, record in
      guard let time = record["time"] as? Double, time.isFinite else { return nil }
      let url = root.appendingPathComponent(path).standardizedFileURL
      guard url.path.hasPrefix(root.path + "/"),
        FileManager.default.fileExists(atPath: url.path)
      else { return nil }
      let repeating = ReminderRepeat(rawValue: record["repeat"] as? String ?? "") ?? .none
      guard let next = repeating.nextDate(
        reference: Date(timeIntervalSince1970: time), after: now)
      else { return nil }
      return ActiveReminder(path: path, date: next, repetition: repeating)
    }.sorted {
      $0.date == $1.date ? $0.path.localizedStandardCompare($1.path) == .orderedAscending
        : $0.date < $1.date
    }
  }

  func makeReminderList() -> NSView {
    let container = NSView()
    reminderPanel = container
    let panel = NSStackView()
    panel.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(panel)
    reminderPanelTop = panel.topAnchor.constraint(equalTo: container.topAnchor)
    reminderPanelCollapsedHeight = container.heightAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
      panel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      panel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      panel.bottomAnchor.constraint(equalTo: container.bottomAnchor), reminderPanelTop!,
    ])
    panel.orientation = .vertical
    panel.alignment = .leading
    panel.spacing = 6
    reminderResizeHandle.vertical = false
    reminderResizeHandle.toolTip = "Потяни вверх — больше напоминаний. Вниз до минимума — скрыть блок. Вернуть: ⋯ → Скрыть меню напоминаний."
    reminderResizeHandle.setAccessibilityLabel("Высота блока напоминаний")
    var initialHeight: CGFloat = 0
    reminderResizeHandle.beginResize = { [weak self] in initialHeight = self?.reminderListHeight?.constant ?? 144 }
    reminderResizeHandle.resize = { [weak self] delta in self?.resizeReminderViewport(to: initialHeight + delta) }
    reminderResizeHandle.heightAnchor.constraint(equalToConstant: 10).isActive = true
    reminderHeading.font = .systemFont(ofSize: 12, weight: .semibold)
    reminderList.orientation = .vertical
    reminderList.alignment = .leading
    reminderList.spacing = 4
    reminderList.translatesAutoresizingMaskIntoConstraints = false
    reminderScroll.drawsBackground = false
    reminderScroll.hasVerticalScroller = true
    reminderScroll.documentView = reminderList
    allRemindersButton.target = self
    allRemindersButton.action = #selector(showAllReminders)
    allRemindersButton.bezelStyle = .inline
    allRemindersButton.setAccessibilityLabel("Открыть все напоминания")
    allRemindersButton.toolTip = "Поиск, фильтры и управление всеми напоминаниями"
    let heading = NSStackView(views: [reminderHeading, NSView(), allRemindersButton])
    heading.distribution = .fill
    heading.spacing = 6
    for view in [reminderResizeHandle, heading, reminderScroll] {
      panel.addArrangedSubview(view)
      view.widthAnchor.constraint(equalTo: panel.widthAnchor).isActive = true
    }
    NSLayoutConstraint.activate([
      reminderList.widthAnchor.constraint(equalTo: reminderScroll.contentView.widthAnchor),
      reminderList.topAnchor.constraint(equalTo: reminderScroll.contentView.topAnchor),
    ])
    reminderListHeight = reminderScroll.heightAnchor.constraint(equalToConstant: 22)
    reminderListHeight?.isActive = true
    refreshReminderList()
    reminderListTimer?.invalidate()
    reminderListTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      self?.refreshReminderList()
    }
    return container
  }

  func refreshReminderList() {
    let reminders = activeReminders()
    if remindersController?.window?.isVisible == true { remindersController?.refresh(reminders) }
    sidebarReminders = reminders
    renderSidebarReminders()
  }

  var reminderSidebarHidden: Bool { defaults.bool(forKey: "hideReminderSidebar") }

  var maximumReminderViewportHeight: CGFloat {
    max(48, (window?.contentView?.bounds.height ?? 680) - 380)
  }

  func renderSidebarReminders() {
    guard reminderListHeight != nil else { return }
    let reminders = sidebarReminders
    let hidden = reminderSidebarHidden
    // The content is unconstrained at the top while collapsed, so it can retain
    // its own layout without limiting the notes list above the zero-height panel.
    if hidden {
      reminderPanelTop?.isActive = false
      reminderPanelCollapsedHeight?.isActive = true
    } else {
      reminderPanelCollapsedHeight?.isActive = false
      reminderPanelTop?.isActive = true
    }
    reminderPanel?.isHidden = hidden
    let naturalHeight: CGFloat = reminders.isEmpty ? 22 : CGFloat(min(reminders.count, 3) * 48)
    let storedHeight = defaults.object(forKey: "reminderViewportHeight") as? Double
    let preferredHeight = storedHeight.flatMap { $0.isFinite ? max(48, CGFloat($0)) : nil } ?? naturalHeight
    let viewportHeight = hidden ? 0 : min(preferredHeight, maximumReminderViewportHeight)
    reminderListHeight?.constant = viewportHeight
    let capacity = hidden ? 0 : max(1, Int(ceil(viewportHeight / 48)))
    reminderList.arrangedSubviews.forEach {
      reminderList.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    reminderHeading.stringValue = "Напоминания · \(reminders.count)"
    let formatter = DateFormatter()
    formatter.dateFormat = "dd.MM.yyyy · HH:mm"
    for reminder in reminders.prefix(capacity) {
      let url = root.appendingPathComponent(reminder.path)
      let name = url.deletingPathExtension().lastPathComponent
      let button = NSButton(title: "", target: self, action: #selector(openListedReminder(_:)))
      button.isBordered = false
      button.alignment = .left
      button.cell?.wraps = true
      button.lineBreakMode = .byTruncatingTail
      button.identifier = NSUserInterfaceItemIdentifier(reminder.path)
      let title = NSMutableAttributedString(string: name + "\n", attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor,
      ])
      let details = formatter.string(from: reminder.date)
        + (reminder.repetition == .none ? "" : " · " + reminder.repetition.title)
      title.append(NSAttributedString(string: details, attributes: [
        .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor,
      ]))
      button.attributedTitle = title
      button.toolTip = reminder.path + "\n" + details
      button.setAccessibilityLabel(name + ", " + details)
      button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      let actions = NSPopUpButton(frame: .zero, pullsDown: true)
      actions.isBordered = false
      (actions.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
      actions.addItem(withTitle: "⋯")
      actions.setAccessibilityLabel("Изменить напоминание «\(name)»")
      for (title, action) in [
        ("Изменить время и повтор…", #selector(contextReminder(_:))),
        ("Отменить напоминание", #selector(contextCancelReminder(_:))),
      ] {
        actions.addItem(withTitle: title)
        actions.lastItem?.target = self
        actions.lastItem?.action = action
        actions.lastItem?.representedObject = ["path": reminder.path]
      }
      let row = NSStackView(views: [button, actions])
      row.distribution = .fill
      row.spacing = 2
      row.alignment = .centerY
      reminderList.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: reminderList.widthAnchor).isActive = true
      row.heightAnchor.constraint(equalToConstant: 44).isActive = true
      actions.widthAnchor.constraint(equalToConstant: 30).isActive = true
    }
    if reminders.isEmpty {
      let empty = NSTextField(labelWithString:
        notificationsEnabled ? "Нет активных напоминаний" : "Уведомления выключены")
      empty.font = .systemFont(ofSize: 11)
      empty.textColor = .secondaryLabelColor
      reminderList.addArrangedSubview(empty)
    }
  }

  func resizeReminderViewport(to height: CGFloat) {
    guard height.isFinite else { return }
    if height < 32 {
      defaults.set(true, forKey: "hideReminderSidebar")
    } else {
      defaults.set(false, forKey: "hideReminderSidebar")
      defaults.set(Double(min(max(48, height), maximumReminderViewportHeight)), forKey: "reminderViewportHeight")
    }
    renderSidebarReminders()
    settingsController?.refresh()
    window?.contentView?.layoutSubtreeIfNeeded()
  }

  @objc func toggleReminderSidebar() {
    defaults.set(!reminderSidebarHidden, forKey: "hideReminderSidebar")
    renderSidebarReminders()
    settingsController?.refresh()
    window?.contentView?.layoutSubtreeIfNeeded()
  }

  @objc func showAllReminders() {
    if remindersController == nil { remindersController = RemindersWindowController(app: self) }
    remindersController?.refresh(activeReminders())
    remindersController?.showWindow(nil)
    remindersController?.window?.makeKeyAndOrderFront(nil)
  }

  @objc func openListedReminder(_ sender: NSButton) {
    guard let path = sender.identifier?.rawValue else { return }
    let item = NSMenuItem()
    item.representedObject = ["path": path]
    guard let url = contextURL(item) else { return }
    searchField.stringValue = ""
    applySearch()
    openNote(url)
  }
}
