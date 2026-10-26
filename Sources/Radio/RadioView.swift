//
//  RadioView.swift
//  Walnut
//
//  The whole radio: walnut cabinet with feet, the lighter recessed panel, the speaker, the
//  brass-framed display, recessed brass buttons and the EQ knobs.
//

import SwiftUI

struct RadioView: View {
  @ObservedObject var model: RadioModel
  @State private var hovering = false

  var body: some View {
    VStack(spacing: 0) {
      cabinet
      feet
    }
    .onHover { hovering = $0 }
  }

  // MARK: Cabinet

  private var cabinet: some View {
    let shape = RoundedRectangle(cornerRadius: u(Radio.cabinetRadius), style: .continuous)
    return ZStack {
      WindowDragArea()                  // dragging the outer frame moves the window
      FrameWalnut().allowsHitTesting(false)
        .overlay(alignment: .bottom) {   // the edge rolling under: a narrow band of shade, thin dark line
          LinearGradient(colors: [.clear, Color(hex: 0x1E0C04, opacity: 0.45)], startPoint: .top, endPoint: .bottom).frame(height: u(5))
        }
      cornerGlints
      front.padding(u(Radio.cabinetPadding))
    }
    .frame(width: u(Radio.size.width), height: u(Radio.size.height))
    // close and minimise: an overlay sized to the buttons only, so it doesn't swallow clicks on the wood
    .overlay(alignment: .topLeading) { TrafficLights(visible: hovering).padding(.top, u(7)).padding(.leading, u(14)) }
    .clipShape(shape)
    .overlay(shape.stroke(Color(hex: 0x140A03, opacity: 0.85), lineWidth: 0.5))
    .overlay(alignment: .bottom) { shape.stroke(Color(hex: 0x140802, opacity: 0.75), lineWidth: 1).mask(Rectangle().frame(height: u(8))) }
    // the slab's front face below the edge, then the desk
    .background(shape.fill(Color(hex: 0x4A2613)).offset(y: u(6)).overlay(shape.stroke(Color(hex: 0x140A03, opacity: 0.85), lineWidth: 0.5).offset(y: u(6))))
  }

  /// One small glint on the top-left corner, a tinier one top-right; nothing else.
  private var cornerGlints: some View {
    ZStack(alignment: .top) {
      Ellipse().fill(RadialGradient(colors: [Color(hex: 0xFFF2E0, opacity: 0.45), .clear], center: .center, startRadius: 0, endRadius: u(19)))
        .frame(width: u(38), height: u(8)).rotationEffect(.degrees(-45))
        .offset(x: u(-7), y: u(10)).frame(maxWidth: .infinity, alignment: .leading)
      Ellipse().fill(RadialGradient(colors: [Color(hex: 0xFFF2E0, opacity: 0.28), .clear], center: .center, startRadius: 0, endRadius: u(10)))
        .frame(width: u(20), height: u(5)).rotationEffect(.degrees(45))
        .offset(x: u(3), y: u(11)).frame(maxWidth: .infinity, alignment: .trailing)
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .allowsHitTesting(false)
  }

  private var feet: some View {
    HStack {
      foot; Spacer(); foot
    }
    .frame(width: u(Radio.size.width) * 0.9)
    .padding(.top, u(5))
  }

  private var foot: some View {
    UnevenRoundedRectangleShape(bottomRadius: u(4))
      .fill(LinearGradient(colors: [Color(hex: 0x2A170B), Color(hex: 0x1B0E06)], startPoint: .top, endPoint: .bottom))
      .frame(width: u(64), height: u(7))
  }

  // MARK: Front panel

  private var front: some View {
    let shape = RoundedRectangle(cornerRadius: u(Radio.panelRadius))
    return HStack(spacing: 0) {
      SpeakerView(playing: model.isPlaying)
        .frame(width: u(720) * 0.37)
      face
    }
    .background(ZStack { WindowDragArea(); PanelWalnut().allowsHitTesting(false) })   // and so does the wood panel
    .clipShape(shape)
    // the cabinet's top lip shades the panel; its bottom edge catches the light
    .overlay(shape.stroke(Color(hex: 0x0A0500, opacity: 0.55), lineWidth: 3).blur(radius: 1.5).offset(y: 1.5).clipShape(shape))
    .overlay(LinearGradient(colors: [Color(hex: 0x0A0500, opacity: 0.32), .clear], startPoint: .top, endPoint: .bottom)
               .frame(height: u(8)).frame(maxHeight: .infinity, alignment: .top).clipShape(shape).allowsHitTesting(false))
    .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xFFECCD, opacity: 0.22)).frame(height: 1).padding(.horizontal, u(16)) }
    .overlay(shape.stroke(Color(hex: 0x0A0500, opacity: 0.75), lineWidth: 0.5))
  }

  private var face: some View {
    VStack(spacing: u(16)) {
      DisplayView(model: model)
        .padding(u(7))
        .background(BrushedBrass().clipShape(RoundedRectangle(cornerRadius: u(10))))
        .overlay(RoundedRectangle(cornerRadius: u(10)).stroke(Color(hex: 0x32200A, opacity: 0.6), lineWidth: 0.5))
        .overlay(RoundedRectangle(cornerRadius: u(10)).trim(from: 0.5, to: 1).stroke(Color(hex: 0xFFF0C8, opacity: 0.55), lineWidth: 0.5).padding(0.5).rotationEffect(.degrees(0)))
        .shadow(color: Color(hex: 0x0A0500, opacity: 0.55), radius: 0.5, y: 1.5)
        .shadow(color: Color(hex: 0x1E0F00, opacity: 0.3), radius: 3, y: u(5))
      controls
    }
    .padding(EdgeInsets(top: u(18), leading: u(8), bottom: u(16), trailing: u(20)))
  }

  private var controls: some View {
    HStack(spacing: 0) {
      HStack(spacing: u(20)) {
        RecessedBrassButton(size: u(64), action: { model.back() }) {
          Image(systemName: "line.3.horizontal").resizable().aspectRatio(contentMode: .fit)
        }
        .help("Stations")
        RecessedBrassButton(size: u(64), action: playButton) {
          Image(systemName: model.isPlaying && model.mode == .nowPlaying ? "pause.fill" : "play.fill").resizable().aspectRatio(contentMode: .fit)
        }
        .help("Play / Pause")
        RecessedBrassButton(size: u(64), action: skipButton) {
          Image(systemName: "forward.end.fill").resizable().aspectRatio(contentMode: .fit)
        }
        .help("Next song")
      }
      Spacer(minLength: 0)
      PanelDivider()
      Spacer(minLength: 0)
      HStack(spacing: u(14)) {
        BrassKnob(label: "Low", value: $model.eqLow, size: u(44))
        BrassKnob(label: "Mid", value: $model.eqMid, size: u(44))
        BrassKnob(label: "High", value: $model.eqHigh, size: u(44))
      }
    }
    .frame(height: u(64))
  }

  /// Play plays and pauses; in the station browser and its screens it chooses (history keeps playing/pausing).
  private func playButton() {
    switch model.mode {
    case .nowPlaying, .history: model.playPause()
    case .login: model.logIn()
    case .loading: break
    default: model.choose()
    }
  }
  /// Skip skips the song; in a list it moves the selection along.
  private func skipButton() {
    switch model.mode {
    case .nowPlaying: model.next()
    case .stations, .history, .newStation: model.move(1)
    default: break
    }
  }
}

/// Close and minimise, shown on hover, drawn like small enamel buttons on the wood.
private struct TrafficLights: View {
  let visible: Bool
  @State private var over = false
  var body: some View {
    HStack(spacing: u(7)) {
      light(Color(hex: 0xFF5F57), symbol: "xmark") { NSApp.keyWindow?.orderOut(nil) }
      light(Color(hex: 0xFEBC2E), symbol: "minus") { NSApp.keyWindow?.miniaturize(nil) }
    }
    .opacity(visible ? 1 : 0)
    .animation(.easeOut(duration: 0.15), value: visible)
    .onHover { over = $0 }
  }
  private func light(_ color: Color, symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Circle().fill(color).frame(width: 12, height: 12)
        .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.5))
        .overlay(Image(systemName: symbol).font(.system(size: 7, weight: .black)).foregroundStyle(.black.opacity(over ? 0.55 : 0)))
    }
    .buttonStyle(.plain)
  }
}

/// Lets the user drag the window by the wood.
struct WindowDragArea: NSViewRepresentable {
  /// Moves the window by hand while the mouse is dragged; a plain click is left to AppKit, which
  /// brings Walnut forward as usual.
  final class DragView: NSView {
    private var grab: NSPoint?          // where in the window the mouse went down
    override func mouseDown(with event: NSEvent) { grab = event.locationInWindow }
    override func mouseDragged(with event: NSEvent) {
      guard let grab, let window else { return }
      let mouse = NSEvent.mouseLocation
      window.setFrameOrigin(NSPoint(x: mouse.x - grab.x, y: mouse.y - grab.y))
    }
    override func mouseUp(with event: NSEvent) { grab = nil; window?.saveFrame(usingName: "WalnutRadio") }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
  }
  func makeNSView(context: Context) -> NSView { DragView() }
  func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Rectangle with only its bottom corners rounded (UnevenRoundedRectangle needs macOS 13).
struct UnevenRoundedRectangleShape: Shape {
  let bottomRadius: CGFloat
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: r.minX, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bottomRadius))
    p.addQuadCurve(to: CGPoint(x: r.maxX - bottomRadius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
    p.addLine(to: CGPoint(x: r.minX + bottomRadius, y: r.maxY))
    p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - bottomRadius), control: CGPoint(x: r.minX, y: r.maxY))
    p.closeSubpath()
    return p
  }
}
