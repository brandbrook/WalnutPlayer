//
//  DisplayView.swift
//  Walnut
//
//  The display behind the brass frame. Now playing: art, seven-segment timer, station and song,
//  with the appearance strip on top and the song actions below. The menu button turns the whole
//  display into the station browser (stations and history in sideways columns, new, edit, delete).
//

import SwiftUI

struct DisplayView: View {
  @ObservedObject var model: RadioModel
  @Environment(\.colorScheme) private var systemScheme

  private var style: GlassStyle {
    let dark: Bool
    switch model.theme {
    case .light: dark = false
    case .dark: dark = true
    case .system: dark = systemScheme == .dark
    }
    if !dark { return model.isPlaying ? .lightPlaying : .light }
    return model.isPlaying ? .darkPlaying : .dark   // navy glass while music plays, warm brown when not
  }
  private var dim: Bool { model.mode == .nowPlaying && !model.isPlaying }

  var body: some View {
    ZStack {
      if style.vertical {
        LinearGradient(colors: style.glass, startPoint: .top, endPoint: .bottom)
      } else {
        RadialGradient(colors: style.glass, center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: u(380))
      }
      VStack(spacing: u(7)) {
        if model.mode != .nowPlaying { topStrip }       // now playing lays out its own top row
        if model.mode == .stations { TunerScale(model: model, style: style) }
        content.frame(maxWidth: .infinity, maxHeight: .infinity)
        if model.mode != .nowPlaying { bottomStrip }   // now playing has no action strip
      }
      .padding(u(7))
      .foregroundStyle(style.ink)
      .shadow(color: style.glow, radius: style.glow == .clear ? 0 : 3)
      // glass glare
      LinearGradient(colors: [.white.opacity(style.glare), .clear], startPoint: .topTrailing, endPoint: UnitPoint(x: 0.45, y: 0.55))
        .rotationEffect(.degrees(-10)).scaleEffect(1.4).allowsHitTesting(false)
    }
    // set behind the brass: the frame's top lip throws a shadow down onto the glass, a little on the
    // left too, and a fine dark line marks where the glass meets the brass
    .overlay(alignment: .top) {
      LinearGradient(colors: [Color(hex: 0x5A3812, opacity: 0.26), Color(hex: 0x7A5420, opacity: 0.07), .clear], startPoint: .top, endPoint: .bottom)
        .frame(height: u(12)).allowsHitTesting(false)   // warm, so it doesn't read as a grey strip
    }
    .clipShape(RoundedRectangle(cornerRadius: u(5)))
    .overlay(RoundedRectangle(cornerRadius: u(5)).stroke(Color(hex: 0x2A1A04, opacity: 0.45), lineWidth: 1))
    .saturation(dim ? (style.glare > 0.3 ? 0.8 : 0.7) : 1)
    .brightness(dim ? (style.glare > 0.3 ? -0.03 : 0) : 0)   // dark mode: the brown glass already reads as off
    // a short fade when playback pauses or resumes; switching screens is instant
    .animation(.easeInOut(duration: 0.25), value: model.isPlaying)   // only play/pause fades
  }

  // MARK: Strips

  private var topStrip: some View {
    Strip(style: style) {
      switch model.mode {
      case .nowPlaying, .loading, .login:
        if model.mode == .nowPlaying { StationBadge(model: model, style: style) }
        Spacer()
        ForEach(DisplayTheme.allCases, id: \.self) { t in
          ThemeButton(theme: t, lit: model.theme == t, style: style) { model.theme = t }
        }
      case .stations, .history:
        StripButton("STATIONS", lit: model.mode == .stations, style: style) { model.showBrowser(.stations) }
        StripButton("HISTORY", lit: model.mode == .history, style: style) { model.showBrowser(.history) }
        Spacer()
        if model.mode == .stations {
          StripButton("A–Z", lit: !model.sortByNewest, style: style) { model.sortByNewest = false; model.showBrowser(.stations) }
          StripButton("NEWEST", lit: model.sortByNewest, style: style) { model.sortByNewest = true; model.showBrowser(.stations) }
        } else {
          StripLabel("\(model.history.count) SONGS", style: style)
        }
      case .newStation:
        StripLabel("NEW STATION", style: style, lit: true); Spacer()
        StripButton("CANCEL", style: style) { model.back() }
      case .editStation(let token):
        StripLabel("EDIT · \(model.nameOfStation(token).uppercased())", style: style, lit: true); Spacer()
        StripButton("CANCEL", style: style) { model.back() }
      case .deleteStation:
        StripLabel("DELETE STATION", style: style, lit: true); Spacer()
        StripButton("CANCEL", style: style) { model.back() }
      }
    }
  }

  private var bottomStrip: some View {
    Strip(style: style, spread: true) {
      switch model.mode {
      case .nowPlaying:
        EmptyView()   // like and dislike sit beside the time; skip is the brass button
      case .login:
        StripButton("CREATE ACCOUNT", style: style, bright: true) {
          NSWorkspace.shared.open(URL(string: "https://www.pandora.com/account/register")!)
        }
        StripButton("LOG IN", lit: true, style: style) { model.logIn() }
      case .loading:
        StripLabel(" ", style: style)
      case .stations:
        let item = model.sortedStations.indices.contains(model.selection) ? model.sortedStations[model.selection] : nil
        StripButton("+ NEW", style: style, bright: true) { model.beginNewStation() }
        StripButton("EDIT", style: style, bright: true, disabled: !(item?.canEdit ?? false)) { model.beginEdit(model.selection) }
        StripButton("DELETE", style: style, bright: true, disabled: !(item?.canEdit ?? false)) { model.beginDelete(model.selection) }
        // always active: on another station it tunes in, on the current one it resumes playback
        StripButton("▶ TUNE IN", lit: item != nil, style: style, bright: true, disabled: item == nil) { model.tune(model.selection) }
      case .history:
        let item = model.history.indices.contains(model.selection) ? model.history[model.selection] : nil
        StripButton("DISLIKE", icon: "hand.thumbsdown.fill", lit: item?.rating == -1, style: style, bright: true, disabled: item == nil) {
          model.toggleHistoryRating(model.selection, like: false) }
        StripButton("LIKE", icon: "hand.thumbsup.fill", lit: item?.rating == 1, litColor: accentRed, style: style, bright: true, disabled: item == nil) {
          model.toggleHistoryRating(model.selection, like: true) }
      case .newStation:
        StripButton("CANCEL", style: style, bright: true) { model.back() }
        StripButton("▶ CREATE STATION", style: style, bright: true, disabled: model.results.isEmpty) { model.createStation(model.selection) }
      case .editStation:
        StripButton("CANCEL", style: style, bright: true) { model.back() }
        StripButton("SAVE", style: style, bright: true) { model.saveEdit() }
      case .deleteStation(let token):
        StripButton("CANCEL", style: style, bright: true) { model.back() }
        StripButton("DELETE", lit: true, litColor: accentRed, style: style) { model.confirmDelete(token) }
      }
    }
  }

  // MARK: Content

  @ViewBuilder private var content: some View {
    switch model.mode {
    case .nowPlaying: NowPlayingView(model: model, style: style)
    case .loading(let text):
      Text(text == RadioModel.noSignal ? text : text + "…").font(.system(size: u(13), weight: .bold)).kerning(u(2)).foregroundStyle(style.inkDim)
    case .login: LoginView(model: model, style: style)
    case .stations, .history:
      if model.browserItems == 0 {
        Hint(model.mode == .history ? "Songs you play show up here." : "No stations yet. Press + NEW to make one.", style: style)
      } else {
        BrowserGrid(model: model, style: style, rows: 4)
      }
    case .newStation:
      VStack(spacing: u(6)) {
        Field(label: "SEARCH", style: style) {
          GlassTextField(placeholder: "Artist, song or genre", text: Binding(get: { model.query }, set: { model.search($0) }),
                         style: style, focus: true) { model.createStation(model.selection) }
        }
        if model.query.trimmingCharacters(in: .whitespaces).isEmpty {
          Hint("Type an artist, song or genre. Pandora builds a station around it.", style: style)
        } else if model.results.isEmpty {
          Hint("Searching…", style: style)
        } else {
          BrowserGrid(model: model, style: style, rows: 4)
        }
      }
    case .editStation: EditStationView(model: model, style: style)
    case .deleteStation(let token):
      VStack(spacing: u(4)) {
        (Text("Delete ") + Text(model.nameOfStation(token)).bold() + Text("?")).font(.system(size: u(15)))
        Text("This also removes it from your Pandora account.").font(.system(size: u(11))).foregroundStyle(style.inkDim)
      }
    }
  }
}

// MARK: - Now playing

private struct NowPlayingView: View {
  @ObservedObject var model: RadioModel
  let style: GlassStyle

  var body: some View {
    HStack(alignment: .top, spacing: u(20)) {
      // left: the art, with the time centred under it
      VStack(spacing: u(17)) {
        AlbumArt(image: model.art, style: style).frame(width: u(96), height: u(96))
        HStack(alignment: .bottom, spacing: u(4)) {
          SevenSegmentDisplay(digits: timeDigits, ink: style.ink, off: style.inkOff)
            .frame(height: u(25))
            .shadow(color: style.glow, radius: style.glow == .clear ? 0 : 3)
            .fixedSize()
          VStack(alignment: .leading, spacing: u(2)) {
            Text("MIN").kerning(u(0.5)); Text("SEC").kerning(u(0.5))
          }
          .font(.system(size: u(8)))
          .foregroundStyle(model.isPlaying ? style.inkDim : style.inkOff)
        }
        .offset(y: u(3.9))   // centred on the action bar beside it (bar 24 tall at the column's bottom)
      }
      // right: station and appearance on top, the song in the middle, ratings at the bottom
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: u(4)) {
          StationBadge(model: model, style: style)
          Spacer(minLength: u(8))
          ForEach(DisplayTheme.allCases, id: \.self) { t in
            ThemeButton(theme: t, lit: model.theme == t, style: style) { model.theme = t }
          }
        }
        // the song, artist and album as one group, centred between the station and the bar
        Spacer(minLength: u(4))
        VStack(alignment: .leading, spacing: u(6)) {
          InfoLine(text: model.title, link: model.link(for: .track), strong: true, style: style) {
            SpinningRecord(playing: model.isPlaying, style: style)
          }
          InfoLine(text: model.artist, link: model.link(for: .artist), style: style) {
            Image(systemName: "person.fill").font(.system(size: u(11.5)))
          }
          InfoLine(text: model.album, link: model.link(for: .album), style: style) {
            Image(systemName: "rectangle.stack.fill").font(.system(size: u(11.5)))
          }
        }
        Spacer(minLength: u(4))
        // the song's actions, under the info only, level with the time
        Strip(style: style, spread: true) {
          StripButton("DISLIKE", icon: "hand.thumbsdown.fill", lit: model.flash == "dislike", style: style) { model.dislike() }
          StripButton("TIRED", icon: "moon.fill", lit: model.flash == "tired", style: style) { model.tired() }
          StripButton("LIKE", icon: "hand.thumbsup.fill", lit: model.rating == 1, litColor: accentRed, style: style) { model.like() }
        }
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .frame(height: u(96 + 17 + 25) + u(2))         // same height as the art and time, so the rows line up
    }
    .padding(.horizontal, u(4))
    .frame(maxHeight: .infinity)                   // centred in the display
  }

  /// Four digits, the unused leading one faintly visible like a real LCD.
  private var timeDigits: String {
    let s = Int(model.elapsed), m = (s / 60) % 100
    return (m < 10 ? " \(m)" : "\(m)") + String(format: "%02d", s % 60)
  }
}

/// In the top strip: a radio-station icon and the station's name; clicking it opens the station picker.
private struct StationBadge: View {
  @ObservedObject var model: RadioModel
  let style: GlassStyle
  var body: some View {
    HStack(spacing: u(7)) {
      Image(systemName: "radio.fill").font(.system(size: u(11.5)))
        .foregroundStyle(style.inkDim).frame(width: u(15), height: u(15))
      Text(model.stationName.isEmpty ? "Walnut" : model.stationName)
        .font(.system(size: u(13.5))).foregroundStyle(style.inkDim)
        .lineLimit(1).truncationMode(.tail)
    }
    .contentShape(Rectangle())
    .pointingHand()
    .onTapGesture { model.showBrowser(.stations) }          // opens the station picker
    .help("Choose a station")
  }
}

/// One line of song info with its icon. Clicking it opens the link (Pandora's page, or a web search).
private struct InfoLine<Icon: View>: View {
  let text: String
  let link: URL?
  var strong = false
  let style: GlassStyle
  @ViewBuilder var icon: () -> Icon
  @State private var hover = false

  var body: some View {
    HStack(spacing: u(7)) {
      icon().foregroundStyle(style.inkDim).frame(width: u(15), height: u(15))
      Text(text.isEmpty ? " " : text)
        .font(.system(size: u(13.5), weight: strong ? .semibold : .regular))   // same size; only the song is bold
        .foregroundStyle(style.inkDim)
        .lineLimit(1).truncationMode(.tail)
    }
    .contentShape(Rectangle())
    .pointingHand(link != nil)
    .onTapGesture { if let link { NSWorkspace.shared.open(link) } }
    .help(link == nil ? "" : "Open “\(text)”")
  }
}

/// A small record that turns slowly while music plays.
private struct SpinningRecord: View {
  let playing: Bool
  let style: GlassStyle
  @State private var angle = 0.0
  @State private var last = Date()

  var body: some View {
    TimelineView(.animation(paused: !playing)) { t in
      Canvas { ctx, size in
        let r = min(size.width, size.height) / 2, c = CGPoint(x: size.width / 2, y: size.height / 2)
        func circle(_ rr: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)) }
        // one colour, like the other icons: a solid disc with the label and grooves cut out of it
        ctx.fill(circle(r), with: .color(style.inkDim))
        do {
          var l = ctx                                                              // cut into the disc itself
          l.blendMode = .destinationOut
          for g in stride(from: r * 0.55, to: r * 0.95, by: r * 0.17) { l.stroke(circle(g), with: .color(.black.opacity(0.5)), lineWidth: 0.5) }
          l.stroke(circle(r * 0.34), with: .color(.black), lineWidth: 0.9)
          l.fill(circle(r * 0.09), with: .color(.black))                            // spindle hole
        }
        // a sheen across the grooves, so the turning is visible
        let a = angle(at: t.date)
        var sheen = Path()
        sheen.move(to: c)
        sheen.addArc(center: c, radius: r * 0.95, startAngle: .radians(a), endAngle: .radians(a + 0.6), clockwise: false)
        sheen.closeSubpath()
        var cut = ctx; cut.blendMode = .destinationOut; cut.fill(sheen, with: .color(.black.opacity(0.4)))
      }
    }
  }

  /// About one turn every 4 seconds while playing; holds still when paused.
  private func angle(at date: Date) -> Double {
    let dt = date.timeIntervalSince(last)
    DispatchQueue.main.async { last = date; if playing { angle += dt * .pi / 2 } }
    return angle + (playing ? dt * .pi / 2 : 0)
  }
}

private struct AlbumArt: View {
  let image: NSImage?
  let style: GlassStyle
  var body: some View {
    ZStack {
      if let image {
        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
          .saturation(0.9).colorMultiply(Color(hex: 0xFFF1D8))
      } else {
        style.stripBackground
        Image(systemName: "music.note").font(.system(size: u(26))).foregroundStyle(style.inkOff)
      }
      LinearGradient(colors: [Color(hex: 0xFFE6AA, opacity: 0.18), Color(hex: 0x78460A, opacity: 0.12)], startPoint: .top, endPoint: .bottom)
    }
    .clipShape(RoundedRectangle(cornerRadius: u(10), style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: u(10), style: .continuous).stroke(Color(hex: 0x3C2305, opacity: 0.35), lineWidth: 0.5))
    .shadow(color: Color(hex: 0x3C2305, opacity: 0.12), radius: 0.6, y: 0.5)   // just an edge, not a tile on the glass
  }
}


// MARK: - Login

private struct LoginView: View {
  @ObservedObject var model: RadioModel
  let style: GlassStyle
  var body: some View {
    VStack(spacing: u(8)) {
      Field(label: "EMAIL", style: style) {
        GlassTextField(placeholder: "Pandora email", text: $model.username, style: style, focus: model.username.isEmpty) { model.logIn() }
      }
      Field(label: "PASSWORD", style: style) {
        GlassTextField(placeholder: "Password", text: $model.password, style: style, secure: true, focus: !model.username.isEmpty) { model.logIn() }
      }
      if let error = model.loginError {          // only shown when something went wrong, under the fields
        Text(error).font(.system(size: u(10.5), weight: .bold)).kerning(u(1.2)).foregroundStyle(accentRed)
          .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, u(90))
      }
    }
    .padding(.horizontal, u(6))
  }
}

// MARK: - Edit station

private struct EditStationView: View {
  @ObservedObject var model: RadioModel
  let style: GlassStyle
  var body: some View {
    VStack(alignment: .leading, spacing: u(6)) {
      Field(label: "NAME", style: style) {
        GlassTextField(placeholder: "Station name", text: $model.draftName, style: style, focus: true) { model.saveEdit() }
      }
      Field(label: "BASED ON", style: style) {
        HStack(spacing: u(5)) {
          ForEach(model.draftSeeds.prefix(3)) { seed in
            HStack(spacing: u(2)) {
              Text(seed.name).lineLimit(1)
              Button { model.removeSeed(seed) } label: { Text("×") }.buttonStyle(.plain).foregroundStyle(style.inkDim).pointingHand()
                .disabled(model.draftSeeds.count < 2)
            }
            .font(.system(size: u(11)))
            .padding(.leading, u(7)).padding(.trailing, u(4)).padding(.vertical, u(1))
            .overlay(Capsule().stroke(style.inkDim, lineWidth: 1))
          }
          if model.draftSeeds.count > 3 { Text("+\(model.draftSeeds.count - 3)").font(.system(size: u(11))).foregroundStyle(style.inkDim) }
          GlassTextField(placeholder: "+ Add artist or song", text: Binding(get: { model.seedQuery }, set: { model.searchSeeds($0) }),
                         style: style, focus: false) { if let first = model.seedResults.first { model.addSeed(first) } }
        }
      }
      if !model.seedResults.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: u(6)) {
            ForEach(model.seedResults) { r in
              Button { model.addSeed(r) } label: {
                Text("+ \(r.name)\(r.detail.map { " · \($0)" } ?? "")").font(.system(size: u(11))).lineLimit(1)
                  .padding(.horizontal, u(7)).padding(.vertical, u(2))
                  .background(Capsule().fill(style.stripBackground))
              }.buttonStyle(.plain).pointingHand()
            }
          }
        }
      }
    }
    .padding(.horizontal, u(2))
  }
}

// MARK: - Browser grid (sideways-scrolling columns)

private struct BrowserGrid: View {
  @ObservedObject var model: RadioModel
  let style: GlassStyle
  let rows: Int

  var body: some View {
    GeometryReader { geo in
      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {   // the tuning needle shows where you are
          LazyHGrid(rows: Array(repeating: GridItem(.flexible(), spacing: u(1)), count: rows), spacing: u(16)) {
            ForEach(0..<count, id: \.self) { i in
              cell(i)
                .frame(width: (geo.size.width - u(16)) / 2)
                .id(i)
                .contentShape(Rectangle())
                .pointingHand()
                .onTapGesture {
                  // stations: a click only selects (TUNE IN plays it); new-station results: a second click creates
                  if model.selection == i && model.mode == .newStation { model.choose() } else { model.selection = i }
                }
            }
          }
          .frame(height: geo.size.height - u(4))
        }
        .onChange(of: model.selection) { i in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(i) } }
        .onAppear { proxy.scrollTo(model.selection) }
      }
    }
  }

  private var count: Int {
    switch model.mode {
    case .stations: return model.sortedStations.count
    case .history: return model.history.count
    default: return model.results.count
    }
  }

  @ViewBuilder private func cell(_ i: Int) -> some View {
    let selected = i == model.selection
    HStack(spacing: u(8)) {
      switch model.mode {
      case .stations:
        let st = model.sortedStations[i]
        Group {
          if st.isShuffle { Image(systemName: "shuffle").font(.system(size: u(10))) }
          else { Text(String(format: "%02d", i)).font(.system(size: u(10), weight: .semibold, design: .monospaced)) }
        }
        .foregroundStyle(selected ? style.selectedText.opacity(0.75) : style.inkDim).frame(width: u(16))
        Text(st.isShuffle ? "Shuffle" : st.name).lineLimit(1)
        Spacer(minLength: 0)
        if st.id == model.currentToken { Circle().fill(accentRed).frame(width: u(6), height: u(6)) }
      case .history:
        let h = model.history[i]
        (Text(h.title) + Text(" · \(h.artist)").foregroundColor(selected ? style.selectedText.opacity(0.75) : style.inkDim)).lineLimit(1)
        Spacer(minLength: 0)
        if i == 0 && model.isPlaying { Text("NOW").font(.system(size: u(8), weight: .bold)).kerning(u(1)).foregroundStyle(accentRed) }
        if h.rating == 1 { Image(systemName: "hand.thumbsup.fill").font(.system(size: u(9))).foregroundStyle(accentRed) }
        if h.rating == -1 { Image(systemName: "hand.thumbsdown.fill").font(.system(size: u(9))) }
      default:
        let r = model.results[i]
        (Text(r.name) + Text(r.detail.map { " · \($0)" } ?? "").foregroundColor(selected ? style.selectedText.opacity(0.75) : style.inkDim)).lineLimit(1)
        Spacer(minLength: 0)
        Text(r.kind.rawValue).font(.system(size: u(8.5), weight: .bold)).kerning(u(1)).foregroundStyle(selected ? style.selectedText.opacity(0.75) : style.inkDim)
      }
    }
    .font(.system(size: u(13)))
    .padding(.horizontal, u(7))
    .frame(maxHeight: .infinity)
    .foregroundStyle(selected ? style.selectedText : style.ink)
    .background(RoundedRectangle(cornerRadius: 2).fill(selected ? style.ink : .clear))
    .shadow(radius: 0)
  }
}

/// Tuning scale with a red needle at the selected station. Drag it like a tuning knob: the selection
/// follows the needle and letting go snaps onto that station; TUNE IN then plays it.
private struct TunerScale: View {
  @ObservedObject var model: RadioModel
  let style: GlassStyle
  @State private var dragFraction: Double?

  var body: some View {
    GeometryReader { geo in
      let n = max(model.browserItems, 1)
      let f = dragFraction ?? (n > 1 ? Double(model.selection) / Double(n - 1) : 0.5)
      ZStack(alignment: .bottomLeading) {
        Canvas { ctx, size in
          ctx.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)), with: .color(style.inkDim))
          var x = 0.0
          while x <= size.width {
            ctx.fill(Path(CGRect(x: x, y: size.height - u(5), width: 1, height: u(5))), with: .color(style.inkDim))
            x += u(8)
          }
          x = 0
          while x <= size.width {
            ctx.fill(Path(CGRect(x: x, y: size.height - u(9), width: 1, height: u(9))), with: .color(style.ink))
            x += u(48)
          }
        }
        .shadow(color: style.glow, radius: style.glow == .clear ? 0 : 2)
        Capsule().fill(Color(hex: 0xFF4A2A))
          .frame(width: 2, height: u(18))
          .shadow(color: Color(hex: 0xFF5028, opacity: 0.75), radius: 3)
          .offset(x: geo.size.width * f - 1, y: u(2))
          .animation(dragFraction == nil ? .spring(response: 0.35, dampingFraction: 0.8) : nil, value: f)
      }
      .contentShape(Rectangle().inset(by: -u(8)))
      .gesture(DragGesture(minimumDistance: 0)
        .onChanged { g in
          let fr = (g.location.x / geo.size.width).clamped(to: 0...1)
          dragFraction = fr
          model.selection = Int((fr * Double(n - 1)).rounded())
        }
        .onEnded { _ in dragFraction = nil })   // snaps onto the station; TUNE IN plays it
    }
    .frame(height: u(13))
    .padding(.horizontal, u(10))
    .padding(.bottom, u(9))   // as much room below the scale as above it
  }
}

// MARK: - Small parts

private struct Strip<Content: View>: View {
  let style: GlassStyle
  var plain = false               // no band behind it (the top strip)
  var spread = false
  @ViewBuilder var content: () -> Content
  var body: some View {
    HStack(spacing: u(2)) { content() }
    .environment(\.stripSpread, spread)
    .frame(height: u(24))
    .padding(.leading, u(9)).padding(.trailing, u(6))
    .frame(maxWidth: .infinity)
    .background(RoundedRectangle(cornerRadius: u(3)).fill(plain ? .clear : style.stripBackground))
    .overlay(RoundedRectangle(cornerRadius: u(3)).stroke(plain ? .clear : style.stripLine, lineWidth: 0.5))
  }
}

private struct StripLabel: View {
  let text: String
  let style: GlassStyle
  var lit = false
  init(_ text: String, style: GlassStyle, lit: Bool = false) { self.text = text; self.style = style; self.lit = lit }
  var body: some View {
    Text(text).font(.system(size: u(10.5), weight: .bold)).kerning(u(1.2)).lineLimit(1)
      .foregroundStyle(lit ? style.ink : style.inkDim.opacity(0.55))
  }
}

private struct StripButton: View {
  let title: String
  var icon: String? = nil
  var lit = false
  var litColor: Color? = nil
  let style: GlassStyle
  var bright = false
  var disabled = false
  let action: () -> Void
  @State private var hover = false
  @Environment(\.stripSpread) private var spread

  init(_ title: String, icon: String? = nil, lit: Bool = false, litColor: Color? = nil, style: GlassStyle,
       bright: Bool = false, disabled: Bool = false, action: @escaping () -> Void) {
    self.title = title; self.icon = icon; self.lit = lit; self.litColor = litColor; self.style = style
    self.bright = bright; self.disabled = disabled; self.action = action
  }

  var body: some View {
    Button(action: { if !disabled { action() } }) {
      HStack(spacing: u(5)) {
        if let icon { Image(systemName: icon).font(.system(size: u(10.5))) }
        Text(title).font(.system(size: u(10.5), weight: .bold)).kerning(u(1.2)).lineLimit(1)
      }
      .padding(.horizontal, u(6)).padding(.vertical, u(4))
      .contentShape(Rectangle())
      .foregroundStyle(lit ? (litColor ?? style.ink) : style.inkDim)
      .opacity(disabled ? 0.42 : lit ? 1 : hover ? 0.85 : (bright ? 0.78 : 0.42))   // unavailable: faded like an unlit option
    }
    .buttonStyle(.plain)
    .focusable(false)
    .pointingHand(!disabled)
    .frame(maxWidth: spread ? .infinity : nil)   // bottom strip: actions spread evenly across
    .onHover { hover = $0 }
    .animation(.easeOut(duration: 0.15), value: lit)
  }
}

private struct Field<Content: View>: View {
  let label: String
  let style: GlassStyle
  @ViewBuilder var content: () -> Content
  var body: some View {
    HStack(spacing: u(10)) {
      Text(label).font(.system(size: u(10.5), weight: .bold)).kerning(u(1.2)).foregroundStyle(style.inkDim).lineLimit(1).fixedSize().frame(width: u(80), alignment: .leading)
      content()
    }
    .frame(minHeight: u(26))
  }
}

private struct Hint: View {
  let text: String
  let style: GlassStyle
  init(_ text: String, style: GlassStyle) { self.text = text; self.style = style }
  var body: some View { Text(text).font(.system(size: u(11))).foregroundStyle(style.inkDim).frame(maxHeight: .infinity) }
}

/// A text field drawn as part of the glass: no box, an underline, the display's ink.
private struct GlassTextField: View {
  let placeholder: String
  @Binding var text: String
  let style: GlassStyle
  var secure = false
  var focus = false
  var onSubmit: () -> Void = {}
  @FocusState private var focused: Bool

  init(placeholder: String, text: Binding<String>, style: GlassStyle, secure: Bool = false, focus: Bool, onSubmit: @escaping () -> Void = {}) {
    self.placeholder = placeholder; self._text = text; self.style = style; self.secure = secure; self.focus = focus; self.onSubmit = onSubmit
  }

  var body: some View {
    ZStack(alignment: .leading) {
      if text.isEmpty {
        Text(placeholder).font(.system(size: u(13))).foregroundStyle(style.inkDim.opacity(0.6)).allowsHitTesting(false)
      }
      Group {
        if secure { SecureField("", text: $text) } else { TextField("", text: $text) }
      }
      .textFieldStyle(.plain)
      .font(.system(size: u(14)))
      .foregroundStyle(style.ink)
      .focused($focused)
      .onSubmit(onSubmit)
    }
    .padding(.vertical, u(2))
    .overlay(alignment: .bottom) { Rectangle().fill(style.inkDim).frame(height: 1) }
    .onAppear { if focus { DispatchQueue.main.async { focused = true } } }
  }
}

private struct StripSpreadKey: EnvironmentKey { static let defaultValue = false }
private extension EnvironmentValues {
  var stripSpread: Bool { get { self[StripSpreadKey.self] } set { self[StripSpreadKey.self] = newValue } }
}

/// System / light / dark as icons in the top strip; the active one lit, like an LCD indicator.
private struct ThemeButton: View {
  let theme: DisplayTheme
  let lit: Bool
  let style: GlassStyle
  let action: () -> Void
  @State private var hover = false
  private var symbol: String {
    switch theme { case .system: return "circle.lefthalf.filled"; case .light: return "sun.max.fill"; case .dark: return "moon.fill" }
  }
  var body: some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: u(11.5)))
        .frame(width: u(24), height: u(18)).contentShape(Rectangle())
        .foregroundStyle(lit ? style.ink : style.inkDim)
        .opacity(lit ? 1 : hover ? 0.85 : 0.42)
    }
    .buttonStyle(.plain).focusable(false)
    .onHover { hover = $0 }
    .pointingHand()
    .help(theme == .system ? "Match the system appearance" : theme == .light ? "Light display" : "Dark display")
  }
}


/// A pointing-hand cursor over something clickable on the display (instead of underlines).
private struct PointingHand: ViewModifier {
  let enabled: Bool
  @State private var pushed = false
  func body(content: Content) -> some View {
    content
      .onHover { inside in
        if inside && enabled && !pushed { NSCursor.pointingHand.push(); pushed = true }
        else if !inside && pushed { NSCursor.pop(); pushed = false }
      }
      .onDisappear { if pushed { NSCursor.pop(); pushed = false } }   // e.g. the screen changed under the cursor
      .onChange(of: enabled) { on in if !on && pushed { NSCursor.pop(); pushed = false } }
  }
}
extension View {
  func pointingHand(_ enabled: Bool = true) -> some View { modifier(PointingHand(enabled: enabled)) }
}
