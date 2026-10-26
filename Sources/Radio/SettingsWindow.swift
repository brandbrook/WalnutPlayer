//
//  SettingsWindow.swift
//  Walnut
//
//  Walnut's Settings, replacing the old Hermes preferences window. Every option reads and writes
//  the same saved settings the engine uses, and calls the engine's own update actions when needed.
//

import AppKit
import Sparkle
import SwiftUI

// MARK: - Window

@MainActor
final class SettingsWindowController: NSWindowController {
  static let shared = SettingsWindowController()

  private init() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "Walnut Settings"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: SettingsView())
    window.center()
    window.setFrameAutosaveName("WalnutSettings")
    super.init(window: window)
  }

  required init?(coder: NSCoder) { fatalError() }

  @objc func show() {
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

// MARK: - Views

private struct SettingsView: View {
  @AppStorage("walnut.settingsTab") private var tab = "general"   // reopens on the last tab
  var body: some View {
    TabView(selection: $tab) {
      GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }.tag("general")
      PlaybackSettings().tabItem { Label("Playback", systemImage: "play.circle") }.tag("playback")
      AccountSettings().tabItem { Label("Account", systemImage: "person.crop.circle") }.tag("account")
      NetworkSettings().tabItem { Label("Network", systemImage: "network") }.tag("network")
    }
    .frame(width: 520)
    .fixedSize(horizontal: false, vertical: true)
  }
}

private var app: HermesAppDelegate { NSApp.delegate as! HermesAppDelegate }

private struct GeneralSettings: View {
  @AppStorage("statusBarIcon") private var menuBar = false
  @AppStorage("statusBarShowSongTitle") private var songTitle = false
  @AppStorage("statusBarIconBlackWhite") private var blackWhite = false
  @AppStorage("statusBarIconAlbumArt") private var albumArtIcon = false
  @AppStorage("dockIconAlbumArt") private var dockArt = false
  @AppStorage("albumArtPlayPause") private var playPauseOverArt = false
  @AppStorage("alwaysOnTop") private var onTop = false
  @StateObject private var updates = UpdateSettings()

  private var iconStyle: Binding<Int> {
    Binding(get: { albumArtIcon ? 2 : (blackWhite ? 1 : 0) },
            set: { blackWhite = $0 == 1; albumArtIcon = $0 == 2; app.updateStatusItem(nil) })
  }

  var body: some View {
    Form {
      Section {
        Toggle("Keep Walnut in the menu bar instead of the Dock", isOn: $menuBar)
          .onChange(of: menuBar) { _ in app.updateStatusItemVisibility(self) }
        Picker("Menu bar icon", selection: iconStyle) {
          Text("Walnut icon").tag(0)
          Text("Black and white, with play/pause").tag(1)
          Text("Album art").tag(2)
        }
        .disabled(!menuBar)
        Toggle("Show the song title in the menu bar", isOn: $songTitle)
          .onChange(of: songTitle) { _ in app.updateStatusItem(nil) }
          .disabled(!menuBar)
      }
      Section {
        Toggle("Show album art as the Dock icon", isOn: $dockArt)
          .onChange(of: dockArt) { _ in app.updateDockIcon(nil) }
          .disabled(menuBar)
        Toggle("Show play/pause over the album art", isOn: $playPauseOverArt)
          .onChange(of: playPauseOverArt) { _ in app.updateStatusItem(nil); app.updateDockIcon(nil) }
          .disabled(menuBar || !dockArt)
        Toggle("Keep the radio on top of other windows", isOn: $onTop)
          .onChange(of: onTop) { _ in RadioWindowController.shared.applyAlwaysOnTop() }
      }
      Section {
        Toggle("Check for updates automatically", isOn: $updates.automaticallyChecks)
        Toggle("Download and install updates automatically", isOn: $updates.automaticallyDownloads)
          .disabled(!updates.automaticallyChecks)
      }
    }
    .formStyle(.grouped)
  }
}

private struct PlaybackSettings: View {
  @AppStorage("audioQuality") private var quality = 0
  @AppStorage("pleaseGrowl") private var notify = true
  @AppStorage("pleaseGrowlNew") private var notifyNew = true
  @AppStorage("pleaseGrowlPlay") private var notifyResume = false
  @AppStorage("pauseOnScreensaverStart") private var pauseSaver = false
  @AppStorage("playOnScreensaverStop") private var playSaver = false
  @AppStorage("pauseOnScreenLock") private var pauseLock = false
  @AppStorage("playOnScreenUnlock") private var playUnlock = false
  @AppStorage("pleaseScrobble") private var scrobble = false
  @AppStorage("pleaseScrobbleLikes") private var scrobbleLikes = false
  @AppStorage("onlyScrobbleLiked") private var onlyLiked = false

  var body: some View {
    Form {
      Section {
        Picker("Audio quality", selection: $quality) {
          Text("High").tag(0)
          Text("Medium").tag(1)
          Text("Low").tag(2)
        }
        .pickerStyle(.segmented)
      } footer: {
        Text("Applies from the next song. High quality needs a Pandora subscription for its best stream.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section("Notifications") {
        Toggle("Show notifications", isOn: $notify)
        Toggle("When a song starts", isOn: $notifyNew).disabled(!notify)
        Toggle("When playback resumes", isOn: $notifyResume).disabled(!notify)
      }
      Section("Pause and resume") {
        Toggle("Pause when the screen saver starts", isOn: $pauseSaver)
        Toggle("Play when the screen saver stops", isOn: $playSaver)
        Toggle("Pause when the screen locks", isOn: $pauseLock)
        Toggle("Play when the screen unlocks", isOn: $playUnlock)
      }
      Section("Last.fm") {
        Toggle("Scrobble songs to Last.fm", isOn: $scrobble)
        Toggle("Send likes and dislikes", isOn: $scrobbleLikes).disabled(!scrobble)
        Toggle("Only scrobble songs I like", isOn: $onlyLiked).disabled(!scrobble)
      }
    }
    .formStyle(.grouped)
  }
}

private struct AccountSettings: View {
  @AppStorage("pandora.username") private var username = ""
  @ObservedObject private var model = RadioModel.shared

  var body: some View {
    Form {
      Section {
        LabeledContent("Pandora account", value: username.isEmpty ? "Not signed in" : username)
      } footer: {
        Text("Walnut is not affiliated with Pandora.").font(.caption).foregroundStyle(.secondary)
      }
      Section {
        HStack {
          Spacer()
          if username.isEmpty || model.mode == .login {
            Button("Sign In…") { RadioWindowController.shared.bringToFront() }
          } else {
            Button("Sign Out") { app.auth.logout(nil) }
          }
        }
      }
    }
    .formStyle(.grouped)
  }
}

private struct NetworkSettings: View {
  @AppStorage("enabledProxy") private var proxy = 0
  @AppStorage("httpProxyHost") private var httpHost = ""
  @AppStorage("httpProxyPort") private var httpPort = 0
  @AppStorage("socksProxyHost") private var socksHost = ""
  @AppStorage("socksProxyPort") private var socksPort = 0
  @AppStorage("proxyAudio") private var proxyAudio = false

  var body: some View {
    Form {
      Section {
        Picker("Proxy", selection: $proxy) {
          Text("Use system settings").tag(0)
          Text("HTTP(S) proxy").tag(1)
          Text("SOCKS proxy").tag(2)
        }
        if proxy == 1 {
          TextField("Host", text: $httpHost)
          TextField("Port", value: $httpPort, format: .number.grouping(.never))
        } else if proxy == 2 {
          TextField("Host", text: $socksHost)
          TextField("Port", value: $socksPort, format: .number.grouping(.never))
        }
        Toggle("Also use the proxy for audio", isOn: $proxyAudio).disabled(proxy == 0)
      }
    }
    .formStyle(.grouped)
    .onChange(of: proxy) { _ in app.preferences.proxySettingsChanged(nil) }
    .onChange(of: httpHost) { _ in app.preferences.proxySettingsChanged(nil) }
    .onChange(of: httpPort) { _ in app.preferences.proxySettingsChanged(nil) }
    .onChange(of: socksHost) { _ in app.preferences.proxySettingsChanged(nil) }
    .onChange(of: socksPort) { _ in app.preferences.proxySettingsChanged(nil) }
  }
}

/// Sparkle's update options, through the updater behind the app menu's "Check for Updates…" item.
@MainActor
private final class UpdateSettings: ObservableObject {
  private let updater: SPUUpdater? = {
    let item = NSApp.mainMenu?.items.first?.submenu?.items.first { $0.action == #selector(SPUStandardUpdaterController.checkForUpdates(_:)) }
    return (item?.target as? SPUStandardUpdaterController)?.updater
  }()

  var automaticallyChecks: Bool {
    get { updater?.automaticallyChecksForUpdates ?? false }
    set { objectWillChange.send(); updater?.automaticallyChecksForUpdates = newValue }
  }
  var automaticallyDownloads: Bool {
    get { updater?.automaticallyDownloadsUpdates ?? false }
    set { objectWillChange.send(); updater?.automaticallyDownloadsUpdates = newValue }
  }
}
