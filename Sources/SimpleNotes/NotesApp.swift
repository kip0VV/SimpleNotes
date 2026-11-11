import Carbon
import Cocoa
import QuartzCore
import UserNotifications
import WebKit

final class NotesApp: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextViewDelegate,
  NSTextFieldDelegate, NSSearchFieldDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate,
  NSMenuDelegate, WKNavigationDelegate
{
  var startupComplete = false
  var pendingQuickNote = false
  var pendingRegularWindow = false
  let quickTopics = NSPopUpButton()
  let quickMore = NSPopUpButton(frame: .zero, pullsDown: true)
  let quickStatus = NSTextField(labelWithString: "Сохраняется автоматически")
  var quickChrome: [NSView] = []
  var quickSaveTimer: Timer?
  var quickAutomaticTitle = false
  var quickTopicChanged = false
  var quickMode = false
  var regularFrame = NSRect.zero
  var regularConstraints: [NSLayoutConstraint] = []
  var quickConstraints: [NSLayoutConstraint] = []
  var regularHiddenViews: [NSView] = []
  let expandButton = NSButton(title: "Основное окно", target: nil, action: nil)
  var root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("SimpleNotes", isDirectory: true)
  let defaults = UserDefaults.standard
  var quickHotKey: EventHotKeyRef?
  var quickHotKeyHandler: EventHandlerRef?
  lazy var noteNotifications = UNUserNotificationCenter.current()
  var window: NSWindow!
  var sidebarView: NSView!
  var sidebarTrailing: NSLayoutConstraint!
  var hoverTimer: Timer?
  var pendingVisibility: Bool?
  var manualRevealUntil = Date.distantPast
  var menuTracking = false
  var animationGeneration = 0
  var scaledConstraints: [(NSLayoutConstraint, CGFloat)] = []
  var headerLabels: [NSControl] = []
  var headingLabel: NSTextField!
  var rowHeight: NSLayoutConstraint!
  var topicRowWidth: NSLayoutConstraint!
  var topicControls: [NSControl] = []
  let topicHandle = ResizeHandle()
  let recentButton = NSPopUpButton(frame: .zero, pullsDown: true)
  var swipe = HorizontalSwipe()
  var gestureMonitor: Any?
  var actionKeyMonitor: Any?
  var lastGestureEvent: NSEvent?
  var lastGestureResult = false
  var touchOrigin: NSPoint?
  var touchSwipeRecognized = false
  var settingsController: NotesSettingsController?
  let reminderList = ReminderListStack()
  let reminderScroll = NSScrollView()
  let reminderHeading = NSTextField(labelWithString: "Напоминания")
  let allRemindersButton = NSButton(title: "Все…", target: nil, action: nil)
  var remindersController: RemindersWindowController?
  let reminderResizeHandle = ResizeHandle()
  var reminderPanel: NSView?
  var reminderPanelTop: NSLayoutConstraint?
  var reminderPanelCollapsedHeight: NSLayoutConstraint?
  var sidebarReminders: [ActiveReminder] = []
  var reminderListHeight: NSLayoutConstraint?
  var reminderListTimer: Timer?
  let newNoteButton = NSButton(title: "+ Новая заметка", target: nil, action: nil)
  var suppressHoverUntil = Date.distantPast
  let refreshButton = NSButton(title: "Обновить список", target: nil, action: nil)
  var manualRefreshStarted: Date?
  let settingsButton = NSButton(title: "⋯", target: nil, action: nil)
  var sidebarWidth: NSLayoutConstraint!
  var mainTrailing: NSLayoutConstraint!
  var headerHeight: NSLayoutConstraint!
  var titleHeight: NSLayoutConstraint!
  let sideHandle = ResizeHandle()
  let headerHandle = ResizeHandle()
  let autoHide = NSButton(checkboxWithTitle: "Скрывать при уходе курсора", target: nil, action: nil)
  let menuToggle = NSButton(title: "Меню ▸", target: nil, action: nil)
  var menuVisible = true
  var savedSidebarWidth: CGFloat = 280
  let outline = SnapOutline()
  let previewContainer = NSView()
  var preview: WKWebView?
  var previewReady = false
  var lastPreviewPayload: String?
  var previewRevision = ""
  var updatingTask = false
  lazy var markdownScript: String? = Bundle.main.url(
    forResource: "markdown-it.min", withExtension: "js"
  )
  .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
  var indexGeneration = 0
  var indexedRoot: URL?
  let indexQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "SimpleNotes.noteIndex"
    queue.qualityOfService = .userInitiated
    queue.maxConcurrentOperationCount = 1
    return queue
  }()
  var noteBodyCache: [URL: CachedNoteBody] = [:]
  var keyboardContextURL: URL?
  var shortcutMenuItems: [String: NSMenuItem] = [:]
  var saveNoteButton: NSButton?
  let zoomLabel = NSButton(title: "100%", target: nil, action: nil)
  let mode = NSSegmentedControl(
    labels: ["Редактор", "Рендер"], trackingMode: .selectOne, target: nil, action: nil)
  var tree: [NoteNode] = []
  var allNotes: [NoteNode] = []
  let noteDragType = NSPasteboard.PasteboardType("local.personal.quicknotes.tree-item")
  let colorPalette: [(String, String, NSColor)] = [
    ("Красный", "red", .systemRed), ("Оранжевый", "orange", .systemOrange),
    ("Жёлтый", "yellow", .systemYellow), ("Зелёный", "green", .systemGreen),
    ("Голубой", "blue", .systemBlue), ("Фиолетовый", "purple", .systemPurple),
    ("Розовый", "pink", .systemPink),
  ]
  var itemColors: [String: String] {
    defaults.dictionary(forKey: "itemColors") as? [String: String] ?? [:]
  }
  var showDates: Bool { defaults.object(forKey: "showDates") as? Bool ?? true }
  var customOrder: [String: [String]] {
    defaults.dictionary(forKey: "treeOrder") as? [String: [String]] ?? [:]
  }

  let searchField = NSSearchField()
  let searchStatus = NSTextField(labelWithString: "")
  var searchWork: DispatchWorkItem?
  var searchQuery: String {
    searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var currentURL: URL?
  var loadedContent: String?
  var noteDate = ""
  var dirty = false { didSet { window?.isDocumentEdited = dirty } }
  var loadingTree = false
  var editorScroll: NSScrollView!

  let topics = NSPopUpButton()
  let titleField = NSTextField()
  let editor = NotesTextView()
  let status = NSTextField(labelWithString: "Готово")

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    guard configureStorage() else {
      NSApp.terminate(nil)
      return
    }
    buildMenu()
    prepareRemindersAndShortcut()
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1060, height: 680),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.title = "SimpleNotes"
    window.minSize = NSSize(width: 850, height: 500)
    window.delegate = self
    window.isReleasedWhenClosed = false
    let outer = HoverContent()
    window.contentView = outer
    window.acceptsMouseMovedEvents = true
    let view = NSView()
    let sidebar = NSView()
    sidebarView = sidebar
    savedSidebarWidth = CGFloat(defaults.double(forKey: "sidebarWidth"))
    if savedSidebarWidth < 210 { savedSidebarWidth = 280 }
    for part in [view, sidebar] {
      part.translatesAutoresizingMaskIntoConstraints = false
      outer.addSubview(part)
    }
    sidebarTrailing = sidebar.trailingAnchor.constraint(equalTo: outer.trailingAnchor)
    outer.wantsLayer = true
    outer.layer?.masksToBounds = true
    sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: savedSidebarWidth)
    mainTrailing = view.trailingAnchor.constraint(
      equalTo: outer.trailingAnchor, constant: -savedSidebarWidth)
    NSLayoutConstraint.activate([
      view.leadingAnchor.constraint(equalTo: outer.leadingAnchor),
      view.topAnchor.constraint(equalTo: outer.topAnchor),
      view.bottomAnchor.constraint(equalTo: outer.bottomAnchor), mainTrailing,
      sidebarTrailing, sidebar.topAnchor.constraint(equalTo: outer.topAnchor),
      sidebar.bottomAnchor.constraint(equalTo: outer.bottomAnchor), sidebarWidth,
    ])
    outer.moved = { [weak self] point in self?.handleHover(point, in: outer) }
    buildSidebar(sidebar)
    let heading = NSTextField(labelWithString: "SimpleNotes")
    headingLabel = heading
    heading.font = .systemFont(ofSize: 24, weight: .bold)
    heading.lineBreakMode = .byTruncatingTail
    heading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    menuToggle.target = self
    menuToggle.action = #selector(toggleMenu)
    menuToggle.toolTip =
      "Показать или скрыть правое меню. В скрытом режиме наведи курсор на правый край."
    newNoteButton.target = self
    newNoteButton.action = #selector(newNote)
    newNoteButton.bezelStyle = .rounded
    newNoteButton.controlSize = .large
    newNoteButton.toolTip = "Новая заметка · ⌘N"
    topics.target = self
    topics.action = #selector(topicChanged)
    let add = NSButton(title: "+ Тема", target: self, action: #selector(addTopic))
    add.setContentCompressionResistancePriority(.required, for: .horizontal)
    add.setContentHuggingPriority(.required, for: .horizontal)
    add.toolTip = "Добавить тему — новую папку для заметок"
    add.setAccessibilityLabel("Добавить тему")
    topics.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    (topics.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
    topicControls = [topics, add]
    let row = NSStackView(views: [topics, add])
    row.orientation = .horizontal
    row.spacing = 10
    topics.setContentHuggingPriority(.defaultLow, for: .horizontal)
    titleField.placeholderString = "Название заметки"
    titleField.font = .systemFont(ofSize: 20, weight: .medium)
    titleField.delegate = self
    titleField.stringValue = defaults.string(forKey: "draftTitle") ?? ""
    let formatting = makeFormattingBar()
    let scroll = NSScrollView()
    editorScroll = scroll
    mode.selectedSegment = 0
    mode.target = self
    mode.action = #selector(changeMode)
    previewContainer.isHidden = true
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    editor.isRichText = false
    editor.font = .systemFont(ofSize: 16)
    editor.textContainerInset = NSSize(width: 12, height: 12)
    editor.autoresizingMask = [.width]
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    editor.textContainer?.widthTracksTextView = true
    editor.string = defaults.string(forKey: "draftBody") ?? ""
    editor.delegate = self
    scroll.documentView = editor
    status.font = .systemFont(ofSize: 12)
    status.textColor = .secondaryLabelColor
    let save = NSButton(title: "Сохранить заметку  ⌘↩", target: self, action: #selector(saveNote))
    saveNoteButton = save
    save.bezelStyle = .rounded
    let zoomControls = makeZoomControls()
    for item in [
      heading, menuToggle, row, titleField, mode, newNoteButton, scroll, previewContainer, status,
      recentButton, save, headerHandle, topicHandle, formatting, zoomControls,
    ] {
      item.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(item)
    }

    let initialHeader: CGFloat = 220
    headerHeight = headerHandle.topAnchor.constraint(
      equalTo: view.topAnchor, constant: initialHeader)
    titleHeight = titleField.heightAnchor.constraint(equalToConstant: 36)
    rowHeight = row.heightAnchor.constraint(equalToConstant: 26)
    topicRowWidth = row.widthAnchor.constraint(equalToConstant: 300)
    let recentMenu = NSMenu()
    recentMenu.delegate = self
    recentButton.menu = recentMenu
    rebuildRecentMenu()
    NSLayoutConstraint.activate([
      menuToggle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      menuToggle.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
      topicRowWidth,
      topicHandle.leadingAnchor.constraint(equalTo: row.trailingAnchor, constant: 5),
      topicHandle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
      topicHandle.widthAnchor.constraint(equalToConstant: 12),
      topicHandle.heightAnchor.constraint(equalTo: row.heightAnchor),
      rowHeight, headerHeight,
      headerHandle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      headerHandle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      headerHandle.heightAnchor.constraint(equalToConstant: 10),
      heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      heading.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
      row.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
      row.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -44),
      row.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 18),
      titleField.leadingAnchor.constraint(equalTo: row.leadingAnchor),
      titleField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      titleField.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 16), titleHeight,
      scroll.leadingAnchor.constraint(equalTo: row.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      formatting.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
      formatting.trailingAnchor.constraint(lessThanOrEqualTo: scroll.trailingAnchor),
      formatting.topAnchor.constraint(equalTo: headerHandle.bottomAnchor, constant: 4),
      formatting.heightAnchor.constraint(equalToConstant: 28),
      scroll.topAnchor.constraint(equalTo: formatting.bottomAnchor, constant: 6),
      scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -14),
      newNoteButton.trailingAnchor.constraint(equalTo: menuToggle.leadingAnchor, constant: -12),
      newNoteButton.centerYAnchor.constraint(equalTo: menuToggle.centerYAnchor),
      newNoteButton.heightAnchor.constraint(equalToConstant: 28),
      newNoteButton.leadingAnchor.constraint(
        greaterThanOrEqualTo: heading.trailingAnchor, constant: 16),
      mode.leadingAnchor.constraint(equalTo: row.leadingAnchor),
      mode.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 12),
      previewContainer.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
      previewContainer.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
      previewContainer.topAnchor.constraint(equalTo: scroll.topAnchor),
      previewContainer.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
      recentButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      recentButton.centerYAnchor.constraint(equalTo: status.centerYAnchor),
      recentButton.widthAnchor.constraint(equalToConstant: 135),
      status.leadingAnchor.constraint(equalTo: recentButton.trailingAnchor, constant: 10),
      status.bottomAnchor.constraint(equalTo: save.topAnchor, constant: -12),
      status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      zoomControls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      zoomControls.centerYAnchor.constraint(equalTo: save.centerYAnchor),
      zoomControls.trailingAnchor.constraint(lessThanOrEqualTo: save.leadingAnchor, constant: -12),
      save.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      save.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
    ])
    regularConstraints = view.constraints
    configureQuickChrome(in: view)
    quickConstraints = [
      quickTopics.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      quickTopics.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
      quickTopics.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.7),
      quickMore.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      quickMore.centerYAnchor.constraint(equalTo: quickTopics.centerYAnchor),
      expandButton.trailingAnchor.constraint(equalTo: quickMore.leadingAnchor, constant: -8),
      expandButton.centerYAnchor.constraint(equalTo: quickTopics.centerYAnchor),
      quickTopics.trailingAnchor.constraint(lessThanOrEqualTo: expandButton.leadingAnchor, constant: -12),
      scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: quickTopics.bottomAnchor, constant: 8),
      scroll.bottomAnchor.constraint(equalTo: quickStatus.topAnchor, constant: -12),
      quickStatus.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
      quickStatus.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      quickStatus.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
    ]
    regularHiddenViews = [heading, menuToggle, row, titleField, mode, newNoteButton, previewContainer,
      status, recentButton, save, headerHandle, topicHandle, formatting, zoomControls]
    headerLabels = [mode, menuToggle, newNoteButton]
    let headerViews: [NSView] = [heading, menuToggle, row, titleField, mode, newNoteButton]
    scaledConstraints = view.constraints.filter { constraint in
      constraint !== headerHeight && constraint !== titleHeight && constraint !== rowHeight
        && headerViews.contains { $0 === (constraint.firstItem as? NSView) }
    }.map { ($0, $0.constant) }
    applyHeaderScale(CGFloat(defaults.object(forKey: "headerScale") as? Double ?? 1))
    applyNoteZoom()
    applyTheme()
    configureResizing(outer: outer, main: view)
    installGestures()
    installActionKeyMonitor()
    topicHandle.toolTip = "Потяни вправо, чтобы увеличить выбор темы и кнопку"
    var startTopicScale: CGFloat = 1
    topicHandle.beginResize = { [weak self] in
      startTopicScale = CGFloat(self?.defaults.object(forKey: "topicScale") as? Double ?? 1)
    }
    topicHandle.resize = { [weak self] delta in
      guard let self = self else { return }
      self.applyTopicScale(startTopicScale + delta / 300)
      view.layoutSubtreeIfNeeded()
    }
    refreshTopics(select: defaults.string(forKey: "selectedTopic") ?? "Разное")
    restoreEditingState()
    refreshTree()
    seedRecentNotes()
    window.center()
    window.setFrameAutosaveName("NotesWindowLayout")
    _ = window.setFrameUsingName("NotesWindowLayout")
    autoHide.state = defaults.bool(forKey: "autoHideSidebar") ? .on : .off
    setMenuVisible(!defaults.bool(forKey: "sidebarHidden"))
    window.makeFirstResponder(titleField)
    updateActionShortcuts()
    prepareQuickNoteService()
    startupComplete = true
    if pendingQuickNote {
      pendingQuickNote = false
      pendingRegularWindow = false
      openQuickNote()
    } else if pendingRegularWindow {
      pendingRegularWindow = false
      showWindow()
    }
  }

  var selectedTopicPath: String {
    topics.selectedItem?.representedObject as? String ?? ""
  }
  func configureStorage() -> Bool {
    if let path = defaults.string(forKey: "notesDirectory") {
      let saved = URL(fileURLWithPath: path, isDirectory: true)
      var directory: ObjCBool = false
      if FileManager.default.fileExists(atPath: saved.path, isDirectory: &directory),
        directory.boolValue
      {
        root = saved
        return true
      }
    }
    NSApp.activate(ignoringOtherApps: true)
    let panel = NSOpenPanel()
    panel.title = window == nil ? "Добро пожаловать в SimpleNotes" : "Папка заметок"
    panel.message =
      "Выбери или создай папку для заметок. Темы станут подпапками, записи будут обычными Markdown-файлами."
    panel.prompt = "Выбрать папку"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL =
      FileManager.default.fileExists(atPath: root.path)
      ? root : FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    guard panel.runModal() == .OK, let selected = panel.url else { return false }
    root = selected.standardizedFileURL
    defaults.set(root.path, forKey: "notesDirectory")
    return true
  }
  @objc func chooseStorage() {
    guard canLeaveNote() else { return }
    persistDraft()
    let oldRoot = root
    defaults.removeObject(forKey: "notesDirectory")
    guard configureStorage() else {
      root = oldRoot
      defaults.set(oldRoot.path, forKey: "notesDirectory")
      return
    }
    guard root != oldRoot else { return }
    noteBodyCache.removeAll()
    noteNotifications.removeAllPendingNotificationRequests()
    defaults.removeObject(forKey: "reminders")
    for key in [
      "draftTitle", "draftBody", "draftPath", "draftBaseline", "draftDate", "draftDirty",
      "recentNotes", "treeOrder", "itemColors", "collapsedFolders", "selectedTopic",
    ] { defaults.removeObject(forKey: key) }
    quickSaveTimer?.invalidate()
    quickSaveTimer = nil
    quickAutomaticTitle = quickMode
    quickTopicChanged = false
    quickStatus.stringValue = "Сохраняется автоматически"
    currentURL = nil
    loadedContent = nil
    noteDate = ""
    dirty = false
    titleField.stringValue = ""
    editor.string = ""
    editor.undoManager?.removeAllActions()
    searchField.stringValue = ""
    refreshTopics(select: "")
    refreshTree()
    seedRecentNotes()
    mode.selectedSegment = 0
    changeMode()
    persistDraft()
    status.stringValue = "Выбрана папка — " + root.lastPathComponent
  }

  func configureResizing(outer: NSView, main: NSView) {
    sideHandle.translatesAutoresizingMaskIntoConstraints = false
    sideHandle.toolTip = "Потяни границу, чтобы изменить ширину меню"
    outer.addSubview(sideHandle)
    NSLayoutConstraint.activate([
      sideHandle.centerXAnchor.constraint(equalTo: sidebarView.leadingAnchor),
      sideHandle.widthAnchor.constraint(equalToConstant: 10),
      sideHandle.topAnchor.constraint(equalTo: outer.topAnchor),
      sideHandle.bottomAnchor.constraint(equalTo: outer.bottomAnchor),
    ])
    var initialWidth: CGFloat = 280
    sideHandle.beginResize = { [weak self] in initialWidth = self?.sidebarWidth.constant ?? 280 }
    sideHandle.resize = { [weak self] delta in
      guard let self = self else { return }
      let width = min(max(210, initialWidth - delta), max(210, outer.bounds.width - 520))
      self.savedSidebarWidth = width
      self.sidebarWidth.constant = width
      self.mainTrailing.constant = -width
      self.outline.tableColumns.first?.width = max(80, width - 38)
      self.defaults.set(Double(width), forKey: "sidebarWidth")
      outer.layoutSubtreeIfNeeded()
    }
    headerHandle.vertical = false
    headerHandle.toolTip = "Потяни вверх или вниз, чтобы изменить верхнюю панель"
    var initialHeight: CGFloat = 220
    headerHandle.beginResize = { [weak self] in initialHeight = self?.headerHeight.constant ?? 220 }
    headerHandle.resize = { [weak self] delta in
      guard let self = self else { return }
      let maxScale = min(1.55, max(0.9, (main.bounds.height - 180) / 220))
      self.applyHeaderScale(min(maxScale, max(0.9, (initialHeight - delta) / 220)))
      main.layoutSubtreeIfNeeded()
    }
  }
  func applyHeaderScale(_ requested: CGFloat) {
    let widthLimit = max(
      0.9, (window.contentView!.bounds.width - (menuVisible ? savedSidebarWidth : 0)) / 520)
    let scale = min(max(0.9, requested), min(1.55, widthLimit))
    headingLabel.font = .systemFont(ofSize: 24 * scale, weight: .bold)
    titleField.font = .systemFont(ofSize: 20 * scale, weight: .medium)
    headerLabels.forEach { $0.font = .systemFont(ofSize: 13 * scale) }
    scaledConstraints.forEach { $0.0.constant = $0.1 * scale }
    titleHeight.constant = 36 * scale
    rowHeight.constant = 26 * scale
    headerHeight.constant = 220 * scale
    defaults.set(Double(scale), forKey: "headerScale")
    applyTopicScale(CGFloat(defaults.object(forKey: "topicScale") as? Double ?? 1))
  }
  func applyTopicScale(_ requested: CGFloat) {
    let headerScale = CGFloat(defaults.object(forKey: "headerScale") as? Double ?? 1)
    let available = max(
      300, window.contentView!.bounds.width - (menuVisible ? sidebarWidth.constant : 0) - 90)
    let scale = min(max(0.85, requested), min(1.8, available / (300 * headerScale)))
    let combined = scale * headerScale
    topics.font = .systemFont(ofSize: 13 * combined)
    topicControls.forEach { $0.font = .systemFont(ofSize: 13 * combined) }
    topicRowWidth.constant = 300 * combined
    rowHeight.constant = 26 * combined
    headerHeight.constant = 220 * headerScale + max(0, 26 * headerScale * (scale - 1))
    defaults.set(Double(scale), forKey: "topicScale")
  }
  func handleHorizontalGesture(delta: CGFloat) {
    suppressHoverUntil = Date().addingTimeInterval(1.5)
    manualRevealUntil = Date().addingTimeInterval(1.5)
    let reveal = delta > 0
    setMenuVisible(defaults.bool(forKey: "reverseSidebarSwipe") ? !reveal : reveal, animated: true)
  }
  func installGestures() {
    editor.gestureHandler = { [weak self] event in
      self?.processWindowGesture(event) ?? false
    }
    func acceptTouches(_ view: NSView) {
      view.allowedTouchTypes = [.indirect]
      for child in view.subviews { acceptTouches(child) }
    }
    if let content = window.contentView { acceptTouches(content) }
    if let monitor = gestureMonitor { NSEvent.removeMonitor(monitor) }
    gestureMonitor = NSEvent.addLocalMonitorForEvents(matching: [
      .scrollWheel, .swipe, .gesture, .beginGesture, .endGesture,
    ]) {
      [weak self] event in
      guard let self = self,
        event.window === self.window || (event.window == nil && self.window.isKeyWindow)
      else { return event }
      return self.processWindowGesture(event) ? nil : event
    }
  }
  func processWindowGesture(_ event: NSEvent) -> Bool {
    if event === lastGestureEvent { return lastGestureResult }
    lastGestureEvent = event
    lastGestureResult = updateWindowGesture(event)
    return lastGestureResult
  }
  func updateWindowGesture(_ event: NSEvent) -> Bool {
    guard !menuTracking else { return false }
    if event.type == .gesture || event.type == .beginGesture || event.type == .endGesture {
      let touches = event.touches(matching: .touching, in: nil).filter { $0.type == .indirect }
      guard touches.count == 2 else {
        touchOrigin = nil
        touchSwipeRecognized = false
        return false
      }
      let center = NSPoint(
        x: touches.reduce(0) { $0 + $1.normalizedPosition.x } / 2,
        y: touches.reduce(0) { $0 + $1.normalizedPosition.y } / 2)
      guard let origin = touchOrigin else {
        touchOrigin = center
        return false
      }
      let x = center.x - origin.x
      let y = center.y - origin.y
      if !touchSwipeRecognized && abs(x) > 0.045 && abs(x) > abs(y) * 1.5 {
        touchSwipeRecognized = true
        if !swipe.recognized { handleHorizontalGesture(delta: -x) }
      }
      return false
    }
    if touchSwipeRecognized && event.type == .scrollWheel { return true }
    if event.type == .swipe {
      guard abs(event.deltaX) > abs(event.deltaY), event.deltaX != 0 else { return false }
      handleHorizontalGesture(delta: event.deltaX)
      return true
    }
    guard event.type == .scrollWheel, event.momentumPhase.isEmpty else { return false }
    let ended = event.phase.contains(.ended) || event.phase.contains(.cancelled)
    let alreadyHandled = swipe.recognized
    let rawX = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.deltaX
    let rawY = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
    let physicalX = event.isDirectionInvertedFromDevice ? -rawX : rawX
    if let direction = swipe.update(
      x: physicalX, y: rawY, time: event.timestamp, began: event.phase.contains(.began),
      ended: ended)
    {
      handleHorizontalGesture(delta: direction)
      return true
    }
    return ended ? alreadyHandled : swipe.recognized
  }
  func handleHover(_ point: NSPoint, in outer: NSView) {
    guard !quickMode, !menuTracking, Date() >= suppressHoverUntil else { return }
    if menuVisible && Date() < manualRevealUntil { return }
    let inRevealZone = point.x >= outer.bounds.width - 24
    let outsideHoldZone = point.x < outer.bounds.width - sidebarWidth.constant - 80
    let editingSearch =
      window.firstResponder === searchField.currentEditor() && searchField.currentEditor() != nil
    let desired: Bool? =
      !menuVisible && inRevealZone
      ? true
      : (menuVisible && autoHide.state == .on && outsideHoldZone && !editingSearch ? false : nil)
    guard let desired = desired else {
      hoverTimer?.invalidate()
      hoverTimer = nil
      pendingVisibility = nil
      return
    }
    if pendingVisibility == desired { return }
    hoverTimer?.invalidate()
    pendingVisibility = desired
    hoverTimer = Timer.scheduledTimer(withTimeInterval: desired ? 0.12 : 0.5, repeats: false) {
      [weak self] _ in
      self?.pendingVisibility = nil
      self?.hoverTimer = nil
      guard NSEvent.pressedMouseButtons == 0 else { return }
      self?.setMenuVisible(desired, animated: true)
    }
  }
  func setMenuVisible(_ visible: Bool, animated: Bool = false) {
    guard !quickMode else { return }
    hoverTimer?.invalidate()
    hoverTimer = nil
    pendingVisibility = nil
    animationGeneration += 1
    let generation = animationGeneration
    menuVisible = visible
    sidebarView.isHidden = false
    sideHandle.isHidden = !visible
    let width = min(savedSidebarWidth, max(210, window.contentView!.bounds.width - 520))
    sidebarWidth.constant = width
    outline.tableColumns.first?.width = max(80, width - 38)
    menuToggle.title = visible ? "Скрыть меню ▸" : "◂ Меню"
    defaults.set(!visible, forKey: "sidebarHidden")
    NSAnimationContext.runAnimationGroup { context in
      context.duration = animated ? 0.26 : 0
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      context.allowsImplicitAnimation = true
      mainTrailing.animator().constant = visible ? -width : 0
      sidebarTrailing.animator().constant = visible ? 0 : width
      window.contentView?.layoutSubtreeIfNeeded()
    } completionHandler: { [weak self] in
      guard let self = self, self.animationGeneration == generation else { return }
      self.sidebarView.isHidden = !visible
    }
  }
  @objc func toggleMenu() {
    if !menuVisible { manualRevealUntil = Date().addingTimeInterval(2) }
    setMenuVisible(!menuVisible, animated: true)
  }
  @objc func toggleAutoHide() {
    autoHide.state = autoHide.state == .on ? .off : .on
    defaults.set(autoHide.state == .on, forKey: "autoHideSidebar")
    if autoHide.state == .off { setMenuVisible(true, animated: true) }
  }
  @objc func showSettings() {
    hoverTimer?.invalidate()
    if settingsController == nil { settingsController = NotesSettingsController(app: self) }
    settingsController?.refresh()
    settingsController?.showWindow(nil)
    settingsController?.window?.makeKeyAndOrderFront(nil)
  }
  @objc func toggleDate() {
    defaults.set(!showDates, forKey: "showDates")
    status.stringValue =
      showDates && !noteDate.isEmpty ? "\(noteDate)" : "Готово"
    if mode.selectedSegment == 1 { renderMarkdown() }
  }
  @objc func changeTheme(_ sender: NSMenuItem) {
    defaults.set(sender.representedObject as? String, forKey: "appearance")
    applyTheme()
    refreshTree()
  }
  func applyTheme() {
    switch defaults.string(forKey: "appearance") {
    case "light": NSApp.appearance = NSAppearance(named: .aqua)
    case "dark", "graphite": NSApp.appearance = NSAppearance(named: .darkAqua)
    default: NSApp.appearance = nil
    }
    applyGraphiteChrome()
    applyEditorStyle()
  }
  func windowDidResize(_ notification: Notification) {
    guard !quickMode, sidebarWidth != nil, headerHeight != nil else { return }
    setMenuVisible(menuVisible)
    applyHeaderScale(CGFloat(defaults.object(forKey: "headerScale") as? Double ?? 1))
    renderSidebarReminders()
  }

  func buildMenu() {
    let menu = NSMenu()
    let appItem = NSMenuItem()
    menu.addItem(appItem)
    let appMenu = NSMenu()
    let settings = appMenu.addItem(
      withTitle: "Настройки…", action: #selector(showSettings), keyEquivalent: ",")
    settings.target = self
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "Завершить", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    let editItem = NSMenuItem()
    menu.addItem(editItem)
    let editMenu = NSMenu(title: "Правка")
    for (name, selector, key) in [
      ("Отменить", "undo:", "z"), ("Вырезать", "cut:", "x"), ("Скопировать", "copy:", "c"),
      ("Вставить", "paste:", "v"), ("Выбрать всё", "selectAll:", "a"),
    ] {
      editMenu.addItem(withTitle: name, action: Selector(selector), keyEquivalent: key)
    }
    let redo = editMenu.insertItem(
      withTitle: "Повторить", action: NSSelectorFromString("redo:"), keyEquivalent: "z", at: 1)
    redo.keyEquivalentModifierMask = [.command, .shift]
    editItem.submenu = editMenu
    let windowItem = NSMenuItem()
    let windowMenu = NSMenu(title: "Окно")
    windowMenu.addItem(
      withTitle: "Закрыть окно", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    windowItem.submenu = windowMenu
    menu.addItem(windowItem)
    NSApp.windowsMenu = windowMenu
    installActionShortcuts(in: menu)
    NSApp.mainMenu = menu
    editor.allowsUndo = true
  }

  func refreshTopics(select name: String) {
    do {
      func folderPaths(_ entries: [NoteNode]) -> [String] {
        entries.filter { $0.isFolder }.flatMap { node in
          [String(node.url.path.dropFirst(root.path.count + 1))] + folderPaths(node.children)
        }
      }
      let folders = folderPaths(try folderNodes(in: root))
      topics.removeAllItems()
      topics.addItem(withTitle: "Без папки")
      topics.lastItem?.representedObject = ""
      for folder in folders {
        topics.addItem(withTitle: folder)
        topics.lastItem?.representedObject = folder
      }
      if let selected = topics.itemArray.first(where: { ($0.representedObject as? String) == name })
      {
        topics.select(selected)
      } else {
        topics.selectItem(at: 0)
      }
      syncQuickTopics()
    } catch { showError(error.localizedDescription) }
  }

  @objc func topicChanged() {
    defaults.set(selectedTopicPath, forKey: "selectedTopic")
    if currentURL != nil { dirty = true }
  }
  func persistDraft() {
    defaults.set(titleField.stringValue, forKey: "draftTitle")
    defaults.set(editor.string, forKey: "draftBody")
    defaults.set(selectedTopicPath, forKey: "selectedTopic")
    defaults.set(currentURL?.path, forKey: "draftPath")
    defaults.set(loadedContent, forKey: "draftBaseline")
    defaults.set(noteDate, forKey: "draftDate")
    defaults.set(dirty, forKey: "draftDirty")
  }
  func textDidChange(_ notification: Notification) {
    dirty = true
    persistDraft()
    editor.needsDisplay = true
    scheduleQuickSave()
  }
  func controlTextDidChange(_ notification: Notification) {
    if notification.object as? NSSearchField === searchField {
      searchWork?.cancel()
      let work = DispatchWorkItem { [weak self] in self?.applySearch() }
      searchWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
      return
    }
    dirty = true
    persistDraft()
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if quickMode { flushQuickSave() }
    persistDraft()
    return true
  }
  func applicationWillTerminate(_ notification: Notification) {
    if quickMode { flushQuickSave() }
    persistDraft()
  }
  func showWindow() {
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  static func isServiceLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
    event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
      == AEKeyword(keyAELaunchedAsServiceItem)
  }

  func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
    // Services request their own compact window after startup has completed.
    guard !Self.isServiceLaunch(NSAppleEventManager.shared().currentAppleEvent) else { return false }
    if startupComplete {
      showWindow()
    } else {
      pendingRegularWindow = true
    }
    return false
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    guard !Self.isServiceLaunch(NSAppleEventManager.shared().currentAppleEvent) else { return false }
    guard startupComplete else {
      pendingRegularWindow = true
      return true
    }
    expandQuickNote()
    refreshTopics(select: selectedTopicPath)
    refreshTree()
    showWindow()
    return true
  }

  @objc func addTopic() {
    let alert = NSAlert()
    alert.messageText = "Новая тема"
    alert.informativeText = "Папка появится автоматически."
    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
    alert.accessoryView = input
    alert.addButton(withTitle: "Создать")
    alert.addButton(withTitle: "Отмена")
    alert.window.initialFirstResponder = input
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !name.hasPrefix("."), !name.lowercased().hasSuffix(".app"),
      name.rangeOfCharacter(from: CharacterSet(charactersIn: "/:\n\r\0")) == nil
    else {
      showError(
        "Введи название без слешей, двоеточий и переносов строк. Оно не должно начинаться с точки или заканчиваться на .app."
      )
      return
    }
    do {
      try FileManager.default.createDirectory(
        at: root.appendingPathComponent(name), withIntermediateDirectories: true)
      refreshTopics(select: name)
      topicChanged()
      refreshTree()
    } catch { showError(error.localizedDescription) }
  }

  @objc func openAllNotes() { NSWorkspace.shared.open(root) }
  @objc func openFolder() {
    let topic = selectedTopicPath
    NSWorkspace.shared.open(root.appendingPathComponent(topic))
  }

  @objc func saveNote() { _ = saveCurrent() }
  @discardableResult func saveCurrent(preservingExistingFile: Bool = false) -> Bool {
    let body = editor.string
    let previousTitle = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    var title = previousTitle
    let firstLine = String(body.split(whereSeparator: \.isNewline).first ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if quickMode && quickAutomaticTitle && !firstLine.isEmpty {
      title = firstLine
    }
    if title.isEmpty {
      title = String(body.split(whereSeparator: \.isNewline).first ?? "").trimmingCharacters(
        in: .whitespacesAndNewlines)
    }
    guard !title.isEmpty else {
      showError("Напиши название или текст заметки.")
      return false
    }
    let topic = selectedTopicPath
    var safeTitle = String(title.prefix(80)).components(
      separatedBy: CharacterSet(charactersIn: "/:\n\r\0")
    ).joined(separator: "-")
    if safeTitle.hasPrefix(".") { safeTitle = "Заметка " + safeTitle }
    let formatter = DateFormatter()
    formatter.dateFormat = "dd.MM.yyyy HH:mm"
    let automaticRetitle = quickMode && quickAutomaticTitle && title != previousTitle
    let existingURL = preservingExistingFile && !automaticRetitle ? currentURL : nil
    let originalLines = loadedContent?.components(separatedBy: "\n") ?? []
    let hasMetadata = NoteMetadata.hasHeader(originalLines)
    let preservePlainText = currentURL != nil && !hasMetadata
    let date =
      preservePlainText ? "" : (noteDate.isEmpty ? formatter.string(from: Date()) : noteDate)
    let content =
      preservePlainText
      ? body : "\(title)\n\(date)\nТема — \(topic.isEmpty ? "Без папки" : topic)\n\n\(body)"
    do {
      if let oldURL = currentURL {
        guard try String(contentsOf: oldURL, encoding: .utf8) == loadedContent else {
          showError(
            "Файл изменён вне приложения. Скопируй свой текст и открой заметку заново, чтобы сохранить обе версии."
          )
          return false
        }
      }
      let folder = existingURL?.deletingLastPathComponent() ?? root.appendingPathComponent(topic)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let fileExtension = currentURL?.pathExtension ?? "md"
      var suffix = 1
      var destination: URL
      if let existingURL = existingURL {
        try Data(content.utf8).write(to: existingURL, options: .atomic)
        destination = existingURL
      } else {
        while true {
          let filename = suffix == 1
            ? "\(safeTitle).\(fileExtension)" : "\(safeTitle) (\(suffix)).\(fileExtension)"
          destination = folder.appendingPathComponent(filename)
          if let current = currentURL,
            destination.standardizedFileURL.resolvingSymlinksInPath()
              == current.standardizedFileURL.resolvingSymlinksInPath() {
            destination = current
            try Data(content.utf8).write(to: destination, options: .atomic)
            break
          }
          do {
            try Data(content.utf8).write(to: destination, options: .withoutOverwriting)
            break
          } catch let error as NSError
            where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError
          { suffix += 1 }
        }
      }
      if let old = currentURL, old != destination {
        // Keep the original until the complete replacement has been written.
        try FileManager.default.removeItem(at: old)
      }
      if let old = currentURL { remapColors(from: old, to: destination) }
      currentURL = destination
      recordRecent(destination)
      loadedContent = content
      noteDate = date
      titleField.stringValue = title
      dirty = false
      if quickMode { quickStatus.stringValue = "✓ Сохранено" }
      persistDraft()
      noteBodyCache.removeValue(forKey: destination)
      refreshTree()
      status.stringValue =
        "Сохранено в «\(topic.isEmpty ? "Без папки" : topic)»"
        + (showDates && !date.isEmpty ? " · \(date)" : "")
      if mode.selectedSegment == 1 { renderMarkdown() }
      return true
    } catch {
      showError(error.localizedDescription)
      return false
    }
  }

  func buildSidebar(_ sidebar: NSView) {
    let label = NSTextField(labelWithString: "Темы и заметки")
    label.font = .systemFont(ofSize: 16, weight: .semibold)
    let newButton = NSButton(title: "+ Новая заметка", target: self, action: #selector(newNote))
    let refresh = refreshButton
    refresh.target = self
    refresh.action = #selector(refreshLibrary)
    refresh.toolTip = "Перечитать папки и заметки с диска · ⌘R"
    mode.toolTip = "Рендер — отображение Markdown и формул LaTeX"
    let reminders = makeReminderList()
    settingsButton.target = self
    settingsButton.action = #selector(showSettings)
    settingsButton.font = .systemFont(ofSize: 22)
    settingsButton.toolTip = "Настройки меню и темы приложения"
    searchField.placeholderString = "Поиск по всем заметкам"
    searchField.delegate = self
    searchField.sendsSearchStringImmediately = true
    searchField.sendsWholeSearchString = false
    searchStatus.font = .systemFont(ofSize: 11)
    searchStatus.textColor = .secondaryLabelColor
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("notes"))
    column.width = 250
    column.minWidth = 80
    column.resizingMask = .autoresizingMask
    outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    outline.addTableColumn(column)
    outline.outlineTableColumn = column
    outline.headerView = nil
    outline.rowHeight = 32
    outline.indentationPerLevel = 16
    outline.delegate = self
    outline.dataSource = self
    outline.target = self
    outline.action = #selector(openSelection)
    outline.registerForDraggedTypes([noteDragType])
    outline.setDraggingSourceOperationMask(.move, forLocal: true)
    outline.draggingDestinationFeedbackStyle = .regular
    let contextMenu = NSMenu()
    contextMenu.delegate = self
    outline.menu = contextMenu
    outline.toolTip =
      "Потяни между строками для перестановки. Option + перетаскивание — перенос в папку. Правая кнопка — цвет."
    scroll.documentView = outline
    for item in [label, newButton, searchField, searchStatus, scroll, reminders, refresh, settingsButton] {
      item.translatesAutoresizingMaskIntoConstraints = false
      sidebar.addSubview(item)
    }
    NSLayoutConstraint.activate([
      label.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 26),
      label.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
      newButton.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 16),
      newButton.leadingAnchor.constraint(equalTo: label.leadingAnchor),
      newButton.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
      searchField.topAnchor.constraint(equalTo: newButton.bottomAnchor, constant: 12),
      searchField.leadingAnchor.constraint(equalTo: label.leadingAnchor),
      searchField.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
      searchField.heightAnchor.constraint(equalToConstant: 28),
      searchStatus.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 5),
      searchStatus.leadingAnchor.constraint(equalTo: label.leadingAnchor),
      searchStatus.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: searchStatus.bottomAnchor, constant: 6),
      scroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: reminders.topAnchor, constant: -10),
      reminders.leadingAnchor.constraint(equalTo: label.leadingAnchor),
      reminders.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
      reminders.bottomAnchor.constraint(equalTo: refresh.topAnchor, constant: -10),
      settingsButton.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
      settingsButton.centerYAnchor.constraint(equalTo: refresh.centerYAnchor),
      settingsButton.widthAnchor.constraint(equalToConstant: 36),
      refresh.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -20),
      refresh.leadingAnchor.constraint(equalTo: label.leadingAnchor),
      refresh.trailingAnchor.constraint(
        lessThanOrEqualTo: settingsButton.leadingAnchor, constant: -6),
    ])
  }
  @objc func refreshLibrary() {
    manualRefreshStarted = Date()
    refreshButton.title = "Обновление…"
    refreshButton.toolTip = "Читаю папки и заметки с диска…"
    refreshButton.isEnabled = false
    refreshTopics(select: selectedTopicPath)
    refreshTree()
  }

  func finishManualRefresh(generation: Int, directory: URL, succeeded: Bool) {
    guard let started = manualRefreshStarted else { return }
    // Keep the progress state visible even when the library is tiny.
    let delay = max(0, 0.35 - Date().timeIntervalSince(started))
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self = self, self.indexGeneration == generation, self.root == directory,
        self.manualRefreshStarted == started else { return }
      self.manualRefreshStarted = nil
      self.refreshButton.isEnabled = true
      if succeeded {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let time = formatter.string(from: Date())
        self.refreshButton.title = "✓ Обновлено"
        self.refreshButton.toolTip = "Папки и заметки перечитаны с диска в \(time) · ⌘R — обновить снова"
        if self.searchQuery.isEmpty { self.searchStatus.stringValue = "Обновлено в \(time)" }
      } else {
        self.refreshButton.title = "Повторить обновление"
        self.refreshButton.toolTip = "Не удалось обновить список. Нажми, чтобы повторить."
      }
    }
  }

  @objc func refreshTree() {
    refreshReminderList()
    if indexedRoot != root {
      indexedRoot = root
      allNotes = []
      noteBodyCache.removeAll()
      applySearch()
    }
    indexGeneration += 1
    let generation = indexGeneration
    let directory = root
    let order = customOrder
    let cached = noteBodyCache
    indexQueue.cancelAllOperations()
    indexQueue.addOperation { [weak self] in
      var scanner = NoteIndexScanner(root: directory, order: order, cache: cached)
      let result = Result { try scanner.scan() }
      let updatedCache = scanner.cache
      DispatchQueue.main.async { [weak self] in
        guard let self = self, self.indexGeneration == generation, self.root == directory else {
          return
        }
        switch result {
        case .success(let notes):
          self.allNotes = notes
          self.noteBodyCache = updatedCache
          self.applySearch()
          self.finishManualRefresh(generation: generation, directory: directory, succeeded: true)
        case .failure(let error):
          self.loadingTree = false
          self.finishManualRefresh(generation: generation, directory: directory, succeeded: false)
          self.showError(error.localizedDescription)
        }
      }
    }
  }
  func applySearch() {
    let selectedURLs = outline.selectedRowIndexes.compactMap {
      (outline.item(atRow: $0) as? NoteNode)?.url
    }
    let query = searchQuery
    var count = 0
    func filter(_ nodes: [NoteNode]) -> [NoteNode] {
      nodes.compactMap { node in
        if node.isFolder {
          let children = filter(node.children)
          return query.isEmpty || !children.isEmpty
            ? NoteNode(url: node.url, children: children, isFolder: true, count: node.noteCount)
            : nil
        }
        let bodyMatch =
          query.isEmpty
          ? nil
          : node.searchBody.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
        let titleMatch = node.url.deletingPathExtension().lastPathComponent.range(
          of: query, options: [.caseInsensitive, .diacriticInsensitive])
        guard query.isEmpty || bodyMatch != nil || titleMatch != nil else { return nil }
        node.snippet = ""
        if let range = bodyMatch {
          let start =
            node.searchBody.index(
              range.lowerBound, offsetBy: -35, limitedBy: node.searchBody.startIndex)
            ?? node.searchBody.startIndex
          let end =
            node.searchBody.index(
              range.upperBound, offsetBy: 100, limitedBy: node.searchBody.endIndex)
            ?? node.searchBody.endIndex
          node.snippet =
            (start > node.searchBody.startIndex ? "…" : "")
            + node.searchBody[start..<end].components(separatedBy: .whitespacesAndNewlines).filter {
              !$0.isEmpty
            }.joined(separator: " ") + (end < node.searchBody.endIndex ? "…" : "")
        } else if !query.isEmpty {
          node.snippet = "Совпадение в названии"
        }
        count += 1
        return node
      }
    }
    tree = filter(allNotes)
    searchStatus.stringValue =
      query.isEmpty ? "" : (count == 0 ? "Ничего не найдено" : "Найдено заметок — \(count)")
    loadingTree = true
    outline.reloadData()
    outline.expandItem(nil, expandChildren: true)
    if query.isEmpty {
      let collapsed = Set(defaults.stringArray(forKey: "collapsedFolders") ?? [])
      for path in collapsed.sorted(by: { $0.count > $1.count }) {
        if let node = findNode(root.appendingPathComponent(path), in: tree) {
          outline.collapseItem(node)
        }
      }
    }
    let selection = IndexSet(
      selectedURLs.compactMap { url in
        guard let node = findNode(url, in: tree) else { return nil }
        let row = outline.row(forItem: node)
        return row >= 0 ? row : nil
      })
    outline.selectRowIndexes(selection, byExtendingSelection: false)
    loadingTree = false
  }
  func outlineViewItemDidExpand(_ notification: Notification) {
    saveFolderExpansion(notification, collapsed: false)
  }
  func outlineViewItemDidCollapse(_ notification: Notification) {
    saveFolderExpansion(notification, collapsed: true)
  }
  func saveFolderExpansion(_ notification: Notification, collapsed: Bool) {
    guard !loadingTree, searchQuery.isEmpty,
      let node = notification.userInfo?["NSObject"] as? NoteNode
    else { return }
    var paths = Set(defaults.stringArray(forKey: "collapsedFolders") ?? [])
    if collapsed {
      paths.insert(relativePath(node.url))
    } else {
      paths.remove(relativePath(node.url))
    }
    defaults.set(Array(paths), forKey: "collapsedFolders")
  }
  func relativePath(_ url: URL) -> String {
    url == root ? "" : String(url.path.dropFirst(root.path.count + 1))
  }
  func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any)
    -> NSPasteboardWriting?
  {
    guard searchQuery.isEmpty, let node = item as? NoteNode else { return nil }
    let writer = NSPasteboardItem()
    writer.setString(node.url.path, forType: noteDragType)
    return writer
  }
  func draggedURL(_ info: NSDraggingInfo) -> URL? {
    guard info.draggingSource as? NSOutlineView === outline,
      let path = info.draggingPasteboard.string(forType: noteDragType)
    else { return nil }
    let url = URL(fileURLWithPath: path).standardizedFileURL
    return url.path.hasPrefix(root.path + "/") ? url : nil
  }
  func findNode(_ url: URL, in nodes: [NoteNode]) -> NoteNode? {
    for node in nodes {
      if node.url.resolvingSymlinksInPath().path == url.resolvingSymlinksInPath().path { return node }
      if let found = findNode(url, in: node.children) { return found }
    }
    return nil
  }
  func outlineView(
    _ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?,
    proposedChildIndex index: Int
  ) -> NSDragOperation {
    guard searchQuery.isEmpty, let source = draggedURL(info) else { return [] }
    if !NSEvent.modifierFlags.contains(.option) {
      let parentURL = source.deletingLastPathComponent()
      let parentNode = parentURL == root ? nil : findNode(parentURL, in: tree)
      let siblings = parentNode?.children ?? tree
      let pointer = outline.convert(info.draggingLocation, from: nil)
      var candidates: [(Int, CGFloat)] = []
      for (position, node) in siblings.enumerated() {
        let row = outline.row(forItem: node)
        if row >= 0 { candidates.append((position, outline.rect(ofRow: row).minY)) }
      }
      if let last = siblings.last {
        var row = outline.row(forItem: last)
        if row >= 0 {
          let level = outline.level(forRow: row)
          while row + 1 < outline.numberOfRows && outline.level(forRow: row + 1) > level {
            row += 1
          }
          candidates.append((siblings.count, outline.rect(ofRow: row).maxY))
        }
      }
      guard let nearest = candidates.min(by: { abs($0.1 - pointer.y) < abs($1.1 - pointer.y) })
      else { return [] }
      outline.setDropItem(parentNode, dropChildIndex: nearest.0)
      let level = parentNode.map { outline.level(forItem: $0) + 1 } ?? 0
      outline.showGuide(at: nearest.1, indent: CGFloat(level + 1) * outline.indentationPerLevel)
      return .move
    }
    outline.guide.isHidden = true
    let destinationNode = item as? NoteNode
    guard item == nil || destinationNode?.isFolder == true else { return [] }
    let parent = destinationNode?.url ?? root
    let isFolder = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    guard parent != root || isFolder else { return [] }
    guard parent != source, !parent.path.hasPrefix(source.path + "/") else { return [] }
    return .move
  }
  func outlineView(
    _ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
    endedAt screenPoint: NSPoint, operation: NSDragOperation
  ) {
    outline.guide.isHidden = true
  }
  func outlineView(
    _ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
    willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]
  ) {
    session.animatesToStartingPositionsOnCancelOrFail = true
  }
  func outlineView(
    _ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int
  ) -> Bool {
    guard searchQuery.isEmpty, var source = draggedURL(info) else { return false }
    let parentNode = item as? NoteNode
    guard item == nil || parentNode?.isFolder == true else { return false }
    let parent = parentNode?.url ?? root
    guard NSEvent.modifierFlags.contains(.option) || parent == source.deletingLastPathComponent()
    else { return false }
    outline.guide.isHidden = true
    let isFolder = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    guard parent != root || isFolder else { return false }
    guard parent != source, !parent.path.hasPrefix(source.path + "/") else { return false }
    let movingCurrentNote = currentURL == source
    let containsCurrentNote = currentURL.map { $0.path.hasPrefix(source.path + "/") } ?? false
    if movingCurrentNote || containsCurrentNote {
      guard canLeaveNote() else { return false }
      if movingCurrentNote, let savedURL = currentURL { source = savedURL }
    }
    do {
      let oldParent = source.deletingLastPathComponent()
      let siblings = try orderedNoteEntries(in: parent, root: root, order: customOrder).map {
        $0.lastPathComponent
      }
      var insertion = index < 0 ? siblings.count : min(index, siblings.count)
      if oldParent == parent, let oldIndex = siblings.firstIndex(of: source.lastPathComponent),
        oldIndex < insertion
      {
        insertion -= 1
      }
      var ordered = siblings.filter { $0 != source.lastPathComponent || oldParent != parent }
      let target = parent.appendingPathComponent(source.lastPathComponent)
      guard target == source || !FileManager.default.fileExists(atPath: target.path) else {
        showError("В этой папке уже есть файл или тема с таким названием. Перенос отменён.")
        return false
      }
      if source != target { try FileManager.default.moveItem(at: source, to: target) }
      ordered.insert(target.lastPathComponent, at: min(max(0, insertion), ordered.count))
      var order = customOrder
      if oldParent != parent {
        order[relativePath(oldParent)] = (order[relativePath(oldParent)] ?? []).filter {
          $0 != source.lastPathComponent
        }
        let oldKey = relativePath(source)
        let newKey = relativePath(target)
        for key in Array(order.keys) where key == oldKey || key.hasPrefix(oldKey + "/") {
          order[newKey + key.dropFirst(oldKey.count)] = order.removeValue(forKey: key)
        }
      }
      order[relativePath(parent)] = ordered
      defaults.set(order, forKey: "treeOrder")
      remapColors(from: source, to: target)
      if let opened = currentURL, movingCurrentNote || containsCurrentNote {
        let suffix = String(opened.path.dropFirst(source.path.count))
        let movedURL = URL(fileURLWithPath: target.path + suffix)
        currentURL = movedURL
        let topic = relativePath(movedURL.deletingLastPathComponent())
        refreshTopics(select: topic)
        persistDraft()
      } else {
        refreshTopics(select: selectedTopicPath)
      }
      applyMovedSnapshot(from: source, to: target)
      refreshTree()
      if let movedNode = findNode(target, in: tree) {
        let row = outline.row(forItem: movedNode)
        if row >= 0 {
          let destinationRect = outline.rect(ofRow: row)
          info.animatesToDestination = true
          info.enumerateDraggingItems(
            options: [], for: outline, classes: [NSPasteboardItem.self], searchOptions: [:]
          ) { item, _, _ in
            item.draggingFrame = destinationRect
          }
        }
      }
      status.stringValue =
        source == target
        ? "Порядок сохранён"
        : "Перемещено в «\(parent == root ? "SimpleNotes" : parent.lastPathComponent)»"
      return true
    } catch {
      showError(error.localizedDescription)
      return false
    }
  }
  func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
    guard let node = item as? NoteNode else { return 32 }
    return node.snippet.isEmpty ? 32 : 76
  }
  func highlighted(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
    let result = NSMutableAttributedString(
      string: text, attributes: [.font: font, .foregroundColor: color])
    if !searchQuery.isEmpty {
      let range = (text as NSString).range(
        of: searchQuery, options: [.caseInsensitive, .diacriticInsensitive])
      if range.location != NSNotFound {
        result.addAttributes(
          [
            .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.3),
            .foregroundColor: NSColor.labelColor,
          ], range: range)
      }
    }
    return result
  }
  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    (item as? NoteNode)?.children.count ?? tree.count
  }
  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    ((item as? NoteNode)?.children ?? tree)[index]
  }
  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    (item as? NoteNode)?.isFolder == true
  }
  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any)
    -> NSView?
  {
    guard let node = item as? NoteNode else { return nil }
    let cell = NSTableCellView()
    let field = NSTextField(
      labelWithString: node.isFolder
        ? node.url.lastPathComponent : node.url.deletingPathExtension().lastPathComponent)
    let tint = colorPalette.first { $0.1 == itemColors[relativePath(node.url)] }?.2
    let icon = NSImageView()
    icon.image = NSImage(
      systemSymbolName: node.isFolder ? "folder.fill" : "doc.text",
      accessibilityDescription: node.isFolder ? "Папка" : "Заметка")
    icon.contentTintColor = tint ?? (isGraphite ? GraphitePalette.accent : .secondaryLabelColor)
    icon.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(icon)
    NSLayoutConstraint.activate([
      icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
      icon.widthAnchor.constraint(equalToConstant: 16),
      icon.heightAnchor.constraint(equalToConstant: 18),
      icon.topAnchor.constraint(equalTo: cell.topAnchor, constant: 7),
    ])
    field.attributedStringValue = highlighted(
      field.stringValue,
      font: .systemFont(ofSize: 13, weight: node.isFolder ? .semibold : .regular),
      color: tint ?? (isGraphite ? GraphitePalette.text : .labelColor))
    field.maximumNumberOfLines = 1
    field.lineBreakMode = .byTruncatingTail
    field.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(field)
    cell.textField = field
    cell.toolTip = node.url.lastPathComponent
    field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6).isActive = true
    if node.isFolder {
      let count = NSTextField(labelWithString: String(node.noteCount))
      count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
      count.textColor = .secondaryLabelColor
      count.alignment = .right
      count.toolTip = "Заметок в папке и подпапках — \(node.noteCount)"
      count.translatesAutoresizingMaskIntoConstraints = false
      cell.addSubview(count)
      NSLayoutConstraint.activate([
        count.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
        count.centerYAnchor.constraint(equalTo: field.centerYAnchor),
        count.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
        field.trailingAnchor.constraint(equalTo: count.leadingAnchor, constant: -8),
      ])
    } else {
      field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4).isActive = true
    }
    if node.snippet.isEmpty {
      field.centerYAnchor.constraint(equalTo: cell.centerYAnchor).isActive = true
    } else {
      field.topAnchor.constraint(equalTo: cell.topAnchor, constant: 5).isActive = true
      let snippet = NSTextField(wrappingLabelWithString: node.snippet)
      snippet.attributedStringValue = highlighted(
        node.snippet, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
      snippet.maximumNumberOfLines = 2
      snippet.lineBreakMode = .byTruncatingTail
      snippet.translatesAutoresizingMaskIntoConstraints = false
      cell.addSubview(snippet)
      NSLayoutConstraint.activate([
        snippet.leadingAnchor.constraint(equalTo: field.leadingAnchor),
        snippet.trailingAnchor.constraint(equalTo: field.trailingAnchor),
        snippet.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 4),
        snippet.heightAnchor.constraint(equalToConstant: 30),
        snippet.bottomAnchor.constraint(lessThanOrEqualTo: cell.bottomAnchor, constant: -5),
      ])
      cell.toolTip = node.snippet
    }
    return cell
  }
  func seedRecentNotes() {
    guard defaults.object(forKey: "recentNotes") == nil else { return }
    func files(_ nodes: [NoteNode]) -> [URL] {
      nodes.flatMap { $0.isFolder ? files($0.children) : [$0.url] }
    }
    let recent = files(allNotes).sorted {
      let first =
        (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? .distantPast
      let second =
        (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? .distantPast
      return first > second
    }
    defaults.set(Array(recent.prefix(10)).map { relativePath($0) }, forKey: "recentNotes")
    rebuildRecentMenu()
  }
  func recordRecent(_ url: URL) {
    let key = relativePath(url)
    var history = defaults.stringArray(forKey: "recentNotes") ?? []
    history.removeAll { $0 == key }
    history.insert(key, at: 0)
    defaults.set(Array(history.prefix(10)), forKey: "recentNotes")
    rebuildRecentMenu()
  }
  func rebuildRecentMenu() {
    guard let menu = recentButton.menu else { return }
    menu.removeAllItems()
    menu.addItem(NSMenuItem(title: "Недавние ▾", action: nil, keyEquivalent: ""))
    let history = defaults.stringArray(forKey: "recentNotes") ?? []
    let valid = history.filter {
      FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
    }
    for path in valid {
      let url = root.appendingPathComponent(path)
      let name = url.deletingPathExtension().lastPathComponent
      let item = NSMenuItem(
        title: name + " — " + url.deletingLastPathComponent().lastPathComponent,
        action: #selector(openRecent(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = path
      item.toolTip = path
      menu.addItem(item)
    }
    if valid.isEmpty {
      let empty = NSMenuItem(
        title: "Здесь появятся открытые и сохранённые заметки", action: nil, keyEquivalent: "")
      empty.isEnabled = false
      menu.addItem(empty)
    }
  }
  @objc func openRecent(_ sender: NSMenuItem) {
    guard let path = sender.representedObject as? String else { return }
    openNote(root.appendingPathComponent(path))
  }
  func remapColors(from source: URL, to target: URL) {
    remapReminders(from: source, to: target)
    guard source != target else { return }
    var colors = itemColors
    let oldKey = relativePath(source)
    let newKey = relativePath(target)
    for key in Array(colors.keys) where key == oldKey || key.hasPrefix(oldKey + "/") {
      colors[newKey + key.dropFirst(oldKey.count)] = colors.removeValue(forKey: key)
    }
    defaults.set(colors, forKey: "itemColors")
    var order = customOrder
    let oldParent = relativePath(source.deletingLastPathComponent())
    let newParent = relativePath(target.deletingLastPathComponent())
    if oldParent == newParent {
      order[oldParent] = order[oldParent]?.map {
        $0 == source.lastPathComponent ? target.lastPathComponent : $0
      }
    } else {
      order[oldParent] = order[oldParent]?.filter { $0 != source.lastPathComponent }
      if var siblings = order[newParent], !siblings.contains(target.lastPathComponent) {
        siblings.append(target.lastPathComponent)
        order[newParent] = siblings
      }
    }
    for key in Array(order.keys) where key == oldKey || key.hasPrefix(oldKey + "/") {
      order[newKey + key.dropFirst(oldKey.count)] = order.removeValue(forKey: key)
    }
    defaults.set(order, forKey: "treeOrder")
    let recent = defaults.stringArray(forKey: "recentNotes") ?? []
    defaults.set(
      recent.map { key in
        key == oldKey || key.hasPrefix(oldKey + "/") ? newKey + key.dropFirst(oldKey.count) : key
      }, forKey: "recentNotes")
    let collapsed = defaults.stringArray(forKey: "collapsedFolders") ?? []
    defaults.set(
      collapsed.map { key in
        key == oldKey || key.hasPrefix(oldKey + "/") ? newKey + key.dropFirst(oldKey.count) : key
      }, forKey: "collapsedFolders")
    rebuildRecentMenu()
  }
  func menuWillOpen(_ menu: NSMenu) {
    menuTracking = true
    hoverTimer?.invalidate()
    hoverTimer = nil
    pendingVisibility = nil
  }
  func menuDidClose(_ menu: NSMenu) { menuTracking = false }
  func menuNeedsUpdate(_ menu: NSMenu) {
    if menu === recentButton.menu {
      rebuildRecentMenu()
      return
    }
    menu.removeAllItems()
    let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
    let selected = row >= 0 ? outline.item(atRow: row) as? NoteNode : nil
    let contextNode = keyboardContextURL.map { url in
      findNode(url, in: allNotes)
        ?? NoteNode(
          url: url,
          isFolder: (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
    }
    guard let node = contextNode ?? selected else {
      return
    }
    let context = ["path": relativePath(node.url)]
    func add(_ title: String, _ action: Selector, _ symbol: String? = nil) {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      item.representedObject = context
      if let symbol = symbol {
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
      }
      menu.addItem(item)
    }
    let heading = NSMenuItem(
      title: node.isFolder
        ? node.url.lastPathComponent : node.url.deletingPathExtension().lastPathComponent,
      action: nil, keyEquivalent: "")
    heading.isEnabled = false
    menu.addItem(heading)
    add(
      node.isFolder
        ? (outline.isItemExpanded(node) ? "Свернуть папку" : "Раскрыть папку") : "Открыть заметку",
      #selector(contextOpen(_:)), node.isFolder ? "folder" : "doc.text")
    add("Показать в Finder", #selector(contextReveal(_:)), "arrow.up.forward.app")
    menu.addItem(.separator())
    if node.isFolder {
      add("Новая заметка в этой папке", #selector(contextNewNote(_:)), "square.and.pencil")
      add("Новая подпапка…", #selector(contextNewFolder(_:)), "folder.badge.plus")
      menu.addItem(.separator())
    }
    if !node.isFolder {
      add("Напомнить…", #selector(contextReminder(_:)), "bell")
      if reminderRecords[relativePath(node.url)] != nil {
        add("Отменить напоминание", #selector(contextCancelReminder(_:)), "bell.slash")
      }
      menu.addItem(.separator())
    }
    add("Переименовать…", #selector(contextRename(_:)), "pencil")
    add("Создать копию", #selector(contextDuplicate(_:)), "plus.square.on.square")
    let move = NSMenuItem(title: "Переместить в…", action: nil, keyEquivalent: "")
    move.image = NSImage(
      systemSymbolName: "folder.badge.arrow.forward", accessibilityDescription: nil)
    let destinations = NSMenu()
    func folders(_ nodes: [NoteNode]) -> [URL] {
      nodes.filter { $0.isFolder }.flatMap { [$0.url] + folders($0.children) }
    }
    let targets = [root] + folders(allNotes)
    for target in targets
    where target != node.url && !target.path.hasPrefix(node.url.path + "/")
      && target != node.url.deletingLastPathComponent()
    {
      let item = NSMenuItem(
        title: target == root ? "SimpleNotes" : relativePath(target),
        action: #selector(contextMove(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = [
        "path": relativePath(node.url), "destination": relativePath(target),
      ]
      destinations.addItem(item)
    }
    move.submenu = destinations
    move.isEnabled = !destinations.items.isEmpty
    menu.addItem(move)
    let colorItem = NSMenuItem(title: "Цвет", action: nil, keyEquivalent: "")
    colorItem.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
    let colors = NSMenu()
    for (name, value, color) in colorPalette {
      let item = NSMenuItem(title: name, action: #selector(setItemColor(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = ["path": relativePath(node.url), "color": value]
      item.state = itemColors[relativePath(node.url)] == value ? .on : .off
      item.image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
        color.setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
        return true
      }
      colors.addItem(item)
    }
    colors.addItem(.separator())
    let reset = NSMenuItem(
      title: "Без цвета", action: #selector(setItemColor(_:)), keyEquivalent: "")
    reset.target = self
    reset.representedObject = ["path": relativePath(node.url), "color": ""]
    reset.state = itemColors[relativePath(node.url)] == nil ? .on : .off
    colors.addItem(reset)
    colorItem.submenu = colors
    menu.addItem(colorItem)
    menu.addItem(.separator())
    add("Переместить в Корзину…", #selector(contextTrash(_:)), "trash")
  }
  func contextURL(_ sender: NSMenuItem) -> URL? {
    guard let info = sender.representedObject as? [String: String], let path = info["path"] else {
      return nil
    }
    let url = root.appendingPathComponent(path).standardizedFileURL
    guard url.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: url.path)
    else { return nil }
    return url
  }
  func preparedContextURL(_ sender: NSMenuItem) -> URL? {
    guard let source = contextURL(sender) else { return nil }
    let wasCurrent = source == currentURL
    let containsCurrent = currentURL.map { $0.path.hasPrefix(source.path + "/") } ?? false
    if wasCurrent || containsCurrent {
      guard canLeaveNote() else { return nil }
      return wasCurrent ? currentURL : source
    }
    return source
  }
  func validEntryName(_ name: String) -> Bool {
    !name.isEmpty && !name.hasPrefix(".") && !name.lowercased().hasSuffix(".app")
      && name.rangeOfCharacter(from: CharacterSet(charactersIn: "/:\n\r\0")) == nil
      && name.utf8.count <= 200
  }
  func askName(title: String, initial: String) -> String? {
    let alert = NSAlert()
    alert.messageText = title
    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 330, height: 26))
    input.stringValue = initial
    alert.accessoryView = input
    alert.addButton(withTitle: "Сохранить")
    alert.addButton(withTitle: "Отмена")
    alert.window.initialFirstResponder = input
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard validEntryName(name) else {
      showError(
        "Сократи название и убери слеши, двоеточия и переносы строк. Оно не должно начинаться с точки или заканчиваться на .app."
      )
      return nil
    }
    return name
  }
  @objc func contextOpen(_ sender: NSMenuItem) {
    guard let url = contextURL(sender) else { return }
    if let node = findNode(url, in: tree), node.isFolder {
      if outline.isItemExpanded(node) {
        outline.collapseItem(node)
      } else {
        outline.expandItem(node)
      }
    } else {
      openNote(url)
    }
  }
  @objc func contextReveal(_ sender: NSMenuItem) {
    guard let url = contextURL(sender) else { return }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
  @objc func contextNewNote(_ sender: NSMenuItem) {
    guard let folder = contextURL(sender) else { return }
    newNote()
    guard !dirty, currentURL == nil else { return }
    refreshTopics(select: relativePath(folder))
    persistDraft()
    window.makeFirstResponder(titleField)
  }
  @objc func contextNewFolder(_ sender: NSMenuItem) {
    guard let parent = contextURL(sender), let name = askName(title: "Новая подпапка", initial: "")
    else { return }
    let target = parent.appendingPathComponent(name)
    guard !FileManager.default.fileExists(atPath: target.path) else {
      showError("Папка с таким названием уже существует.")
      return
    }
    do {
      try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
      refreshAfterFileOperation()
    } catch { showError(error.localizedDescription) }
  }
  @objc func contextRename(_ sender: NSMenuItem) {
    guard let source = preparedContextURL(sender) else { return }
    let isFolder = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    let initial =
      isFolder ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
    guard
      let name = askName(title: isFolder ? "Название папки" : "Название заметки", initial: initial)
    else { return }
    let filename = isFolder ? name : name + "." + source.pathExtension
    let target = source.deletingLastPathComponent().appendingPathComponent(filename)
    do { try moveEntry(source, to: target, newTitle: isFolder ? nil : name) } catch {
      showError(error.localizedDescription)
    }
  }
  @objc func contextMove(_ sender: NSMenuItem) {
    guard let source = preparedContextURL(sender),
      let info = sender.representedObject as? [String: String], let path = info["destination"]
    else { return }
    let parent = path.isEmpty ? root : root.appendingPathComponent(path)
    do { try moveEntry(source, to: parent.appendingPathComponent(source.lastPathComponent)) } catch
    { showError(error.localizedDescription) }
  }
  func contentWithTitle(_ title: String, content: String) -> String {
    var lines = content.components(separatedBy: "\n")
    if NoteMetadata.hasHeader(lines) { lines[0] = title }
    return lines.joined(separator: "\n")
  }
  func moveEntry(_ source: URL, to target: URL, newTitle: String? = nil) throws {
    guard source != target else { return }
    guard target.path.hasPrefix(root.path + "/"), !target.path.hasPrefix(source.path + "/") else {
      throw CocoaError(.fileWriteInvalidFileName)
    }
    let targetExists = FileManager.default.fileExists(atPath: target.path)
    if targetExists {
      let sourceID =
        try source.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        as? NSObject
      let targetID =
        try target.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        as? NSObject
      guard let sourceID = sourceID, let targetID = targetID, sourceID.isEqual(targetID) else {
        throw CocoaError(.fileWriteFileExists)
      }
    }
    let renamedContent: String?
    if let title = newTitle {
      renamedContent = contentWithTitle(
        title, content: try String(contentsOf: source, encoding: .utf8))
    } else {
      renamedContent = nil
    }
    if targetExists {
      let temporary = source.deletingLastPathComponent().appendingPathComponent(
        ".rename-" + UUID().uuidString)
      try FileManager.default.moveItem(at: source, to: temporary)
      do { try FileManager.default.moveItem(at: temporary, to: target) } catch {
        try FileManager.default.moveItem(at: temporary, to: source)
        throw error
      }
    } else {
      try FileManager.default.moveItem(at: source, to: target)
    }
    do {
      if let content = renamedContent { try Data(content.utf8).write(to: target, options: .atomic) }
    } catch {
      try FileManager.default.moveItem(at: target, to: source)
      throw error
    }
    remapColors(from: source, to: target)
    if let opened = currentURL, opened == source || opened.path.hasPrefix(source.path + "/") {
      let suffix = String(opened.path.dropFirst(source.path.count))
      currentURL = URL(fileURLWithPath: target.path + suffix)
      let openedURL = currentURL!
      let content = try String(contentsOf: openedURL, encoding: .utf8)
      loadNote(content, url: openedURL)
      dirty = false
      persistDraft()
      if mode.selectedSegment == 1 { renderMarkdown() }
    } else {
      let selected = selectedTopicPath
      if selected == relativePath(source) || selected.hasPrefix(relativePath(source) + "/") {
        refreshTopics(select: relativePath(target) + selected.dropFirst(relativePath(source).count))
        persistDraft()
      }
    }
    refreshAfterFileOperation()
    status.stringValue = "Сохранено — " + target.deletingPathExtension().lastPathComponent
  }
  @objc func contextDuplicate(_ sender: NSMenuItem) {
    guard let source = preparedContextURL(sender) else { return }
    do {
      let copy = try duplicateEntry(source)
      refreshAfterFileOperation()
      status.stringValue = "Создана копия — " + copy.deletingPathExtension().lastPathComponent
    } catch { showError(error.localizedDescription) }
  }
  func duplicateEntry(_ source: URL) throws -> URL {
    let isFolder = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    let stem =
      isFolder ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
    var number = 1
    var target: URL
    while true {
      let name = stem + " — копия" + (number == 1 ? "" : " (\(number))")
      target = source.deletingLastPathComponent().appendingPathComponent(
        isFolder ? name : name + "." + source.pathExtension)
      do {
        try FileManager.default.copyItem(at: source, to: target)
        break
      } catch let error as NSError
        where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError
      { number += 1 }
    }
    do {
      if !isFolder {
        let content = try String(contentsOf: target, encoding: .utf8)
        let title = target.deletingPathExtension().lastPathComponent
        try Data(contentWithTitle(title, content: content).utf8).write(to: target, options: .atomic)
      }
    } catch {
      try? FileManager.default.removeItem(at: target)
      throw error
    }
    let sourceKey = relativePath(source)
    let targetKey = relativePath(target)
    var colors = itemColors
    for (key, value) in itemColors where key == sourceKey || key.hasPrefix(sourceKey + "/") {
      colors[targetKey + key.dropFirst(sourceKey.count)] = value
    }
    defaults.set(colors, forKey: "itemColors")
    var order = customOrder
    for (key, value) in customOrder where key == sourceKey || key.hasPrefix(sourceKey + "/") {
      order[targetKey + key.dropFirst(sourceKey.count)] = value
    }
    let parentKey = relativePath(source.deletingLastPathComponent())
    var siblings =
      (try orderedNoteEntries(
        in: source.deletingLastPathComponent(), root: root, order: customOrder)).map {
        $0.lastPathComponent
      }.filter { $0 != target.lastPathComponent }
    let index = siblings.firstIndex(of: source.lastPathComponent).map { $0 + 1 } ?? siblings.count
    siblings.insert(target.lastPathComponent, at: index)
    order[parentKey] = siblings
    defaults.set(order, forKey: "treeOrder")
    return target
  }
  @objc func contextTrash(_ sender: NSMenuItem) {
    guard let source = preparedContextURL(sender) else { return }
    let alert = NSAlert()
    alert.messageText = "Переместить «\(source.lastPathComponent)» в Корзину?"
    let isFolder = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    alert.informativeText =
      isFolder
      ? "Папка будет перемещена вместе со всеми записями. Восстановить их можно из Корзины."
      : "Заметку можно будет восстановить из Корзины."
    alert.addButton(withTitle: "В Корзину")
    alert.addButton(withTitle: "Отмена")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    do {
      try FileManager.default.trashItem(at: source, resultingItemURL: nil)
      removeEntryPreferences(source)
      if let opened = currentURL, opened == source || opened.path.hasPrefix(source.path + "/") {
        dirty = false
        newNote()
      }
      refreshAfterFileOperation()
      persistDraft()
      status.stringValue = "Перемещено в Корзину"
    } catch { showError(error.localizedDescription) }
  }
  func removeEntryPreferences(_ source: URL) {
    cancelReminders(in: source)
    let path = relativePath(source)
    func belongs(_ key: String) -> Bool { key == path || key.hasPrefix(path + "/") }
    defaults.set(itemColors.filter { !belongs($0.key) }, forKey: "itemColors")
    defaults.set(
      (defaults.stringArray(forKey: "recentNotes") ?? []).filter { !belongs($0) },
      forKey: "recentNotes")
    defaults.set(
      (defaults.stringArray(forKey: "collapsedFolders") ?? []).filter { !belongs($0) },
      forKey: "collapsedFolders")
    var order = customOrder.filter { !belongs($0.key) }
    let parent = relativePath(source.deletingLastPathComponent())
    order[parent] = order[parent]?.filter { $0 != source.lastPathComponent }
    defaults.set(order, forKey: "treeOrder")
    rebuildRecentMenu()
  }
  func refreshAfterFileOperation() {
    refreshTopics(select: selectedTopicPath)
    refreshTree()
  }
  @objc func setItemColor(_ sender: NSMenuItem) {
    guard let info = sender.representedObject as? [String: String], let path = info["path"] else {
      return
    }
    var colors = itemColors
    colors[path] = info["color"] == "" ? nil : info["color"]
    defaults.set(colors, forKey: "itemColors")
    applySearch()
  }
  func canLeaveNote() -> Bool {
    guard dirty else { return true }
    let alert = NSAlert()
    alert.messageText = "Сохранить изменения?"
    alert.addButton(withTitle: "Сохранить")
    alert.addButton(withTitle: "Отмена")
    alert.addButton(withTitle: "Не сохранять")
    switch alert.runModal() {
    case .alertFirstButtonReturn: return saveCurrent()
    case .alertThirdButtonReturn: return true
    default: return false
    }
  }
  @objc func openSelection() {
    guard !loadingTree, outline.selectedRow >= 0,
      let node = outline.item(atRow: outline.selectedRow) as? NoteNode
    else { return }
    if node.isFolder {
      if outline.isItemExpanded(node) {
        outline.collapseItem(node)
      } else {
        outline.expandItem(node)
      }
      return
    }
    openNote(node.url)
  }
  func openNote(_ url: URL) {
    if url == currentURL {
      recordRecent(url)
      revealSearchMatch()
      return
    }
    guard canLeaveNote() else { return }
    do {
      let content = try String(contentsOf: url, encoding: .utf8)
      loadNote(content, url: url)
      recordRecent(url)
      dirty = false
      persistDraft()
      if mode.selectedSegment == 1 { renderMarkdown() }
      revealSearchMatch()
    } catch { showError(error.localizedDescription) }
  }
  func revealSearchMatch() {
    guard !searchQuery.isEmpty else { return }
    let range = (editor.string as NSString).range(
      of: searchQuery, options: [.caseInsensitive, .diacriticInsensitive])
    guard range.location != NSNotFound else { return }
    mode.selectedSegment = 0
    changeMode()
    editor.setSelectedRange(range)
    editor.scrollRangeToVisible(range)
    editor.showFindIndicator(for: range)
  }
  func loadNote(_ content: String, url: URL) {
    let lines = content.components(separatedBy: "\n")
    quickAutomaticTitle = false
    let hasHeader = NoteMetadata.hasHeader(lines)
    titleField.stringValue = hasHeader ? lines[0] : url.deletingPathExtension().lastPathComponent
    editor.string =
      hasHeader ? lines.dropFirst(lines[3].isEmpty ? 4 : 3).joined(separator: "\n") : content
    noteDate = hasHeader ? lines[1] : ""
    currentURL = url
    loadedContent = content
    refreshTopics(
      select: String(url.deletingLastPathComponent().path.dropFirst(root.path.count + 1)))
    editor.undoManager?.removeAllActions()
    status.stringValue =
      !showDates || noteDate.isEmpty
      ? "\(url.lastPathComponent)"
      : "\(noteDate)"
  }
  func restoreEditingState() {
    guard let path = defaults.string(forKey: "draftPath") else {
      dirty = !titleField.stringValue.isEmpty || !editor.string.isEmpty
      return
    }
    currentURL = URL(fileURLWithPath: path)
    loadedContent = defaults.string(forKey: "draftBaseline")
    noteDate = defaults.string(forKey: "draftDate") ?? ""
    dirty = defaults.bool(forKey: "draftDirty")
    if let url = currentURL, FileManager.default.fileExists(atPath: url.path) { recordRecent(url) }
  }
  @objc func newNote() {
    guard canLeaveNote() else { return }
    resetNoteForWriting()
  }

  func resetNoteForWriting() {
    quickAutomaticTitle = false
    currentURL = nil
    loadedContent = nil
    noteDate = ""
    dirty = false
    titleField.stringValue = ""
    editor.string = ""
    editor.undoManager?.removeAllActions()
    mode.selectedSegment = 0
    changeMode()
    persistDraft()
    status.stringValue = "Новая заметка"
    window.makeFirstResponder(titleField)
  }
  @objc func changeMode() {
    let isPreview = mode.selectedSegment == 1
    editorScroll.isHidden = isPreview
    previewContainer.isHidden = !isPreview
    if isPreview { renderMarkdown() }
  }
  func showError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "SimpleNotes"
    alert.informativeText = message
    alert.runModal()
  }
}
