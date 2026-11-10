import Cocoa

struct CachedNoteBody {
  let modified: Date?
  let size: Int?
  let changed: Date?
  let identity: NSObject?
  let generation: NSObject?
  let body: String
}

extension NotesApp {
  func folderNodes(in folder: URL) throws -> [NoteNode] {
    try orderedNoteEntries(in: folder, root: root, order: customOrder)
      .compactMap { url in
        let attributes = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard attributes.isDirectory == true, attributes.isSymbolicLink != true,
          url.pathExtension.lowercased() != "app"
        else { return nil }
        return NoteNode(url: url, children: try folderNodes(in: url), isFolder: true)
      }
  }

}

struct NoteIndexScanner {
  let root: URL
  let order: [String: [String]]
  var cache: [URL: CachedNoteBody]
  var visited: Set<URL> = []

  mutating func scan() throws -> [NoteNode] {
    visited.removeAll(keepingCapacity: true)
    let result = try nodes(in: root)
    cache = cache.filter { visited.contains($0.key) }
    return result
  }
  mutating func nodes(in folder: URL) throws -> [NoteNode] {
    let entries = try orderedNoteEntries(in: folder, root: root, order: order)
    return try entries.compactMap { url in
      let values = try url.resourceValues(forKeys: [
        .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey,
        .attributeModificationDateKey, .fileResourceIdentifierKey, .generationIdentifierKey,
      ])
      if values.isDirectory == true {
        return NoteNode(url: url, children: try nodes(in: url), isFolder: true)
      }
      visited.insert(url)
      let node = NoteNode(url: url)
      let identity = values.fileResourceIdentifier as? NSObject
      let generation = values.generationIdentifier as? NSObject
      if values.contentModificationDate != nil, values.fileSize != nil, identity != nil,
        generation != nil || values.attributeModificationDate != nil,
        let cached = cache[url], cached.modified == values.contentModificationDate,
        cached.size == values.fileSize, cached.identity == identity,
        cached.generation == generation,
        generation != nil || cached.changed == values.attributeModificationDate
      {
        node.searchBody = cached.body
      } else if let content = try? String(contentsOf: url, encoding: .utf8) {
        let lines = content.components(separatedBy: "\n")
        node.searchBody =
          NoteMetadata.hasHeader(lines)
          ? lines.dropFirst(lines[3].isEmpty ? 4 : 3).joined(separator: "\n") : content
        cache[url] = CachedNoteBody(
          modified: values.contentModificationDate,
          size: values.fileSize, changed: values.attributeModificationDate, identity: identity,
          generation: generation, body: node.searchBody)
      }
      return node
    }
  }
}

func orderedNoteEntries(in folder: URL, root: URL, order: [String: [String]]) throws -> [URL] {
  let entries = try FileManager.default.contentsOfDirectory(
    at: folder,
    includingPropertiesForKeys: [
      .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey,
      .attributeModificationDateKey, .fileResourceIdentifierKey, .generationIdentifierKey,
    ],
    options: [.skipsHiddenFiles])
  let saved = order[String(folder.path.dropFirst(root.path.count + 1))] ?? []
  let positions = Dictionary(
    saved.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
  return try entries.filter { url in
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    return values.isSymbolicLink != true && url.pathExtension.lowercased() != "app"
      && (values.isDirectory == true
        || ["txt", "md", "markdown"].contains(url.pathExtension.lowercased()))
  }.map { url in
    // Directory enumeration can expand /var into /private/var. Keep every entry
    // relative to the selected library so topic paths and preferences stay consistent.
    folder.appendingPathComponent(
      url.lastPathComponent,
      isDirectory: (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
  }.sorted {
    let first = positions[$0.lastPathComponent] ?? Int.max
    let second = positions[$1.lastPathComponent] ?? Int.max
    return first == second
      ? $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
      : first < second
  }
}
