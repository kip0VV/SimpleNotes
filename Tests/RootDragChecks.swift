import Cocoa

private final class RootNoteDrag: NSObject, NSDraggingInfo {
  let draggingPasteboard = NSPasteboard.withUniqueName()
  let draggingSource: Any?
  let draggingDestinationWindow: NSWindow?
  var draggingLocation = NSPoint.zero
  let draggingSourceOperationMask: NSDragOperation = .move
  let draggedImageLocation = NSPoint.zero
  let draggedImage: NSImage? = nil
  let draggingSequenceNumber = 1
  var draggingFormation: NSDraggingFormation = .none
  var animatesToDestination = false
  var numberOfValidItemsForDrop = 1
  let springLoadingHighlight: NSSpringLoadingHighlight = .none
  init(notes: NotesApp, source: URL) {
    draggingSource = notes.outline
    draggingDestinationWindow = notes.window
    super.init()
    draggingPasteboard.setString(source.path, forType: notes.noteDragType)
  }
  func slideDraggedImage(to screenPoint: NSPoint) {}
  override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
  func resetSpringLoading() {}
  func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions = [], for view: NSView?,
    classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
    using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

func runRootDragChecks(notes parentNotes: NotesApp, fixture: URL) throws {
  let notes = NotesApp()
  notes.window = parentNotes.window
  let savedOrder = notes.defaults.dictionary(forKey: "treeOrder")
  defer {
    notes.outline.removeFromSuperview()
    if let savedOrder = savedOrder { notes.defaults.set(savedOrder, forKey: "treeOrder") }
    else { notes.defaults.removeObject(forKey: "treeOrder") }
  }
  let library = fixture.appendingPathComponent("root-drag", isDirectory: true).resolvingSymlinksInPath()
  try FileManager.default.createDirectory(at: library.appendingPathComponent("A-folder"), withIntermediateDirectories: true)
  let source = library.appendingPathComponent("Z-note.md")
  try "Keep this content".write(to: source, atomically: true, encoding: .utf8)
  notes.root = library
  notes.indexedRoot = library
  notes.currentURL = nil
  notes.dirty = false
  notes.searchField.stringValue = ""
  notes.defaults.removeObject(forKey: "treeOrder")
  var scanner = NoteIndexScanner(root: library, order: [:], cache: [:])
  notes.allNotes = try scanner.scan()
  if notes.outline.tableColumns.isEmpty {
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("notes"))
    notes.outline.addTableColumn(column)
    notes.outline.outlineTableColumn = column
  }
  notes.outline.dataSource = notes
  notes.outline.delegate = notes
  notes.outline.frame = NSRect(x: 0, y: 0, width: 280, height: 400)
  notes.window.contentView!.addSubview(notes.outline)
  notes.applySearch()
  let info = RootNoteDrag(notes: notes, source: source)
  info.draggingLocation = notes.outline.convert(NSPoint(x: 40, y: notes.outline.rect(ofRow: 0).minY), to: nil)
  precondition(notes.outlineView(notes.outline, validateDrop: info, proposedItem: nil,
                                proposedChildIndex: 0) == .move)
  precondition(notes.outlineView(notes.outline, acceptDrop: info, item: nil, childIndex: 0),
               "Root files must allow reordering without Option")
  let expected = ["Z-note.md", "A-folder"]
  precondition(notes.customOrder[""] == expected)
  precondition(notes.allNotes.map { $0.url.lastPathComponent } == expected)
  let deadline = Date().addingTimeInterval(5)
  while notes.indexQueue.operationCount > 0 && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
  }
  RunLoop.current.run(until: Date().addingTimeInterval(0.1))
  precondition(notes.allNotes.map { $0.url.lastPathComponent } == expected,
               "Async refresh preserves new root order")
  precondition(try! String(contentsOf: source, encoding: .utf8) == "Keep this content")
  print("Root-file drop checks passed — acceptance, persisted order, refresh, unchanged content")
}
