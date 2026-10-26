//
//  MenuBarIcon.swift
//  Walnut
//
//  Menu bar icons. The default is a template glyph (the radio's speaker in its cabinet), which macOS
//  tints to suit light, dark and coloured menu bars; the colour radio is the optional alternative.
//

import AppKit

@objc final class MenuBarIcon: NSObject {
  /// Speaker in a rounded cabinet. Playing: the dust cap is filled; paused: two pause bars instead.
  @objc static func glyph(playing: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
      NSColor.black.set()
      let cabinet = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 15, height: 15), xRadius: 4, yRadius: 4)
      cabinet.lineWidth = 1.5
      cabinet.stroke()
      let speaker = NSBezierPath(ovalIn: NSRect(x: 4.5, y: 4.5, width: 9, height: 9))
      speaker.lineWidth = 1.5
      speaker.stroke()
      if playing {
        NSBezierPath(ovalIn: NSRect(x: 7.4, y: 7.4, width: 3.2, height: 3.2)).fill()
      } else {
        NSBezierPath(roundedRect: NSRect(x: 7.3, y: 7.2, width: 1.2, height: 3.6), xRadius: 0.5, yRadius: 0.5).fill()
        NSBezierPath(roundedRect: NSRect(x: 9.5, y: 7.2, width: 1.2, height: 3.6), xRadius: 0.5, yRadius: 0.5).fill()
      }
      return true
    }
    image.isTemplate = true
    return image
  }

  /// The colour walnut radio, cropped tight so it fills the menu bar slot. It's drawn when macOS
  /// paints the menu bar, so it picks the darker walnut on a light bar and lighter walnut on a dark one.
  @objc static let color: NSImage = {
    let standard = Bundle.main.image(forResource: "walnut-menubar") ?? NSImage()
    let light = Bundle.main.image(forResource: "walnut-menubar-light") ?? standard
    return NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
      let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      (dark ? light : standard).draw(in: rect)
      return true
    }
  }()
}
