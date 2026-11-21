import Cocoa

extension NotesApp {
  @objc func showNoteHistory() {
    guard !saveInProgress else { status.stringValue = "Дождись завершения сохранения…"; return }
    guard let url = currentURL else {
      showError("Сначала сохрани заметку — после этого будет доступна история версий.")
      return
    }
    do {
      let store = NoteVersionHistory(root: root)
      if let baseline = loadedContent {
        try store.record(NoteVersion.read(baseline, url: url), for: url)
      }
      let current = NoteVersion(title: titleField.stringValue, body: editor.string)
      let controller = NoteHistoryController(versions: try store.versions(for: url), current: current) { [weak self] version in
        guard let self = self, self.currentURL == url, !self.saveInProgress else {
          throw NSError(domain: "SimpleNotes.History", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Заметка уже изменилась. Открой историю ещё раз."])
        }
        let before = NoteVersion(title: self.titleField.stringValue, body: self.editor.string)
        let restored = try store.prepareRestore(version, current: before, note: url)
        self.titleField.stringValue = restored.title
        self.editor.string = restored.body
        self.dirty = true
        self.editor.undoManager?.removeAllActions()
        self.persistDraft()
        self.updateNoteFind(reset: true)
        // Keep the file path; restoring a title must not silently rename the note.
        if !self.saveCurrent(preservingExistingFile: true) {
          self.titleField.stringValue = before.title
          self.editor.string = before.body
          self.dirty = true
          self.persistDraft()
          throw NSError(domain: "SimpleNotes.History", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Не удалось сохранить восстановленную версию. Текущий текст сохранён в истории."])
        }
        if self.mode.selectedSegment == 1 { self.renderMarkdown() }
      }
      historyController = controller
      window.beginSheet(controller.window!)
    } catch { showError(error.localizedDescription) }
  }
}
