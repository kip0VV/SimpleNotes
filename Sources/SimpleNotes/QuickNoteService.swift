import Carbon
import Cocoa
import CoreServices

extension NotesApp {
  var quickNoteServiceID: String {
    "io.github.kip0vv.SimpleNotes - Новая заметка в SimpleNotes - newNoteService"
  }

  // The service is registered only after the editor and restored draft are ready.
  func prepareQuickNoteService() {
    LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
    NSApp.servicesProvider = self
    if defaults.string(forKey: "quickNoteServiceCharacter") == nil,
      let code = defaults.object(forKey: "quickNoteKeyCode") as? UInt32,
      let character = shortcutCharacter(keyCode: code)
    {
      defaults.set(character, forKey: "quickNoteServiceCharacter")
      setQuickNoteServiceShortcut(
        serviceKeyEquivalent(
          character: character, modifiers: UInt32(defaults.integer(forKey: "quickNoteModifiers"))))
    }
    NSUpdateDynamicServices()
  }

  @objc func newNoteService(
    _ pasteboard: NSPasteboard, userData: String?,
    error: AutoreleasingUnsafeMutablePointer<NSString?>
  ) {
    DispatchQueue.main.async { [weak self] in
      self?.showWindow()
      self?.newNote()
    }
  }

  func serviceKeyEquivalent(character: String, modifiers: UInt32) -> String {
    var equivalent = ""
    if modifiers & UInt32(controlKey) != 0 { equivalent += "^" }
    if modifiers & UInt32(optionKey) != 0 { equivalent += "~" }
    if modifiers & UInt32(shiftKey) != 0 { equivalent += "$" }
    if modifiers & UInt32(cmdKey) != 0 { equivalent += "@" }
    return equivalent + character
  }

  func setQuickNoteServiceShortcut(_ equivalent: String?) {
    let domain = "pbs" as CFString
    var services =
      CFPreferencesCopyAppValue("NSServicesStatus" as CFString, domain)
      as? [String: [String: Any]] ?? [:]
    var entry = services[quickNoteServiceID] ?? [:]
    entry["key_equivalent"] = equivalent ?? ""
    entry["enabled_services_menu"] = true
    services[quickNoteServiceID] = entry
    CFPreferencesSetAppValue("NSServicesStatus" as CFString, services as CFDictionary, domain)
    CFPreferencesSetAppValue("ServicesShortcutsPresent" as CFString, true as CFBoolean, domain)
    CFPreferencesAppSynchronize(domain)
    NSUpdateDynamicServices()
  }

  func shortcutCharacter(keyCode: UInt32) -> String? {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
      let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }
    let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
    guard let bytes = CFDataGetBytePtr(data) else { return nil }
    let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
    var state: UInt32 = 0
    var length = 0
    var characters = [UniChar](repeating: 0, count: 4)
    let result = UCKeyTranslate(
      layout, UInt16(keyCode), UInt16(kUCKeyActionDown), 0,
      UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &state,
      characters.count, &length, &characters)
    guard result == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: characters, count: length).lowercased()
  }
}
