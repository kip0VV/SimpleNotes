import Cocoa
import Darwin

struct ExternalNoteStamp: Equatable {
  let modified: Date?
  let changed: Date?
  let size: Int?
  let identity: NSObject?
  init(_ url: URL) throws {
    var freshURL = url
    freshURL.removeAllCachedResourceValues()
    let values = try freshURL.resourceValues(forKeys: [.contentModificationDateKey, .attributeModificationDateKey, .fileSizeKey, .fileResourceIdentifierKey])
    modified = values.contentModificationDate
    changed = values.attributeModificationDate
    size = values.fileSize
    identity = values.fileResourceIdentifier as? NSObject
  }
}

extension NotesApp {
  // Compare the editable fields, not the serialized file (which may include metadata).
  // A title or folder change is also an unsaved edit, even when the body is unchanged.
  func editingMatchesLoadedNote() -> Bool {
    guard let content = loadedContent, let url = currentURL else { return false }
    let lines = content.components(separatedBy: "\n")
    let hasHeader = NoteMetadata.hasHeader(lines)
    let body = hasHeader ? lines.dropFirst(lines[3].isEmpty ? 4 : 3).joined(separator: "\n") : content
    let title = hasHeader ? lines[0] : url.deletingPathExtension().lastPathComponent
    let folder = String(url.deletingLastPathComponent().path.dropFirst(root.path.count + 1))
    return editor.string == body && titleField.stringValue == title && selectedTopicPath == folder
  }

  func startExternalNoteUpdates() {
    externalUpdatesEnabled = true
    configureExternalNoteWatchers()
  }

  func configureExternalNoteWatchers(force: Bool = false) {
    guard externalUpdatesEnabled else { return }
    let path = currentURL?.path
    guard force || externalWatchPath != path else { return }
    externalWatchWork?.cancel()
    externalWatchWork = nil
    externalFileWatch?.cancel()
    externalDirectoryWatch?.cancel()
    externalFileWatch = nil
    externalDirectoryWatch = nil
    externalWatchPath = path
    guard let url = currentURL else { return }
    func watch(_ path: String) -> DispatchSourceFileSystemObject? {
      let descriptor = open(path, O_EVTONLY)
      guard descriptor >= 0 else { return nil }
      let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
        eventMask: [.write, .extend, .rename, .delete, .revoke], queue: .main)
      source.setEventHandler { [weak self] in self?.scheduleExternalNoteRefresh() }
      source.setCancelHandler { close(descriptor) }
      source.resume()
      return source
    }
    // Watch the directory too: atomic saves replace the file's inode.
    externalFileWatch = watch(url.path)
    externalDirectoryWatch = watch(url.deletingLastPathComponent().path)
  }

  func scheduleExternalNoteRefresh() {
    // Coalesce events, but do not postpone forever during continuous external saves.
    guard externalWatchWork == nil else { return }
    let path = currentURL?.path
    let work = DispatchWorkItem { [weak self] in
      guard let self = self, self.currentURL?.path == path else { return }
      self.externalWatchWork = nil
      self.configureExternalNoteWatchers(force: true)
      self.refreshOpenNoteFromDisk()
    }
    externalWatchWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
  }

  func windowDidBecomeKey(_ notification: Notification) {
    refreshOpenNoteFromDisk(force: true)
  }

  func refreshOpenNoteFromDisk(force: Bool = false) {
    if dirty && editingMatchesLoadedNote() {
      dirty = false
    }
    
    guard !dirty, !quickMode, let url = currentURL, let baseline = loadedContent else { return }
    if externalReadInFlight { externalReadPending = true; return }
    externalReadInFlight = true
    let previousStamp = externalObservedPath == url.path ? externalObservedStamp : nil
    externalReadQueue.async { [weak self] in
      let result: (ExternalNoteStamp, String?)? = {
        guard let before = try? ExternalNoteStamp(url) else { return nil }
        if !force && before == previousStamp { return (before, nil) }
        guard let content = try? String(contentsOf: url, encoding: .utf8),
          let after = try? ExternalNoteStamp(url), before == after else { return nil }
        return (after, content)
      }()
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.externalReadInFlight = false
        defer {
          if self.externalReadPending {
            self.externalReadPending = false
            self.refreshOpenNoteFromDisk(force: true)
          }
        }
        
        guard self.currentURL?.path == url.path, self.loadedContent == baseline else { return }
        if self.dirty && self.editingMatchesLoadedNote() {
          self.dirty = false
        }
        
        guard !self.dirty, !self.quickMode, self.currentURL?.path == url.path,
          self.loadedContent == baseline, let (stamp, content) = result else { return }
        self.externalObservedPath = url.path
        self.externalObservedStamp = stamp
        guard let content = content, content != baseline else { return }
        let selection = self.editor.selectedRange()
        let origin = self.editorScroll?.contentView.bounds.origin
        self.loadNote(content, url: url)
        self.dirty = false
        let length = (self.editor.string as NSString).length
        let start = min(selection.location, length)
        self.editor.setSelectedRange(NSRange(location: start, length: min(selection.length, length - start)))
        if let origin = origin, let scroll = self.editorScroll {
          scroll.contentView.scroll(to: origin)
          scroll.reflectScrolledClipView(scroll.contentView)
        }
        self.persistDraft()
        self.status.stringValue = "Обновлено из файла"
        if self.mode.selectedSegment == 1 { self.renderMarkdown() }
        self.noteBodyCache.removeValue(forKey: url)
        self.refreshTree()
      }
    }
  }
}
