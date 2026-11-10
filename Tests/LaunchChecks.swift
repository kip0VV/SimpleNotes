import Carbon
import Cocoa

func runLaunchChecks() {
  let event = NSAppleEventDescriptor(
    eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
    targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
    transactionID: AETransactionID(kAnyTransactionID))
  precondition(!NotesApp.isServiceLaunch(nil) && !NotesApp.isServiceLaunch(event),
    "Normal startup does not look like a service")
  event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsServiceItem)),
    forKeyword: AEKeyword(keyAEPropData))
  precondition(NotesApp.isServiceLaunch(event), "Service startup is recognized")
  let pending = NotesApp()
  pending.openQuickNote()
  precondition(pending.pendingQuickNote && pending.window == nil,
    "Early hotkey queues a request without showing or accessing an unbuilt window")
  print("Launch checks passed — service event and early hotkey")
}
