import Cocoa
import WebKit
import PDFKit

func check(file: StaticString = #file, line: UInt = #line, _ body: () throws -> Bool) rethrows { let result = try body(); precondition(result, file: file, line: line) }
setbuf(stdout, nil)
let application = NSApplication.shared
let manager = FileManager.default
let fixture = manager.temporaryDirectory.appendingPathComponent("SimpleNotes-features-" + UUID().uuidString)
try manager.createDirectory(at: fixture, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: fixture) }
let note = fixture.appendingPathComponent("Заметка.md")
let store = NoteVersionHistory(root: fixture)
let first = NoteVersion(title: "Заметка", body: "Первый текст\nОбщий текст", timestamp: Date(timeIntervalSince1970: 10))
let second = NoteVersion(title: "Заметка", body: "Новый текст\nОбщий текст", timestamp: Date(timeIntervalSince1970: 20))
try check { try store.versions(for: note).isEmpty }
let created = try store.record(first, for: note)
precondition(created)
let duplicate = try store.record(first, for: note)
precondition(!duplicate)
try store.record(second, for: note)
let reopened = try NoteVersionHistory(root: fixture).versions(for: note)
precondition(reopened == [first, second], "Versions and timestamps must persist across restarts")
let diff = NoteVersionDiff.lines(from: first.body, to: second.body)
precondition(diff == [NoteDiffLine(kind: .removed, text: "Первый текст"),
  NoteDiffLine(kind: .added, text: "Новый текст"), NoteDiffLine(kind: .unchanged, text: "Общий текст")])
for (old, new) in [("", "text"), ("text", ""), ("a\na\nb\n", "a\nb\na"), ("🙂\n", "🙂"), ("", "")] {
  let changes = NoteVersionDiff.lines(from: old, to: new)
  precondition(changes.filter { $0.kind != .added }.map(\.text).joined(separator: "\n") == old)
  precondition(changes.filter { $0.kind != .removed }.map(\.text).joined(separator: "\n") == new)
}
let unsaved = NoteVersion(title: "Несохранённый заголовок", body: "Несохранённая правка")
let restored = try store.prepareRestore(first, current: unsaved, note: note)
precondition(restored == first)
let withBefore = try store.versions(for: note)
precondition(withBefore.last == unsaved, "Restore must persist unsaved edits before replacing them")
try store.record(NoteVersion(title: restored.title, body: restored.body), for: note)
let back = try store.prepareRestore(unsaved, current: NoteVersion(title: restored.title, body: restored.body), note: note)
precondition(back == unsaved)
try store.record(NoteVersion(title: back.title, body: back.body), for: note)
let afterBack = try store.versions(for: note)
precondition(afterBack.last?.body == unsaved.body)
let other = fixture.appendingPathComponent("other.md")
try check { try store.versions(for: other).isEmpty }
let moved = fixture.appendingPathComponent("Renamed.md")
try store.remap(from: note, to: moved)
try check { try store.versions(for: moved) == afterBack }
try check { try store.versions(for: note).isEmpty }
let folder = fixture.appendingPathComponent("folder")
try store.record(first, for: folder.appendingPathComponent("child.md"))
let newFolder = fixture.appendingPathComponent("new-folder")
try store.remap(from: folder, to: newFolder)
try check { try store.versions(for: newFolder.appendingPathComponent("child.md")) == [first] }
// Corrupt/unwritable history must prevent restore before the caller mutates the editor.
let brokenRoot = fixture.appendingPathComponent("broken-library")
try manager.createDirectory(at: brokenRoot, withIntermediateDirectories: true)
try Data("not a directory".utf8).write(to: brokenRoot.appendingPathComponent(".simplenotes-history"))
var blockedRestore = false
var active = unsaved
do {
  active = try NoteVersionHistory(root: brokenRoot).prepareRestore(first, current: active,
    note: brokenRoot.appendingPathComponent("note.md"))
} catch { blockedRestore = true }
precondition(blockedRestore && active == unsaved)
let largeOld = (1...2100).map { "old \($0)" }.joined(separator: "\n")
let largeNew = (1...2100).map { "new \($0)" }.joined(separator: "\n")
let largeDiff = NoteVersionDiff.lines(from: largeOld, to: largeNew)
precondition(largeDiff.filter { $0.kind != .added }.map(\.text).joined(separator: "\n") == largeOld)
precondition(largeDiff.filter { $0.kind != .removed }.map(\.text).joined(separator: "\n") == largeNew)
let plain = NoteVersion.read("# Heading\n\nBody", url: note)
precondition(plain.title == "Заметка" && plain.body == "# Heading\n\nBody")
let legacy = NoteVersion.read("Title\n21.11.2026 12:00\nТема — Без папки\n\nBody", url: note)
precondition(legacy.title == "Title" && legacy.body == "Body")
var selectedRestore: NoteVersion?
let history = NoteHistoryController(versions: [first, second], current: unsaved) { selectedRestore = $0 }
precondition(history.numberOfRows(in: history.table) == 2)
precondition(history.diff.string.contains("− Новый текст") && history.diff.string.contains("+ Несохранённая правка"))
history.restoreSelected()
precondition(selectedRestore == second)
let empty = NoteHistoryController(versions: [], current: first) { _ in preconditionFailure() }
precondition(!empty.restore.isEnabled)
empty.restoreSelected()
print("PASS: version creation, persistent timestamps, deduplication, diff, reversible restore, rename and History selection")

var selection = PDFNoteSelection(notes: [note, other], preferred: other)
var generated: URL?
try selection.export { generated = $0 }
precondition(generated == other)
selection.selectedIndex = 0
try selection.export { generated = $0 }
precondition(generated == note)
selection.selectedIndex = -1
var invalidRejected = false
do { try selection.export { _ in preconditionFailure("Invalid selection must not generate a PDF") } }
catch { invalidRejected = true }
precondition(invalidRejected)
let resources = URL(fileURLWithPath: CommandLine.arguments[1])
let exportedNote = NoteVersion(title: "PDF Export — Тест", body: """
# Heading

**Bold** and *italic*, [link](https://example.com).

- [x] Completed
- [ ] Pending

| Column | Value |
| --- | --- |
| A | B |

> Quote

```swift
let value = 42
```

$x^2$ and [Definition]{definition}

""" + (1...180).map { "Paragraph \($0): многострочный документ с кириллицей." }.joined(separator: "\n\n"))
let html = try NotePDFExporter.html(note: exportedNote, resources: resources)
precondition(html.contains("markdownit") && html.contains("use(noteMath).use(noteColors)"))
precondition(html.contains("task-mark") && html.contains("@page"))
let escapedHTML = try NotePDFExporter.html(note: NoteVersion(title: "</script>", body: "<script>alert(1)</script>"), resources: resources)
precondition(escapedHTML.contains("\\u003c") && !escapedHTML.contains("<script>alert(1)</script>"))
let exporter = NotePDFExporter()
let destination = fixture.appendingPathComponent("export.pdf")
var done = false
var result: Result<URL, Error>?
exporter.export(note: exportedNote, to: destination, resources: resources) { result = $0; done = true }
let deadline = Date().addingTimeInterval(45)
while !done && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
precondition(done, "PDF generation timed out")
let saved = try result!.get()
precondition(saved == destination)
let document = PDFDocument(url: saved)!
precondition(document.pageCount > 1, "Long notes must paginate")
precondition(document.string?.contains("PDF Export") == true)
precondition(document.string?.contains("Heading") == true)
precondition(document.string?.contains("Completed") == true)
precondition(document.string?.contains("Column") == true)
precondition(document.string?.contains("Definition") == true)
precondition(document.string?.contains("42") == true)
precondition(document.string?.contains("180") == true, "The final paragraph must not be clipped")
for index in 0..<document.pageCount {
  let bounds = document.page(at: index)!.bounds(for: .mediaBox)
  precondition(abs(bounds.width - 595.28) < 1 && abs(bounds.height - 841.89) < 1)
}
print("PASS: note selection, export trigger, bundled Markdown formatting, real multipage PDF generation")
var missingFailed = false
exporter.export(note: first, to: destination, resources: fixture.appendingPathComponent("missing")) {
  if case .failure = $0 { missingFailed = true }
}
precondition(missingFailed)
print("PASS: missing renderer resources report an export error")
