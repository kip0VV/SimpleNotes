import Cocoa

func runReminderPanelChecks(notes: NotesApp) throws {
  let oldFrame = notes.window.frame
  let oldReminders = notes.sidebarReminders
  let oldSettings = notes.settingsController
  let notifications = notes.notificationsEnabled
  let records = NSDictionary(dictionary: notes.reminderRecords)
  let settings = NotesSettingsController(app: notes)
  notes.settingsController = settings
  defer {
    notes.defaults.removeObject(forKey: "hideReminderSidebar")
    notes.defaults.removeObject(forKey: "reminderViewportHeight")
    notes.sidebarReminders = oldReminders
    notes.settingsController = oldSettings
    notes.window.setFrame(oldFrame, display: false)
    notes.renderSidebarReminders()
  }
  notes.window.setContentSize(NSSize(width: 1060, height: 900))
  notes.defaults.removeObject(forKey: "hideReminderSidebar")
  notes.defaults.removeObject(forKey: "reminderViewportHeight")
  notes.sidebarReminders = (0..<24).map { index in
    ActiveReminder(path: "Reminder \(index).md", date: Date().addingTimeInterval(Double(index + 1) * 3600), repetition: .daily)
  }
  notes.renderSidebarReminders()
  precondition(notes.reminderList.arrangedSubviews.count == 3 && notes.reminderListHeight?.constant == 144,
    "Default reminder panel remains compact")
  notes.resizeReminderViewport(to: 336)
  precondition(notes.reminderListHeight?.constant == 336 && notes.reminderList.arrangedSubviews.count == 7,
    "Dragging upward reveals more nearest reminders")
  precondition(notes.defaults.double(forKey: "reminderViewportHeight") == 336,
    "Chosen viewport height persists")
  notes.resizeReminderViewport(to: 12)
  precondition(notes.reminderSidebarHidden && notes.reminderPanel!.isHidden
    && notes.reminderPanelCollapsedHeight!.isActive && notes.reminderPanelTop!.isActive == false
    && notes.reminderListHeight?.constant == 0 && settings.hideReminderPanel.state == .on,
    "Dragging below collapse threshold hides panel and checks settings")
  precondition(notes.notificationsEnabled == notifications && NSDictionary(dictionary: notes.reminderRecords) == records,
    "Hiding the panel preserves notification preferences and reminder records")
  let restored = NotesApp()
  precondition(restored.reminderSidebarHidden && restored.defaults.double(forKey: "reminderViewportHeight") == 336,
    "Fresh application state reads saved visibility and height")
  settings.toggle(settings.hideReminderPanel)
  precondition(!notes.reminderSidebarHidden && !notes.reminderPanel!.isHidden
    && notes.reminderListHeight?.constant == 336 && settings.hideReminderPanel.state == .off,
    "Unchecking settings restores previous height")
  settings.toggle(settings.hideReminderPanel)
  precondition(notes.reminderSidebarHidden && settings.hideReminderPanel.state == .on,
    "Settings checkbox can hide panel without dragging")
  notes.toggleReminderSidebar()
  notes.window.setContentSize(NSSize(width: 1060, height: 500))
  notes.renderSidebarReminders()
  precondition(notes.reminderListHeight!.constant <= notes.maximumReminderViewportHeight
    && notes.defaults.double(forKey: "reminderViewportHeight") == 336,
    "Small windows clamp the viewport without losing preferred height")
  notes.window.setContentSize(NSSize(width: 1060, height: 900))
  notes.renderSidebarReminders()
  precondition(notes.reminderListHeight?.constant == 336, "Larger window restores preferred height")
  notes.resizeReminderViewport(to: .nan)
  precondition(notes.reminderListHeight?.constant == 336, "Invalid drag values cannot corrupt layout")
  print("Reminder panel checks passed — resizing, visible rows, collapse, settings sync, persistence and notification preservation")
}
