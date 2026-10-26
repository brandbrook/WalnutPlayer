//
//  SevenSegment.swift
//  Walnut
//
//  The display's seven-segment digits, with the unlit segments faintly visible like a real LCD.
//

import SwiftUI

struct SevenSegmentDisplay: View {
  /// Four characters, digits or spaces, e.g. " 1:03" as " 103".
  let digits: String
  let ink: Color
  let off: Color

  private static let segments: [Character: [CGPoint]] = [
    "a": [.init(x: 4, y: 0), .init(x: 26, y: 0), .init(x: 22, y: 5), .init(x: 8, y: 5)],
    "b": [.init(x: 27, y: 1), .init(x: 27, y: 27), .init(x: 23, y: 24), .init(x: 23, y: 6)],
    "c": [.init(x: 27, y: 29), .init(x: 27, y: 55), .init(x: 23, y: 50), .init(x: 23, y: 32)],
    "d": [.init(x: 4, y: 56), .init(x: 26, y: 56), .init(x: 22, y: 51), .init(x: 8, y: 51)],
    "e": [.init(x: 3, y: 29), .init(x: 3, y: 55), .init(x: 7, y: 50), .init(x: 7, y: 32)],
    "f": [.init(x: 3, y: 1), .init(x: 3, y: 27), .init(x: 7, y: 24), .init(x: 7, y: 6)],
    "g": [.init(x: 5, y: 28), .init(x: 9, y: 25.5), .init(x: 21, y: 25.5), .init(x: 25, y: 28), .init(x: 21, y: 30.5), .init(x: 9, y: 30.5)],
  ]
  private static let lit: [Character: String] = ["0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc",
                                                 "5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg", " ": ""]

  var body: some View {
    Canvas { ctx, size in
      let scale = size.height / 70
      ctx.scaleBy(x: scale, y: scale)
      let chars = Array(digits.padding(toLength: 4, withPad: " ", startingAt: 0))
      for (i, x) in [0.0, 34, 78, 112].enumerated() {
        let on = Self.lit[chars[i]] ?? ""
        for (name, pts) in Self.segments {
          var p = Path()
          p.addLines(pts.map { CGPoint(x: $0.x + x - 0.09 * ($0.y - 28), y: $0.y + 6) })   // slight italic, like the mockup
          p.closeSubpath()
          ctx.fill(p, with: .color(on.contains(name) ? ink : off))
        }
      }
      for y in [22.0, 42.0] {   // colon
        ctx.fill(Path(roundedRect: CGRect(x: 66, y: y, width: 5, height: 5), cornerRadius: 1), with: .color(ink))
      }
    }
    .aspectRatio(150 / 70, contentMode: .fit)
  }
}
