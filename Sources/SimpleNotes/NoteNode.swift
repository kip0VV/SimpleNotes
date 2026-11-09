import Cocoa

final class NoteNode: NSObject {
  let url: URL
  let children: [NoteNode]
  let isFolder: Bool
  let noteCount: Int
  var searchBody = ""
  var snippet = ""
  init(url: URL, children: [NoteNode] = [], isFolder: Bool = false, count: Int? = nil) {
    self.url = url
    self.children = children
    self.isFolder = isFolder
    self.noteCount = count ?? (isFolder ? children.reduce(0) { $0 + $1.noteCount } : 1)
  }
}
