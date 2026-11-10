import Cocoa

extension NotesApp {
  // Keep the drop destination current while the filesystem index refreshes in the background.
  @discardableResult func applyMovedSnapshot(from source: URL, to target: URL) -> Bool {
    let source = source.resolvingSymlinksInPath()
    let target = target.resolvingSymlinksInPath()
    guard let moved = findNode(source, in: allNotes) else { return false }
    let parent = target.deletingLastPathComponent()
    guard parent.path == root.path || findNode(parent, in: allNotes)?.isFolder == true else { return false }
    func rebased(_ node: NoteNode) -> NoteNode {
      let suffix = String(node.url.path.dropFirst(moved.url.path.count))
      let copy = NoteNode(
        url: URL(fileURLWithPath: target.path + suffix, isDirectory: node.isFolder),
        children: node.children.map(rebased), isFolder: node.isFolder)
      copy.searchBody = node.searchBody
      return copy
    }
    let movedCopy = rebased(moved)
    let order = customOrder
    func updated(_ nodes: [NoteNode], in directory: URL) -> [NoteNode] {
      var result = nodes.filter { $0.url.resolvingSymlinksInPath().path != source.path }.map { node -> NoteNode in
        guard node.isFolder else { return node }
        return NoteNode(
          url: node.url, children: updated(node.children, in: node.url), isFolder: true)
      }
      if directory.resolvingSymlinksInPath().path == parent.path { result.append(movedCopy) }
      let names = order[relativePath(directory)] ?? []
      let positions = Dictionary(
        names.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
      return result.sorted {
        let first = positions[$0.url.lastPathComponent] ?? Int.max
        let second = positions[$1.url.lastPathComponent] ?? Int.max
        return first == second
          ? $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent)
            == .orderedAscending : first < second
      }
    }
    allNotes = updated(allNotes, in: root)
    applySearch()
    if let node = findNode(target, in: tree) {
      let row = outline.row(forItem: node)
      if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
    }
    return true
  }
}
