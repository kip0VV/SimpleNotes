import Cocoa

extension NotesApp {
  static let libraryKeys = ["draftTitle", "draftBody", "draftPath", "draftBaseline", "draftDate",
    "draftDirty", "recentNotes", "treeOrder", "itemColors", "collapsedFolders", "selectedTopic", "reminders"]

  func storeLibraryState(at directory: URL) {
    let state = Dictionary(uniqueKeysWithValues: Self.libraryKeys.compactMap { key in
      defaults.object(forKey: key).map { (key, $0) }
    })
    var libraries = defaults.dictionary(forKey: "libraryStates") ?? [:]
    libraries[directory.standardizedFileURL.resolvingSymlinksInPath().path] = state
    defaults.set(libraries, forKey: "libraryStates")
  }

  func restoreLibraryState(at directory: URL) {
    let state = (defaults.dictionary(forKey: "libraryStates")?[directory.standardizedFileURL.resolvingSymlinksInPath().path] as? [String: Any]) ?? [:]
    for key in Self.libraryKeys {
      if let value = state[key] { defaults.set(value, forKey: key) }
      else { defaults.removeObject(forKey: key) }
    }
  }
}
