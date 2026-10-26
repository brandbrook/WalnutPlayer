//
//  SpeakerView.swift
//  Walnut
//
//  The exposed speaker: a single polished brass band with four dark screws, a rubber roll,
//  a grained paper cone and a glossy dust cap. Bass pushes the cone like a damped spring,
//  mids add a faint flutter, highs make the dust cap's highlight shimmer, all from the real
//  audio levels measured by the playback tap (WalnutAudio).
//

import SwiftUI

/// Turns raw band levels into smooth 0…1 drive values, with a slowly adapting ceiling so quiet
/// and loud songs both move the cone, and a spring for the cone itself.
final class SpeakerMotion {
  private(set) var low = 0.0, mid = 0.0, high = 0.0
  private(set) var cone = 0.0
  private var velocity = 0.0
  /// Per band: a running average (about a second) and a slowly falling peak. A reading is scaled
  /// between "a little under the average" and the peak, so beats and swells stand out from steady music.
  private var bands = [Band(), Band(), Band()]

  private struct Band {
    var average = 0.0, peak = 0.0
    mutating func drive(_ raw: Double) -> Double {
      average += (raw - average) * 0.02
      peak = max(raw, peak * 0.995)
      let floor = average * 0.85
      return ((raw - floor) / max(peak - floor, 1e-4)).clamped(to: 0...1)
    }
  }

  func step(playing: Bool) {
    var l: Float = 0, m: Float = 0, h: Float = 0
    WalnutAudioGetLevels(&l, &m, &h)
    let target = playing ? (bands[0].drive(Double(l)), bands[1].drive(Double(m)), bands[2].drive(Double(h))) : (0, 0, 0)
    func ease(_ v: inout Double, _ t: Double) { v += (t - v) * (t > v ? 0.6 : 0.16) }
    ease(&low, target.0); ease(&mid, target.1); ease(&high, target.2)
    velocity += (min(1, low * 0.9 + mid * 0.12) - cone) * 0.32   // spring
    velocity *= 0.62                                             // damping
    cone += velocity
  }
}

struct SpeakerView: View {
  var playing: Bool
  @State private var motion = SpeakerMotion()

  var body: some View {
    TimelineView(.animation(paused: false)) { timeline in
      Canvas { ctx, size in
        motion.step(playing: playing)
        draw(&ctx, size: size, t: timeline.date.timeIntervalSinceReferenceDate)
      }
    }
    .allowsHitTesting(false)
  }

  private func ring(_ c: CGPoint, _ ro: CGFloat, _ ri: CGFloat) -> Path {
    var p = Path()
    p.addEllipse(in: CGRect(x: c.x - ro, y: c.y - ro, width: ro * 2, height: ro * 2))
    p.addEllipse(in: CGRect(x: c.x - ri, y: c.y - ri, width: ri * 2, height: ri * 2))
    return p
  }
  private func circle(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
  private func arc(_ c: CGPoint, _ r: CGFloat, _ from: Double, _ to: Double) -> Path {
    var p = Path(); p.addArc(center: c, radius: r, startAngle: .radians(from * .pi), endAngle: .radians(to * .pi), clockwise: false); return p
  }
  /// Blends fine grain into what's already drawn (a copy of the context, so the blend mode applies to the canvas).
  private func grain(_ ctx: inout GraphicsContext, _ clip: Path, _ opacity: Double, eo: Bool = false) {
    var g = ctx
    g.clip(to: clip, style: FillStyle(eoFill: eo))
    g.blendMode = .overlay; g.opacity = opacity
    g.fill(clip.boundingRect.insetBy(dx: -2, dy: -2).path, with: .tiledImage(Image(nsImage: Texture.grain), scale: 1))
  }

  private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
    let e = motion.cone, hi = motion.high
    let flutter = motion.mid * sin(t * 47) * 0.004
    let c = CGPoint(x: size.width / 2, y: size.height / 2), R = min(size.width, size.height) * 0.45
    let bO = R, bI = R * 0.88, so = R * 0.88, capR = R * 0.26
    let eoFill = FillStyle(eoFill: true)

    // contact with the panel: a soft short shadow and a tight dark one
    ctx.drawLayer { l in l.addFilter(.shadow(color: Color(hex: 0x140A02, opacity: 0.45), radius: 3, y: 2)); l.fill(circle(c, bO), with: .color(Color(hex: 0x1B1B1B))) }
    ctx.drawLayer { l in l.addFilter(.shadow(color: Color(hex: 0x0A0500, opacity: 0.85), radius: 0.6, y: 0.8)); l.fill(circle(c, bO), with: .color(Color(hex: 0x1B1B1B))) }

    // brass band
    let brass = Gradient(stops: [.init(color: Color(hex: 0xF0D79A), location: 0), .init(color: Color(hex: 0xB8904A), location: 0.28),
                                 .init(color: Color(hex: 0xE3C584), location: 0.5), .init(color: Color(hex: 0x8A6528), location: 0.75),
                                 .init(color: Color(hex: 0xC9A462), location: 1)])
    ctx.fill(ring(c, bO, bI), with: .linearGradient(brass, startPoint: CGPoint(x: c.x - bO, y: c.y - bO), endPoint: CGPoint(x: c.x + bO, y: c.y + bO)), style: eoFill)
    grain(&ctx, ring(c, bO, bI), 0.22, eo: true)
    ctx.stroke(arc(c, bO - 0.5, 1.05, 1.95), with: .color(Color(hex: 0xFFF8DE, opacity: 0.75)), lineWidth: 0.5)
    ctx.stroke(arc(c, bI + 0.5, 0.1, 0.9), with: .color(Color(hex: 0xFFF8DE, opacity: 0.5)), lineWidth: 0.5)
    ctx.stroke(circle(c, bO), with: .color(Color(hex: 0x3C280A, opacity: 0.9)), lineWidth: 0.5)
    ctx.stroke(circle(c, bI), with: .color(Color(hex: 0x140C02, opacity: 0.95)), lineWidth: 1.5)
    for i in 0..<4 {
      let a = Double.pi / 4 + Double(i) * .pi / 2, r = (bO + bI) / 2, sr = (bO - bI) * 0.3
      let s = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
      ctx.fill(circle(CGPoint(x: s.x, y: s.y + 0.5), sr + 0.6), with: .color(Color(hex: 0x281905, opacity: 0.6)))
      ctx.fill(circle(s, sr), with: .radialGradient(Gradient(colors: [Color(hex: 0x6A6A6A), Color(hex: 0x1C1C1C), Color(hex: 0x050505)]),
                                                    center: CGPoint(x: s.x - sr * 0.35, y: s.y - sr * 0.4), startRadius: 0, endRadius: sr))
    }

    // everything inside the ring moves toward the listener with the cone
    let k = 1 + e * 0.04 + flutter
    let si = R * 0.71 * k
    // rubber roll
    ctx.fill(ring(c, so, si), with: .radialGradient(Gradient(stops: [.init(color: Color(hex: 0x090909), location: 0), .init(color: Color(hex: 0x2C2C2C), location: 0.42),
                                                                   .init(color: Color(hex: 0x303030), location: 0.58), .init(color: Color(hex: 0x080808), location: 1)]),
                                                    center: c, startRadius: si, endRadius: so), style: eoFill)
    grain(&ctx, ring(c, so, si), 0.24, eo: true)
    ctx.drawLayer { l in
      l.clip(to: ring(c, so, si), style: eoFill)
      l.fill(CGRect(x: c.x - so, y: c.y - so, width: so * 2, height: so * 2).path,
             with: .linearGradient(Gradient(colors: [.white.opacity(0.07), .clear, .black.opacity(0.18)]),
                                   startPoint: CGPoint(x: c.x - so, y: c.y - so), endPoint: CGPoint(x: c.x + so, y: c.y + so)))
    }
    ctx.stroke(circle(c, so), with: .color(.black.opacity(0.95)), lineWidth: 1)

    // cone: matte black, lower slope a touch lighter, paper fibre and fine pebbled grain
    let lo = (24 + e * 6) / 255, up = (54 + e * 14) / 255
    ctx.fill(circle(c, si), with: .linearGradient(Gradient(colors: [Color(white: lo), Color(white: up)]),
                                                  startPoint: CGPoint(x: c.x, y: c.y - si), endPoint: CGPoint(x: c.x, y: c.y + si)))
    do {
      var paper = ctx                                  // paper fibre, desaturated, blended into the cone
      paper.clip(to: circle(c, si))
      paper.blendMode = .overlay; paper.opacity = 0.5
      paper.addFilter(.grayscale(1)); paper.addFilter(.contrast(1.8))
      paper.draw(Image(nsImage: Texture.paper), in: CGRect(x: c.x - si, y: c.y - si, width: si * 2 * 2.3, height: si * 2 * 2.3))
    }
    grain(&ctx, circle(c, si), 0.42)                   // fine pebbled grain
    ctx.drawLayer { l in
      l.clip(to: circle(c, si))
      l.fill(CGRect(x: c.x - si, y: c.y - si, width: si * 2, height: si * 2).path,
             with: .radialGradient(Gradient(stops: [.init(color: .black.opacity(0.55), location: 0), .init(color: .black.opacity(0.15), location: 0.35),
                                                    .init(color: .clear, location: 0.9), .init(color: .black.opacity(0.5), location: 1)]),
                                   center: c, startRadius: capR * k, endRadius: si))
    }
    ctx.stroke(circle(c, si), with: .color(.black.opacity(0.95)), lineWidth: 1)
    ctx.stroke(arc(c, si - 1, 0.15, 0.85), with: .color(.white.opacity(0.1)), lineWidth: 0.5)

    // dust cap: glossy black dome, its highlight shimmers with the highs
    let dr = capR * (1 + e * 0.07 + flutter * 2)
    ctx.drawLayer { l in l.addFilter(.shadow(color: .black.opacity(0.8), radius: 3, y: 2)); l.fill(circle(c, dr), with: .color(Color(hex: 0x0C0C0C))) }
    ctx.fill(circle(c, dr), with: .radialGradient(Gradient(stops: [.init(color: Color(hex: 0x3D3D3D), location: 0), .init(color: Color(hex: 0x161616), location: 0.6),
                                                                  .init(color: Color(hex: 0x070707), location: 1)]),
                                                  center: CGPoint(x: c.x, y: c.y - dr * 0.35), startRadius: dr * 0.1, endRadius: dr))
    let h = CGPoint(x: c.x - dr * 0.18 + hi * sin(t * 61) * 0.5, y: c.y - dr * 0.5 + hi * cos(t * 53) * 0.4)
    ctx.drawLayer { l in
      l.translateBy(x: h.x, y: h.y); l.scaleBy(x: 1.5, y: 0.8)
      l.fill(circle(.zero, dr * 0.42), with: .radialGradient(Gradient(colors: [.white.opacity(0.34 + hi * 0.18 + e * 0.08), .clear]),
                                                             center: .zero, startRadius: 0, endRadius: dr * 0.42))
    }
    ctx.stroke(arc(c, dr - 1, 0.25, 0.75), with: .color(.white.opacity(0.08)), lineWidth: 1.5)
    ctx.stroke(circle(c, dr), with: .color(.black.opacity(0.9)), lineWidth: 0.75)
    ctx.stroke(arc(c, dr - 0.75, 1.1, 1.55), with: .color(.white.opacity(0.2)), lineWidth: 0.5)
  }
}

private extension CGRect { var path: Path { Path(self) } }
