import Foundation
import Darwin

/// Keep the actual displaced inode, including writes made through already-open
/// file descriptors. A compare followed by atomic replacement alone loses those writes.
enum SafeNoteWrite {
  static func conflict(_ url: URL) -> NSError {
    NSError(domain: "SimpleNotes.Save", code: 1, userInfo: [NSLocalizedDescriptionKey:
      "Файл «\(url.lastPathComponent)» изменён вне приложения. Обе версии сохранены; предыдущие файлы находятся в скрытой папке .simplenotes-history библиотеки. Перечитай файл перед повторным сохранением."])
  }

  static func moveExclusively(_ source: URL, to destination: URL) throws {
    guard renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: destination.path])
    }
  }

  static func publish(_ content: String, to destination: URL) throws {
    let staged = destination.deletingLastPathComponent().appendingPathComponent(".simplenotes-save-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: staged) }
    try Data(content.utf8).write(to: staged, options: .withoutOverwriting)
    try moveExclusively(staged, to: destination)
  }

  @discardableResult static func archive(_ url: URL, expected: String?, root: URL) throws -> URL {
    guard let expected = expected, try String(contentsOf: url, encoding: .utf8) == expected else { throw conflict(url) }
    let folder = root.appendingPathComponent(".simplenotes-history", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let backup = folder.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
    try moveExclusively(url, to: backup)
    do {
      guard try String(contentsOf: backup, encoding: .utf8) == expected else { throw conflict(url) }
    } catch {
      // Never replace a new file created by an external editor during the move.
      if !FileManager.default.fileExists(atPath: url.path) { try? moveExclusively(backup, to: url) }
      throw error
    }
    return backup
  }

  static func replace(_ url: URL, expected: String?, content: String, root: URL) throws {
    var coordinationError: NSError?
    var result: Result<Void, Error> = .success(())
    NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinated in
      result = Result {
        let backup = try archive(coordinated, expected: expected, root: root)
        do {
          let snapshot = backup.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + "-saved-" + url.lastPathComponent)
          try Data(content.utf8).write(to: snapshot, options: .withoutOverwriting)
          try publish(content, to: coordinated)
        } catch {
          if !FileManager.default.fileExists(atPath: coordinated.path) { try? moveExclusively(backup, to: coordinated) }
          throw error
        }
      }
    }
    if let error = coordinationError { throw error }
    try result.get()
  }
}
