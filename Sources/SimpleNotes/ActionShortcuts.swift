import Carbon
import Cocoa

struct NoteAction {
  let id: String
  let title: String
  let group: String
  var key = ""
  var modifiers: NSEvent.ModifierFlags = [.command]
  var formatTag: Int?
}

extension NotesApp {
  var noteActions: [NoteAction] {
    [
      NoteAction(id: "new", title: "Новая заметка", group: "Заметки", key: "n"),
      NoteAction(id: "normalWindow", title: "Открыть обычное окно", group: "Заметки", key: "\r", modifiers: [.command, .shift]),
      NoteAction(id: "save", title: "Сохранить заметку", group: "Заметки", key: "\r"),
      NoteAction(
        id: "topic", title: "Новая тема", group: "Заметки", key: "n", modifiers: [.command, .shift]),
      NoteAction(id: "search", title: "Поиск по заметкам", group: "Навигация", key: "f"),
      NoteAction(
        id: "sidebar", title: "Показать / скрыть меню", group: "Навигация", key: "m",
        modifiers: [.command, .shift]),
      NoteAction(
        id: "preview", title: "Предпросмотр Markdown", group: "Навигация", key: "p",
        modifiers: [.command, .shift]),
      NoteAction(id: "editor", title: "Вернуться в редактор", group: "Навигация", key: "e"),
      NoteAction(id: "recent", title: "Недавние заметки", group: "Навигация"),
      NoteAction(id: "refresh", title: "Обновить список заметок", group: "Навигация", key: "r"),
      NoteAction(id: "folder", title: "Открыть папку темы в Finder", group: "Навигация"),
      NoteAction(id: "library", title: "Открыть всю библиотеку в Finder", group: "Навигация"),
      NoteAction(id: "zoomIn", title: "Увеличить масштаб", group: "Масштаб", key: "="),
      NoteAction(id: "zoomOut", title: "Уменьшить масштаб", group: "Масштаб", key: "-"),
      NoteAction(id: "zoomReset", title: "Масштаб 100%", group: "Масштаб", key: "0"),
      NoteAction(id: "bold", title: "Жирный", group: "Форматирование", key: "b", formatTag: 1),
      NoteAction(id: "italic", title: "Курсив", group: "Форматирование", key: "i", formatTag: 2),
      NoteAction(
        id: "heading1", title: "Крупный заголовок", group: "Форматирование", formatTag: 101),
      NoteAction(
        id: "heading2", title: "Средний заголовок", group: "Форматирование", formatTag: 102),
      NoteAction(id: "heading3", title: "Малый заголовок", group: "Форматирование", formatTag: 103),
      NoteAction(
        id: "bullets", title: "Маркированный список", group: "Форматирование", formatTag: 3),
      NoteAction(
        id: "numbers", title: "Нумерованный список", group: "Форматирование", formatTag: 4),
      NoteAction(id: "tasks", title: "Список задач", group: "Форматирование", formatTag: 5),
      NoteAction(id: "quote", title: "Цитата", group: "Форматирование", formatTag: 6),
      NoteAction(id: "code", title: "Код", group: "Форматирование", formatTag: 7),
      NoteAction(
        id: "link", title: "Добавить ссылку", group: "Форматирование", key: "k", formatTag: 8),
      NoteAction(id: "actions", title: "Меню действий записи / папки", group: "Работа с файлами"),
      NoteAction(id: "rename", title: "Переименовать запись / папку", group: "Работа с файлами"),
      NoteAction(id: "duplicate", title: "Создать копию", group: "Работа с файлами"),
      NoteAction(id: "trash", title: "Переместить в Корзину…", group: "Работа с файлами"),
      NoteAction(id: "reminder", title: "Напомнить о заметке…", group: "Напоминания"),
      NoteAction(id: "cancelReminder", title: "Отменить напоминание", group: "Напоминания"),
      NoteAction(
        id: "notifications", title: "Включить / выключить уведомления", group: "Напоминания"),
      NoteAction(id: "dates", title: "Показать / скрыть дату", group: "Оформление"),
      NoteAction(id: "autoHide", title: "Автоскрытие бокового меню", group: "Оформление"),
      NoteAction(id: "theme", title: "Следующая тема приложения", group: "Оформление"),
    ]
  }

  func actionBinding(_ action: NoteAction) -> (String, NSEvent.ModifierFlags) {
    let saved = defaults.dictionary(forKey: "actionShortcuts") as? [String: [String: Any]] ?? [:]
    guard let binding = saved[action.id], let key = binding["key"] as? String,
      let modifiers = binding["modifiers"] as? UInt
    else { return (action.key, action.modifiers) }
    return (key, NSEvent.ModifierFlags(rawValue: modifiers))
  }

  func installActionShortcuts(in menu: NSMenu) {
    let parent = NSMenuItem()
    let actions = NSMenu(title: "Заметки")
    var group = ""
    for action in noteActions {
      if !group.isEmpty && action.group != group { actions.addItem(.separator()) }
      group = action.group
      let item = NSMenuItem(
        title: action.title, action: #selector(performNoteAction(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = action.id
      shortcutMenuItems[action.id] = item
      actions.addItem(item)
    }
    parent.submenu = actions
    menu.insertItem(parent, at: 1)
    updateActionShortcuts()
  }

  func installActionKeyMonitor() {
    if let monitor = actionKeyMonitor { NSEvent.removeMonitor(monitor) }
    actionKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self = self, self.window.isKeyWindow, NSApp.modalWindow == nil,
        event.window == nil || event.window === self.window
      else { return event }
      let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
      guard !flags.intersection([.command, .option, .control]).isEmpty else { return event }
      let character = Self.shortcutCharacter(keyCode: UInt32(event.keyCode))
      if self.mode.selectedSegment == 1, character == "z",
        flags == [.command] || flags == [.command, .shift]
      {
        if flags.contains(.shift) {
          self.editor.redo(nil)
        } else {
          self.editor.undo(nil)
        }
        self.renderMarkdown()
        self.status.stringValue = self.dirty ? "Есть несохранённые изменения" : "Готово"
        return nil
      }
      let saved =
        self.defaults.dictionary(forKey: "actionShortcuts") as? [String: [String: Any]] ?? [:]
      for action in self.noteActions {
        let (key, modifiers) = self.actionBinding(action)
        guard !key.isEmpty else { continue }
        let code = saved[action.id]?["keyCode"] as? UInt32
        let matchesKey = code.map { $0 == UInt32(event.keyCode) } ?? (key == character)
        let zoomPlus =
          action.id == "zoomIn" && key == "=" && modifiers == [.command]
          && flags == [.command, .shift]
        if matchesKey && (modifiers == flags || zoomPlus),
          let item = self.shortcutMenuItems[action.id]
        {
          self.performNoteAction(item)
          return nil
        }
      }
      return event
    }
  }

  func updateActionShortcuts() {
    if quickMore.numberOfItems > 1, let action = noteActions.first(where: { $0.id == "normalWindow" }) {
      quickMore.item(at: 1)?.title = "Открыть обычное окно" + (actionBinding(action).0.isEmpty ? "" : "  " + bindingLabel(action))
      expandButton.toolTip = "Продолжить эту же запись в полном окне"
    }
    if let action = noteActions.first(where: { $0.id == "save" }) {
      let label = actionBinding(action).0.isEmpty ? "" : "  " + bindingLabel(action)
      saveNoteButton?.title = "Сохранить заметку" + label
    }
    if let action = noteActions.first(where: { $0.id == "new" }) {
      newNoteButton.toolTip =
        "Новая заметка" + (actionBinding(action).0.isEmpty ? "" : " · " + bindingLabel(action))
    }
    for action in noteActions {
      let binding = actionBinding(action)
      shortcutMenuItems[action.id]?.keyEquivalent = binding.0
      shortcutMenuItems[action.id]?.keyEquivalentModifierMask = binding.1
    }
  }

  func bindingLabel(_ action: NoteAction) -> String {
    let (key, modifiers) = actionBinding(action)
    guard !key.isEmpty else { return "Не назначено" }
    var label = ""
    if modifiers.contains(.control) { label += "⌃" }
    if modifiers.contains(.option) { label += "⌥" }
    if modifiers.contains(.shift) { label += "⇧" }
    if modifiers.contains(.command) { label += "⌘" }
    let names = [
      "\r": "↩", "\t": "⇥", " ": "Пробел", "\u{1b}": "⎋", "\u{7f}": "⌫", "\u{8}": "⌫", "=": "+",
    ]
    return label + (names[key] ?? key.uppercased())
  }

  func configureActionShortcut(_ id: String) {
    guard let action = noteActions.first(where: { $0.id == id }) else { return }
    suspendQuickNoteHotkey()
    defer { restoreQuickNoteHotkey() }
    let alert = NSAlert()
    alert.messageText = action.title
    alert.informativeText =
      "Нажми сочетание с ⌘, ⌥ или ⌃. Оно действует внутри SimpleNotes. Сейчас — \(bindingLabel(action))."
    let recorder = ShortcutRecorder(frame: NSRect(x: 0, y: 0, width: 420, height: 54))
    alert.accessoryView = recorder
    alert.addButton(withTitle: "Назначить")
    alert.addButton(withTitle: "Отмена")
    alert.addButton(withTitle: "По умолчанию")
    alert.addButton(withTitle: "Убрать сочетание")
    alert.window.initialFirstResponder = recorder
    let result = alert.runModal()
    var saved = defaults.dictionary(forKey: "actionShortcuts") as? [String: [String: Any]] ?? [:]
    if result == .alertThirdButtonReturn {
      if !action.key.isEmpty,
        let conflict = shortcutConflict(key: action.key, modifiers: action.modifiers, excluding: id)
      {
        showError("Стандартное сочетание сейчас используется для «\(conflict)».")
        return
      }
      saved.removeValue(forKey: id)
    } else if result.rawValue == NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + 3 {
      saved[id] = ["key": "", "modifiers": UInt(0)]
    } else {
      guard result == .alertFirstButtonReturn, let key = recorder.serviceCharacter, key.count == 1
      else { return }
      let modifiers = eventModifiers(recorder.modifiers)
      if let conflict = shortcutConflict(key: key, modifiers: modifiers, excluding: id) {
        showError("Это сочетание используется для «\(conflict)».")
        return
      }
      saved[id] = ["key": key, "modifiers": modifiers.rawValue, "keyCode": recorder.keyCode ?? 0]
    }
    defaults.set(saved, forKey: "actionShortcuts")
    updateActionShortcuts()
  }

  func eventModifiers(_ carbon: UInt32) -> NSEvent.ModifierFlags {
    var flags: NSEvent.ModifierFlags = []
    if carbon & UInt32(cmdKey) != 0 { flags.insert(.command) }
    if carbon & UInt32(optionKey) != 0 { flags.insert(.option) }
    if carbon & UInt32(controlKey) != 0 { flags.insert(.control) }
    if carbon & UInt32(shiftKey) != 0 { flags.insert(.shift) }
    return flags
  }

  func shortcutConflict(key: String, modifiers: NSEvent.ModifierFlags, excluding id: String)
    -> String?
  {
    for action in noteActions where action.id != id {
      let binding = actionBinding(action)
      let zoomAlias =
        action.id == "zoomIn" && binding.0 == "=" && binding.1 == [.command]
        && key == "=" && modifiers == [.command, .shift]
      if (binding.0 == key && binding.1 == modifiers) || zoomAlias { return action.title }
    }
    func reserved(_ menu: NSMenu?) -> String? {
      for item in menu?.items ?? [] {
        if item.action != #selector(performNoteAction(_:)), item.keyEquivalent == key,
          item.keyEquivalentModifierMask == modifiers
        {
          return item.title
        }
        if let found = reserved(item.submenu) { return found }
      }
      return nil
    }
    if let found = reserved(NSApp.mainMenu) { return found }
    if id != "global", let character = defaults.string(forKey: "quickNoteServiceCharacter"),
      character == key,
      eventModifiers(UInt32(defaults.integer(forKey: "quickNoteModifiers"))) == modifiers
    {
      return "Быстрая заметка из любого приложения"
    }
    return nil
  }

  @objc func performNoteAction(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String,
      let action = noteActions.first(where: { $0.id == id })
    else { return }
    if let tag = action.formatTag {
      let control = NSButton()
      control.tag = tag
      formatText(control)
      return
    }
    if quickMode && !["new", "save", "normalWindow", "zoomIn", "zoomOut", "zoomReset"].contains(id) {
      expandQuickNote()
    }
    switch id {
    case "normalWindow": expandQuickNote()
    case "new":
      if quickMode { openQuickNote() } else { newNote() }
    case "save": saveNote()
    case "topic": addTopic()
    case "search":
      suppressHoverUntil = Date().addingTimeInterval(2)
      manualRevealUntil = Date().addingTimeInterval(2)
      setMenuVisible(true, animated: true)
      window.makeFirstResponder(searchField)
    case "sidebar": toggleMenu()
    case "preview":
      mode.selectedSegment = 1
      changeMode()
    case "editor":
      mode.selectedSegment = 0
      changeMode()
      window.makeFirstResponder(editor)
    case "recent": recentButton.performClick(nil)
    case "refresh":
      refreshTopics(select: selectedTopicPath)
      refreshTree()
    case "folder": openFolder()
    case "library": openAllNotes()
    case "zoomIn": zoomIn()
    case "zoomOut": zoomOut()
    case "zoomReset": resetZoom()
    case "dates": toggleDate()
    case "autoHide": toggleAutoHide()
    case "notifications": toggleNotifications()
    case "theme":
      let values = ["system", "light", "dark"]
      let index = values.firstIndex(of: defaults.string(forKey: "appearance") ?? "system") ?? 0
      defaults.set(values[(index + 1) % values.count], forKey: "appearance")
      applyTheme()
    default: performFileShortcut(id)
    }
    settingsController?.refresh()
  }

  func performFileShortcut(_ id: String) {
    let selected =
      outline.selectedRow >= 0 ? outline.item(atRow: outline.selectedRow) as? NoteNode : nil
    let url = window.firstResponder === outline ? selected?.url : currentURL
    guard let url = url else {
      showError("Выбери запись или папку в меню. Для текущей заметки сначала сохрани текст.")
      return
    }
    let item = NSMenuItem()
    item.representedObject = ["path": relativePath(url)]
    switch id {
    case "rename": contextRename(item)
    case "duplicate": contextDuplicate(item)
    case "trash": contextTrash(item)
    case "reminder", "cancelReminder":
      guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else {
        return
      }
      if id == "reminder" { contextReminder(item) } else { contextCancelReminder(item) }
    case "actions":
      suppressHoverUntil = Date().addingTimeInterval(2)
      manualRevealUntil = Date().addingTimeInterval(2)
      setMenuVisible(true)
      window.contentView?.layoutSubtreeIfNeeded()
      let menu = NSMenu()
      menu.delegate = self
      keyboardContextURL = url
      defer { keyboardContextURL = nil }
      menuNeedsUpdate(menu)
      menu.popUp(
        positioning: nil, at: NSPoint(x: 0, y: settingsButton.bounds.height + 4), in: settingsButton
      )
    default: break
    }
  }
}
