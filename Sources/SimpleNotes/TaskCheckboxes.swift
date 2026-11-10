import Cocoa
import WebKit

final class TaskToggleHandler: NSObject, WKScriptMessageHandler {
  weak var owner: NotesApp?
  init(owner: NotesApp) { self.owner = owner }
  func userContentController(
    _ controller: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    guard let owner = owner, message.webView === owner.preview, message.frameInfo.isMainFrame,
      let body = message.body as? [String: Any], let line = body["line"] as? Int,
      let checked = body["checked"] as? Bool, body["revision"] as? String == owner.previewRevision,
      owner.mode.selectedSegment == 1
    else { return }
    owner.toggleMarkdownTask(line: line, checked: checked)
  }
}

extension NotesApp {
  static let taskMarker = try! NSRegularExpression(
    pattern: #"^(?:\s*>\s*)*\s*(?:[-+*]|\d+[.)])\s+\[([ xX])\](?=\s|$)"#)

  static func taskMarkerRange(in text: String, line: Int) -> NSRange? {
    guard line >= 0 else { return nil }
    let source = text as NSString
    let breaks = CharacterSet(charactersIn: "\r\n")
    var offset = 0
    for _ in 0..<line {
      let end = source.rangeOfCharacter(
        from: breaks, range: NSRange(location: offset, length: source.length - offset))
      guard end.location != NSNotFound else { return nil }
      offset = NSMaxRange(end)
      if source.character(at: end.location) == 13, offset < source.length,
        source.character(at: offset) == 10
      {
        offset += 1
      }
    }
    guard offset < source.length else { return nil }
    let end = source.rangeOfCharacter(
      from: breaks, range: NSRange(location: offset, length: source.length - offset))
    let lineRange = NSRange(
      location: offset, length: (end.location == NSNotFound ? source.length : end.location) - offset
    )
    let content = source.substring(with: lineRange)
    guard
      let match = taskMarker.firstMatch(
        in: content,
        range: NSRange(location: 0, length: (content as NSString).length))
    else { return nil }
    return NSRange(location: offset + match.range(at: 1).location, length: 1)
  }

  func toggleMarkdownTask(line: Int, checked: Bool) {
    guard let marker = Self.taskMarkerRange(in: editor.string, line: line) else { return }
    let replacement = checked ? "x" : " "
    if (editor.string as NSString).substring(with: marker).lowercased() == replacement { return }
    let selection = editor.selectedRange()
    let wasDirty = dirty
    updatingTask = true
    defer { updatingTask = false }
    editor.insertText(
      replacement, replacementRange: marker)
    editor.setSelectedRange(selection)
    editor.undoManager?.setActionName("Отметить задачу")
    if !wasDirty && currentURL != nil {
      _ = saveCurrent(preservingExistingFile: true)
    } else {
      renderMarkdown()
      status.stringValue = "Задача изменена · сохрани заметку"
    }
  }
}
