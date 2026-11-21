import Foundation
import CryptoKit

struct NoteVersion: Codable, Equatable {
  let id: UUID
  let timestamp: Date
  let title: String
  let body: String

  init(title: String, body: String, timestamp: Date = Date()) {
    id = UUID()
    self.timestamp = timestamp
    self.title = title
    self.body = body
  }

  static func read(_ content: String, url: URL) -> NoteVersion {
    let lines = content.components(separatedBy: "\n")
    let header = NoteMetadata.hasHeader(lines)
    return NoteVersion(title: header ? lines[0] : url.deletingPathExtension().lastPathComponent,
      body: header ? lines.dropFirst(lines[3].isEmpty ? 4 : 3).joined(separator: "\n") : content)
  }
}

/// Separate from SafeNoteWrite's inode backups: timestamps and note identity are explicit.
struct NoteVersionHistory {
  let root: URL
  private var directory: URL {
    root.appendingPathComponent(".simplenotes-history/versions", isDirectory: true)
  }
  private struct Archive: Codable {
    var path: String
    var versions: [NoteVersion]
  }
  private func relative(_ note: URL) -> String {
    String(note.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
  }
  private func file(_ path: String) -> URL {
    let key = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent(key + ".json")
  }
  func versions(for note: URL) throws -> [NoteVersion] {
    let location = file(relative(note))
    guard FileManager.default.fileExists(atPath: location.path) else { return [] }
    return try JSONDecoder().decode(Archive.self, from: Data(contentsOf: location)).versions
  }
  private func write(_ versions: [NoteVersion], path: String) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(Archive(path: path, versions: versions))
    try data.write(to: file(path), options: .atomic)
  }
  @discardableResult func record(_ version: NoteVersion, for note: URL, force: Bool = false) throws -> Bool {
    var saved = try versions(for: note)
    if !force, let last = saved.last, last.title == version.title && last.body == version.body { return false }
    saved.append(version)
    try write(saved, path: relative(note))
    return true
  }
  /// Persist the exact editor state before touching the editor or the note file.
  func prepareRestore(_ version: NoteVersion, current: NoteVersion, note: URL) throws -> NoteVersion {
    if version.title != current.title || version.body != current.body {
      try record(current, for: note, force: true)
    }
    return version
  }
  /// Also handles folder moves. Old history is removed only after the destination is durable.
  func remap(from source: URL, to destination: URL) throws {
    guard source != destination, FileManager.default.fileExists(atPath: directory.path) else { return }
    let old = relative(source), new = relative(destination)
    var obsolete: [URL] = []
    for location in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      where location.pathExtension == "json" {
      let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: location))
      guard archive.path == old || archive.path.hasPrefix(old + "/") else { continue }
      let path = new + archive.path.dropFirst(old.count)
      let target = root.appendingPathComponent(path)
      let existing = try versions(for: target)
      let ids = Set(existing.map(\.id))
      let combined = (existing + archive.versions.filter { !ids.contains($0.id) }).sorted { $0.timestamp < $1.timestamp }
      try write(combined, path: path)
      obsolete.append(location)
    }
    // Retain every source archive if any destination write fails.
    for location in obsolete { try? FileManager.default.removeItem(at: location) }
  }
}

struct NoteDiffLine: Equatable {
  enum Kind { case unchanged, added, removed }
  let kind: Kind
  let text: String
}

enum NoteVersionDiff {
  /// Compare the selected snapshot (red removals) with the current editor (green additions).
  static func lines(from old: String, to new: String) -> [NoteDiffLine] {
    let before = old.isEmpty ? [] : old.components(separatedBy: "\n")
    let after = new.isEmpty ? [] : new.components(separatedBy: "\n")
    // Bound work for entirely different large notes, retaining every source line.
    if before.count > 2000 && after.count > 2000 {
      var prefix = 0
      while prefix < min(before.count, after.count), before[prefix] == after[prefix] { prefix += 1 }
      var suffix = 0
      while suffix < min(before.count, after.count) - prefix,
        before[before.count - suffix - 1] == after[after.count - suffix - 1] { suffix += 1 }
      return before.prefix(prefix).map { NoteDiffLine(kind: .unchanged, text: $0) }
        + before[prefix..<(before.count - suffix)].map { NoteDiffLine(kind: .removed, text: $0) }
        + after[prefix..<(after.count - suffix)].map { NoteDiffLine(kind: .added, text: $0) }
        + before.suffix(suffix).map { NoteDiffLine(kind: .unchanged, text: $0) }
    }
    var removed = Set<Int>(), added = Set<Int>()
    for change in after.difference(from: before) {
      switch change {
      case .remove(let offset, _, _): removed.insert(offset)
      case .insert(let offset, _, _): added.insert(offset)
      }
    }
    var result: [NoteDiffLine] = [], i = 0, j = 0
    while i < before.count || j < after.count {
      if i < before.count && removed.contains(i) {
        result.append(NoteDiffLine(kind: .removed, text: before[i])); i += 1
      } else if j < after.count && added.contains(j) {
        result.append(NoteDiffLine(kind: .added, text: after[j])); j += 1
      } else if i < before.count && j < after.count {
        result.append(NoteDiffLine(kind: .unchanged, text: before[i])); i += 1; j += 1
      } else { break }
    }
    return result
  }
}
