//
//  Materials.swift
//  Walnut
//
//  The radio's materials: the two walnuts, brushed and spun brass, fine grain,
//  and the colours of the display glass. Values follow design-reference/mockup.
//

import SwiftUI

enum Radio {
  /// The radio is laid out in the mockup's units (760 wide) and drawn at this scale, 688 pt wide.
  static let scale: CGFloat = 688 / 760   // 80% of the original 860 pt
  /// Fixed size of the radio itself, in mockup units (the window adds room for its shadow and feet).
  static let size = CGSize(width: 760, height: 348)
  static let cabinetRadius: CGFloat = 34
  static let cabinetPadding: CGFloat = 20
  static let panelRadius: CGFloat = 16
}

// MARK: - Textures

enum Texture {
  static func image(_ name: String) -> NSImage {
    guard let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: nil)
            ?? Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Radio"),
          let image = NSImage(contentsOf: url) else { return NSImage(size: NSSize(width: 1, height: 1)) }
    return image
  }

  static let frameWalnut = image("wood027")   // ambientCG Wood027, CC0
  static let panelWalnut = image("wood026")   // ambientCG Wood026, CC0
  static let brushedMetal = image("metal009") // ambientCG Metal009, CC0
  static let paper = image("paper006")        // ambientCG Paper006, CC0

  /// A few worn patches for the wooden lettering (white = worn), the same every launch.
  static let wear: NSImage = {
    let size = NSSize(width: 240, height: 30)
    let image = NSImage(size: size)
    image.lockFocus()
    var rng = SeededRandom(seed: 11)
    NSColor.white.setFill()
    for _ in 0..<9 {
      let w = CGFloat.random(in: 7...16, using: &rng), h = CGFloat.random(in: 3...7, using: &rng)
      NSBezierPath(ovalIn: NSRect(x: .random(in: 0...size.width, using: &rng), y: .random(in: 0...size.height, using: &rng), width: w, height: h)).fill()
    }
    for _ in 0..<25 {
      let d = CGFloat.random(in: 0.6...1.4, using: &rng)
      NSBezierPath(ovalIn: NSRect(x: .random(in: 0...size.width, using: &rng), y: .random(in: 0...size.height, using: &rng), width: d, height: d)).fill()
    }
    image.unlockFocus()
    return image
  }()

  /// Per-pixel grain, one texel per device pixel, laid over surfaces with overlay blending.
  static let grain: NSImage = {
    let side = 256
    var bytes = [UInt8](repeating: 0, count: side * side * 4)
    for i in stride(from: 0, to: bytes.count, by: 4) {
      let v = UInt8(clamping: 128 + Int.random(in: -45...45))
      bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v; bytes[i + 3] = 255
    }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32)!
    bytes.withUnsafeBytes { memcpy(rep.bitmapData!, $0.baseAddress!, bytes.count) }
    let image = NSImage(size: NSSize(width: side / 2, height: side / 2))   // 2x: one texel per Retina pixel
    image.addRepresentation(rep)
    return image
  }()
}

// MARK: - Surfaces

/// The darker outer walnut: Wood027 warmed with a soft-light tint, plus fine grain.
struct FrameWalnut: View {
  var body: some View {
    ZStack {
      Color(red: 0.35, green: 0.2, blue: 0.1)
      Color.clear.overlay(Image(nsImage: Texture.frameWalnut).resizable().aspectRatio(contentMode: .fill)).clipped()   // one piece, no tiling seams
      LinearGradient(colors: [Color(hex: 0x946036), Color(hex: 0x87542F)], startPoint: .top, endPoint: .bottom)
        .blendMode(.softLight)
      Grain(opacity: 0.12)
    }
  }
}

/// The lighter front panel: Wood026 shifted toward walnut brown, keeping its lightness.
struct PanelWalnut: View {
  var body: some View {
    ZStack {
      Color(hex: 0x8A5228)
      Color.clear.overlay(Image(nsImage: Texture.panelWalnut).resizable().aspectRatio(contentMode: .fill)).clipped()   // one piece, no tiling seams
      Color(red: 118 / 255, green: 78 / 255, blue: 50 / 255).opacity(0.55).blendMode(.color)
      Grain(opacity: 0.12)
    }
  }
}

struct Grain: View {
  var opacity: Double
  var body: some View {
    Rectangle().fill(ImagePaint(image: Image(nsImage: Texture.grain), scale: 1))
      .blendMode(.overlay).opacity(opacity).allowsHitTesting(false)
  }
}

/// Brushed brass for the display frame: darker, lighter toward the top.
struct BrushedBrass: View {
  var body: some View {
    ZStack {
      LinearGradient(colors: [Color(hex: 0xB8914A), Color(hex: 0x9C7636), Color(hex: 0x7A5A24)],
                     startPoint: .top, endPoint: .bottom)
      Rectangle().fill(ImagePaint(image: Image(nsImage: Texture.brushedMetal), scale: 600 / 2048))
        .blendMode(.overlay)
    }
  }
}

// MARK: - Colours

extension Color {
  init(hex: UInt32, opacity: Double = 1) {
    self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255, opacity: opacity)
  }
}

/// The display glass and its ink, light (backlit cream) and dark (smoked glass, glowing amber).
struct GlassStyle {
  let glass: [Color]          // centre to edge
  let ink: Color
  let inkDim: Color
  let inkOff: Color
  let songStrong: Color
  let stripBackground: Color
  let stripLine: Color
  let selectedText: Color
  let glow: Color             // text glow (clear in light mode)
  let glare: Double

  static let light = GlassStyle(
    glass: [Color(hex: 0xFFF4CF), Color(hex: 0xF4E2B0), Color(hex: 0xE4C98A)],
    ink: Color(hex: 0x3A2A14), inkDim: Color(hex: 0x7D6740), inkOff: Color(hex: 0x5A4119, opacity: 0.14),
    songStrong: Color(hex: 0x5D4826),
    stripBackground: Color(hex: 0x6E460F, opacity: 0.07), stripLine: Color(hex: 0x6E460F, opacity: 0.16),
    selectedText: Color(hex: 0xF6E6B8), glow: .clear, glare: 0.5)

  static let dark = GlassStyle(
    glass: [Color(hex: 0x2A1A0B), Color(hex: 0x170E06), Color(hex: 0x0C0703)],
    ink: Color(hex: 0xFFBE5C), inkDim: Color(hex: 0xC88D40), inkOff: Color(hex: 0xFFAA3C, opacity: 0.08),
    songStrong: Color(hex: 0xF2AD4F),
    stripBackground: Color(hex: 0xFFAA3C, opacity: 0.04), stripLine: Color(hex: 0xFFAA3C, opacity: 0.12),
    selectedText: Color(hex: 0x140C05), glow: Color(hex: 0xFFA532, opacity: 0.45), glare: 0.14)
}

let accentRed = Color(hex: 0xD2462F)
let engraveBrown = Color(hex: 0x5A4120)

/// Mockup units to points: every dimension in the radio goes through this.
@inline(__always) func u(_ v: CGFloat) -> CGFloat { v * Radio.scale }


/// Small deterministic random generator, so generated wear looks the same every time.
struct SeededRandom: RandomNumberGenerator {
  var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state = state &* 6364136223846793005 &+ 1442695040888963407
    return state
  }
}
