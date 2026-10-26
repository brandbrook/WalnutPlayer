//
//  RadioWindow.swift
//  Walnut
//
//  The radio-shaped window: no title bar, fixed size, transparent around the radio so only the
//  cabinet, its feet and shadow show. Dragged by the wood; close and minimise appear on hover.
//

import AppKit
import SwiftUI

final class RadioWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

@objc(RadioWindowController)
@MainActor
final class RadioWindowController: NSWindowController, NSWindowDelegate {
  @objc static let shared = RadioWindowController()

  /// Margins around the radio for its shadow and feet.
  private static let margin = NSEdgeInsets(top: 2, left: 2, bottom: u(5 + 7) + 2, right: 2)   // room for the feet only, no shadow
  private var keyMonitor: Any?

  private init() {
    let radio = NSSize(width: u(Radio.size.width), height: u(Radio.size.height))
    let m = Self.margin
    let frame = NSRect(x: 0, y: 0, width: radio.width + m.left + m.right, height: radio.height + m.top + m.bottom)
    let window = RadioWindow(contentRect: frame, styleMask: [.borderless, .miniaturizable], backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false            // the radio draws its own shadow on the desk
    window.isMovableByWindowBackground = false
    window.title = "Walnut"
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.fullScreenNone]
    window.setFrameAutosaveName("WalnutRadio")
    super.init(window: window)
    window.delegate = self

    let root = RadioView(model: RadioModel.shared)
      .padding(EdgeInsets(top: m.top, leading: m.left, bottom: m.bottom, trailing: m.right))
      .frame(width: frame.width, height: frame.height, alignment: .top)
    let host = NSHostingView(rootView: root)
    host.frame = frame
    window.contentView = host
    if !window.setFrameUsingName("WalnutRadio") { window.center() }
    installKeys()
  }

  required init?(coder: NSCoder) { fatalError() }

  @objc func startRadio() {
    RadioModel.shared.start()
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
  }

  @objc func bringToFront() {
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  /// Arrow keys, Return, Escape and Space drive the display, like the brass buttons do.
  private func installKeys() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, event.window === self.window else { return event }
      let model = RadioModel.shared
      let editing = (self.window?.firstResponder as? NSTextView) != nil
      let list = model.mode == .stations || model.mode == .history || model.mode == .newStation
      switch event.keyCode {
      case 53:                                   // Escape
        model.back(); return nil
      case 49:                                   // Space
        if editing { return event }
        model.playPause(); return nil
      case 125, 126:                             // down, up
        guard list else { return event }
        model.move(event.keyCode == 125 ? 1 : -1); return nil
      case 123, 124:                             // left, right: a column at a time
        guard !editing, model.mode.isBrowser else { return event }
        model.move(event.keyCode == 124 ? 4 : -4); return nil
      case 36, 76:                               // Return
        if editing { return event }
        if model.mode == .nowPlaying { model.back() } else { model.choose() }
        return nil
      default:
        return event
      }
    }
  }
}
