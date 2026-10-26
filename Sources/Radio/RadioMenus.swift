//
//  RadioMenus.swift
//  Walnut
//
//  Points the menu bar at the radio: the View menu switches the display between now playing,
//  stations and history, and the station items in the Pandora menu open the display's own screens.
//  Items for the old drawers, toolbar and full screen are removed.
//

import AppKit

@MainActor
final class RadioMenus: NSObject {
  static let shared = RadioMenus()
  private var model: RadioModel { RadioModel.shared }

  func install() {
    UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")   // no Enter Full Screen
    guard let main = NSApp.mainMenu else { return }

    // Settings…: the new Settings window
    if let settings = main.items.first?.submenu?.items.first(where: { $0.title.hasPrefix("Settings") || $0.title.hasPrefix("Preferences") }) {
      settings.target = SettingsWindowController.shared
      settings.action = #selector(SettingsWindowController.show)
    }

    // View: the display's screens
    if let view = main.item(withTitle: "View")?.submenu {
      view.removeAllItems()
      view.addItem(item("Now Playing", key: "0", #selector(showNowPlaying)))
      view.addItem(item("Stations", key: "1", #selector(showStations)))
      view.addItem(item("History", key: "2", #selector(showHistory)))
      view.addItem(.separator())
      let appearance = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
      let sub = NSMenu(title: "Display")
      for (title, theme) in [("System", DisplayTheme.system), ("Light", .light), ("Dark", .dark)] {
        let i = item(title, key: "", #selector(setTheme(_:)))
        i.representedObject = theme.rawValue
        sub.addItem(i)
      }
      appearance.submenu = sub
      view.addItem(appearance)
    }

    // Pandora: station items open the display's screens instead of the old sheets
    if let pandora = main.item(withTitle: "Pandora")?.submenu {
      retarget(pandora.item(withTitle: "New Station…"), #selector(newStation))
      if let edit = pandora.item(withTitle: "Edit Selected Station") {
        edit.title = "Edit Station…"
        retarget(edit, #selector(editStation))
      }
    }

    // Window: no zoom or full screen for a fixed-size radio
    if let window = main.item(withTitle: "Window")?.submenu {
      for title in ["Zoom", "Zoom All", "Main Window"] {
        if let i = window.item(withTitle: title) { window.removeItem(i) }
      }
      window.insertItem(item("Walnut", key: "1", #selector(bringToFront)), at: 2)
    }

    // Help: the website and GitHub are the same place now
    if let help = main.item(withTitle: "Help")?.submenu, let site = help.item(withTitle: "Walnut Web Site") {
      help.removeItem(site)
    }
  }

  private func item(_ title: String, key: String, _ action: Selector) -> NSMenuItem {
    let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
    i.target = self
    return i
  }

  private func retarget(_ item: NSMenuItem?, _ action: Selector) {
    item?.target = self
    item?.action = action
  }

  private var loggedIn: Bool {
    switch model.mode { case .login, .loading: return false; default: return true }
  }

  @objc private func showNowPlaying() { bringToFront(); if model.currentToken != nil { model.mode = .nowPlaying } }
  @objc private func showStations() { bringToFront(); model.showBrowser(.stations) }
  @objc private func showHistory() { bringToFront(); model.showBrowser(.history) }
  @objc private func newStation() { bringToFront(); model.beginNewStation() }
  @objc private func editStation() {
    bringToFront()
    if let i = model.sortedStations.firstIndex(where: { $0.id == model.currentToken }) { model.beginEdit(i) }
  }
  @objc private func setTheme(_ sender: NSMenuItem) {
    if let raw = sender.representedObject as? String, let t = DisplayTheme(rawValue: raw) { model.theme = t }
  }
  @objc private func bringToFront() { RadioWindowController.shared.bringToFront() }
}

extension RadioMenus: NSMenuItemValidation {
  func validateMenuItem(_ item: NSMenuItem) -> Bool {
    switch item.action {
    case #selector(setTheme(_:)):
      item.state = (item.representedObject as? String) == model.theme.rawValue ? .on : .off
      return true
    case #selector(showNowPlaying): return model.currentToken != nil
    case #selector(editStation):
      return loggedIn && model.sortedStations.first { $0.id == model.currentToken }?.canEdit == true
    case #selector(showStations), #selector(showHistory), #selector(newStation): return loggedIn
    default: return true
    }
  }
}
