//
//  Controls.swift
//  Walnut
//
//  Brass push buttons set into recesses in the panel, and knurled brass knobs.
//  Lighting follows the radio's rules: light from above, crisp edge lines, tight contact shadows.
//

import SwiftUI

/// Spun brass, as on the button faces and knob caps: concentric rings and a cross-shaped highlight.
struct SpunBrass: View {
  var body: some View {
    ZStack {
      Color(hex: 0xAA8240)
      AngularGradient(colors: [Color(hex: 0xE9CF8E), Color(hex: 0x9C7634), Color(hex: 0xDDBF7C), Color(hex: 0x8A652A),
                               Color(hex: 0xE9CF8E), Color(hex: 0x9C7634), Color(hex: 0xDDBF7C), Color(hex: 0x8A652A), Color(hex: 0xE9CF8E)],
                      center: .center, angle: .degrees(40))
        .opacity(0.85)
      RadialGradient(colors: [Color.white.opacity(0.06), .clear, Color.black.opacity(0.05), .clear],
                     center: .center, startRadius: 0, endRadius: 3).opacity(0)   // rings come from grain below
      Grain(opacity: 0.35)
      RadialGradient(colors: [Color(hex: 0xFFFAE1, opacity: 0.24), .clear], center: UnitPoint(x: 0.35, y: 0.3),
                     startRadius: 0, endRadius: 30)
    }
  }
}

/// Menu, play/pause and skip: a brass cap in a round recess cut into the walnut. It doesn't turn,
/// so its edge is smooth and polished rather than knurled.
struct RecessedBrassButton<Icon: View>: View {
  var size: CGFloat = 64
  /// Stays pushed in, like a latching radio button (menu while the browser is open, play while playing).
  var latched = false
  var action: () -> Void
  @ViewBuilder var icon: () -> Icon
  @State private var touching = false
  private var pressed: Bool { touching || latched }

  var body: some View {
    ZStack {
      // the recess: dark, top wall in shadow, lower lip catching the light
      Circle()
        .fill(RadialGradient(colors: [Color(hex: 0x1A1009), Color(hex: 0x2A1A0D), Color(hex: 0x3A2614)],
                             center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: size / 2))
        .overlay(Circle().stroke(Color.black.opacity(0.75), lineWidth: 3).blur(radius: 1.5).offset(y: 1.5).mask(Circle()))
        .overlay(Circle().stroke(Color(hex: 0x0A0500, opacity: 0.65), lineWidth: 0.5))
        .background(Circle().stroke(Color(hex: 0xFFECCD, opacity: 0.2), lineWidth: 1).offset(y: 1))
      // the cap
      SpunBrass()
        .clipShape(Circle())
        .overlay(   // polished chamfer
          Circle().strokeBorder(
            RadialGradient(colors: [Color(hex: 0xFFF6DA, opacity: 0.55), Color(hex: 0x5A3E14, opacity: 0.45)],
                           center: .center, startRadius: size * 0.36, endRadius: size * 0.43), lineWidth: size * 0.06))
        .overlay(Circle().stroke(Color(hex: 0x3C280A, opacity: 0.75), lineWidth: 0.5))
        .shadow(color: .black.opacity(pressed ? 0.7 : 0.6), radius: pressed ? 0.3 : 0.9, y: pressed ? 0.3 : 1)
        .padding(size * 0.07)
        .scaleEffect(pressed ? 0.93 : 1)
        .brightness(pressed ? -0.1 : 0)
      icon()
        .foregroundStyle(engraveBrown)
        .shadow(color: Color(hex: 0xFFF5D7, opacity: 0.85), radius: 0, y: 1)
        .frame(width: size * 0.36, height: size * 0.36)
        .scaleEffect(pressed ? 0.93 : 1)
        .opacity(pressed ? 0.85 : 1)
    }
    .frame(width: size, height: size)
    .contentShape(Circle())
    .gesture(DragGesture(minimumDistance: 0)
      .onChanged { _ in if !touching { withAnimation(.easeOut(duration: 0.07)) { touching = true } } }
      .onEnded { _ in withAnimation(.easeOut(duration: 0.07)) { touching = false }; action() })
    .animation(.easeOut(duration: 0.1), value: latched)
    .accessibilityAddTraits(.isButton)
  }
}

/// Knurled brass knob for the EQ: drag up or down, double-click to reset. -12…+12 dB.
struct BrassKnob: View {
  let label: String
  @Binding var value: Double          // dB
  var size: CGFloat = 44
  @State private var dragStart: Double?

  var body: some View {
    VStack(spacing: 5) {
      ZStack {
        // knurled rim
        Circle().fill(AngularGradient(colors: Array(repeating: [Color(hex: 0x765623), Color(hex: 0xC9AA66)], count: 45).flatMap { $0 },
                                      center: .center))
        // cap
        SpunBrass().clipShape(Circle()).padding(size * 0.12)
          .overlay(Circle().stroke(Color(hex: 0x46300A, opacity: 0.7), lineWidth: 0.5).padding(size * 0.12))
        // pointer line
        Capsule().fill(engraveBrown).frame(width: 2, height: size * 0.23)
          .shadow(color: Color(hex: 0xFFF5D7, opacity: 0.7), radius: 0, y: 1)
          .offset(y: -size * 0.24)
      }
      .rotationEffect(.degrees(value / 12 * 135))
      .frame(width: size, height: size)
      .overlay(Circle().stroke(Color(hex: 0x28190A, opacity: 0.85), lineWidth: 0.5))
      .shadow(color: Color(hex: 0x0A0500, opacity: 0.55), radius: 0.8, y: 1)
      .shadow(color: Color(hex: 0x140A00, opacity: 0.25), radius: 3, y: 2)
      .gesture(DragGesture(minimumDistance: 0)
        .onChanged { g in
          if dragStart == nil { dragStart = value }
          value = ((dragStart! - g.translation.height / 140 * 24).clamped(to: -12...12) * 2).rounded() / 2
        }
        .onEnded { _ in dragStart = nil })
      .onTapGesture(count: 2) { value = 0 }
      .help("\(label) \(value > 0 ? "+" : "")\(value.formatted()) dB")
      .accessibilityElement()
      .accessibilityLabel(label)
      .accessibilityValue("\(value.formatted()) dB")
      .accessibilityAdjustableAction { dir in value = (value + (dir == .increment ? 1 : -1)).clamped(to: -12...12) }

      Text(label.uppercased())
        .font(.system(size: 10, weight: .heavy)).kerning(1.2)
        .foregroundStyle(Color(hex: 0xD8B670))                               // inlaid brass lettering
        .shadow(color: Color(hex: 0x140802, opacity: 0.7), radius: 0, y: -1)
    }
  }
}

/// The groove between the transport buttons and the EQ knobs.
struct PanelDivider: View {
  var body: some View {
    Rectangle().fill(Color(hex: 0x140802, opacity: 0.6)).frame(width: 1)
      .overlay(Rectangle().fill(Color(hex: 0xFFE6C8, opacity: 0.16)).frame(width: 1).offset(x: 1))
      .padding(.vertical, 4)
  }
}

extension Comparable {
  func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}
