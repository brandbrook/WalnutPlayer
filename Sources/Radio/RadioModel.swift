//
//  RadioModel.swift
//  Walnut
//
//  Connects the radio interface to the Objective-C engine. It listens to the engine's
//  notifications (login, new song, playback state, stations, search, station info) and
//  calls the existing controllers and Pandora client for every action.
//

import AppKit
import Combine
import SwiftUI

/// What the display is showing.
enum DisplayMode: Equatable {
  case nowPlaying
  case loading(String)
  case login
  case stations
  case history
  case newStation
  case editStation(String)     // station token
  case deleteStation(String)   // station token

  /// Browser screens take over the whole display; the station list and history scroll sideways.
  var isBrowser: Bool { self == .stations || self == .history }
}

enum DisplayTheme: String, CaseIterable { case system, light, dark }

struct StationItem: Identifiable, Equatable {
  let id: String            // token
  let name: String
  let created: UInt64
  let isShuffle: Bool
  let canEdit: Bool
}

struct HistoryItem: Identifiable {
  let id: ObjectIdentifier
  let song: Song
  var title: String { song.title ?? "" }
  var artist: String { song.artist ?? "" }
  var rating: Int { song.nrating?.intValue ?? 0 }
}

struct SearchItem: Identifiable, Equatable {
  enum Kind: String { case artist = "ARTIST", song = "SONG", genre = "GENRE" }
  let id: String            // music or station token
  let name: String
  let detail: String?
  let kind: Kind
}

struct SeedItem: Identifiable, Equatable {
  let id: String            // seedId
  let name: String
}

@MainActor
final class RadioModel: ObservableObject {
  static let shared = RadioModel()

  // Display
  @Published var mode: DisplayMode = .loading("TUNING IN")
  @Published var selection = 0
  @AppStorage("walnut.displayTheme") var theme: DisplayTheme = .system
  @AppStorage("walnut.sortStations") var sortByNewest = false

  // Now playing
  @Published private(set) var stationName = ""
  @Published private(set) var title = ""
  @Published private(set) var artist = ""
  @Published private(set) var album = ""
  @Published private(set) var art: NSImage?
  @Published private(set) var rating = 0
  @Published private(set) var isPlaying = false
  @Published private(set) var elapsed: TimeInterval = 0
  @Published private(set) var currentToken: String?
  @Published var flash: String?          // briefly lit action ("dislike", "tired")

  // Lists
  @Published private(set) var stations: [StationItem] = []
  @Published private(set) var history: [HistoryItem] = []

  // Login
  @Published var username = ""
  @Published var password = ""
  @Published private(set) var loginError: String?

  // New station / edit
  @Published var query = ""
  @Published private(set) var results: [SearchItem] = []
  @Published var draftName = ""
  @Published private(set) var draftSeeds: [SeedItem] = []
  @Published var seedQuery = ""
  @Published private(set) var seedResults: [SearchItem] = []
  private var genres: [SearchItem] = []

  // EQ gains in dB, applied to the audio by the engine (see WalnutAudio)
  @AppStorage("walnut.eq.low") var eqLow = 0.0 { didSet { applyEQ() } }
  @AppStorage("walnut.eq.mid") var eqMid = 0.0 { didSet { applyEQ() } }
  @AppStorage("walnut.eq.high") var eqHigh = 0.0 { didSet { applyEQ() } }

  private var observers: [NSObjectProtocol] = []
  private var progressTimer: Timer?
  private var searchFor: String?
  private var lastSavedPlayState: Bool?

  private var app: HermesAppDelegate { NSApp.delegate as! HermesAppDelegate }
  private var pandora: Pandora { app.pandora }
  private var playback: PlaybackController { app.playback }

  private init() {}

  // MARK: - Start up

  func start() {
    let nc = NotificationCenter.default
    func on(_ name: NSNotification.Name, _ handler: @escaping (Notification) -> Void) {
      observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { n in
        MainActor.assumeIsolated { handler(n) }
      })
    }
    on(.PandoraDidAuthenticate) { [weak self] _ in self?.authenticated() }
    on(.PandoraDidLogOut) { [weak self] _ in self?.showLogin(error: nil) }
    on(.PandoraDidError) { [weak self] n in self?.pandoraError(n) }
    on(.PandoraDidLoadStations) { [weak self] _ in self?.stationsLoaded() }
    on(.PandoraDidCreateStation) { [weak self] _ in self?.reloadStations() }
    on(.PandoraDidDeleteStation) { [weak self] _ in self?.reloadStations() }
    on(.PandoraDidRenameStation) { [weak self] _ in self?.reloadStations() }
    on(.PandoraDidRateSong) { [weak self] _ in self?.refreshSong(); self?.reloadHistory() }
    on(.PandoraDidLoadSearchResults) { [weak self] n in self?.searchLoaded(n) }
    on(.PandoraDidLoadGenreStations) { [weak self] n in self?.genresLoaded(n) }
    on(.PandoraDidLoadStationInfo) { [weak self] n in self?.stationInfoLoaded(n) }
    on(.PandoraDidAddSeed) { [weak self] _ in self?.refetchStationInfo() }
    on(.PandoraDidDeleteSeed) { [weak self] _ in self?.refetchStationInfo() }
    on(.StationDidPlaySong) { [weak self] _ in self?.songPlayed() }
    on(.ASStatusChanged) { [weak self] _ in self?.stateChanged() }
    on(NSNotification.Name(ASStreamError)) { [weak self] _ in self?.mode = .loading(Self.noSignal) }
    // Pandora couldn't be reached (network, server): say so instead of tuning in forever. The engine
    // retries by itself after 20 s; play retries straight away.
    on(NSNotification.Name("WalnutConnectionProblem")) { [weak self] _ in
      guard let self else { return }
      switch self.mode { case .login: return; default: self.mode = .loading(Self.noSignal) }
    }

    progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    applyEQ()
    app.history.loadSavedSongs()   // so History shows past songs right away, not only after the next song

    if UserDefaults.standard.bool(forKey: "walnut.demo") { startDemo(); return }
    let user = app.getSavedUsername() ?? "", pass = app.getSavedPassword() ?? ""
    username = user
    mode = user.isEmpty || pass.isEmpty ? .login : .loading("TUNING IN")
  }

  // MARK: - Demo mode

  /// Sample data for working on the layout without Pandora: launch with `-walnut.demo YES`.
  private var demo = false

  private func startDemo() {
    demo = true
    stations = ["Shuffle", "Late Night Lo-Fi Radio", "Sunday Soul Radio", "Neon Drive Radio", "Classical Calm Radio",
                "Porch Blues Radio", "Café Jazz Radio", "Bossa Nova Breeze Radio", "Indie Folk Radio",
                "Ambient Drift Radio", "80s Synthpop Radio", "Motown Classics Radio"].enumerated().map { i, name in
      StationItem(id: "demo\(i)", name: name, created: UInt64(1_700_000_000 - i * 86_400), isShuffle: i == 0, canEdit: i != 0)
    }
    currentToken = "demo2"
    stationName = "Sunday Soul Radio"
    title = "Golden Hour (Live at the Velvet Room)"
    album = "Evenings on Larkin Street (Deluxe Edition)"
    artist = "The Velvet Room Orchestra"
    rating = 0
    art = Self.demoArt()
    isPlaying = true
    mode = .nowPlaying
  }

  private static func demoArt() -> NSImage {
    NSImage(size: NSSize(width: 300, height: 300), flipped: false) { r in
      NSGradient(colors: [NSColor(red: 0.85, green: 0.55, blue: 0.3, alpha: 1), NSColor(red: 0.35, green: 0.12, blue: 0.15, alpha: 1)])?
        .draw(in: r, angle: -70)
      NSColor(white: 1, alpha: 0.85).setFill()
      NSBezierPath(ovalIn: NSRect(x: 170, y: 170, width: 80, height: 80)).fill()
      ("GOLDEN HOUR" as NSString).draw(at: NSPoint(x: 22, y: 26),
        withAttributes: [.font: NSFont.systemFont(ofSize: 26, weight: .heavy), .foregroundColor: NSColor.white])
      return true
    }
  }

  // MARK: - Engine events

  private func authenticated() {
    loginError = nil
    if mode == .login || mode == .loading("LOGGING IN") { mode = .loading("TUNING IN") }
    if genres.isEmpty { pandora.fetchGenreStations() }
  }

  private func showLogin(error: String?) {
    loginError = error
    password = ""
    mode = .login
  }

  private func pandoraError(_ n: Notification) {
    let code = (n.userInfo?["code"] as? NSNumber)?.intValue ?? 0
    switch code {
    case 1002, 1011, 1012: showLogin(error: "WRONG EMAIL OR PASSWORD")
    default: break   // other errors arrive as WalnutConnectionProblem, after the engine has handled them
    }
  }

  private func stationsLoaded() {
    reloadStations()
    // The engine resumes the last station after loading; if it has none, let the listener pick one.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
      guard let self, case .loading = self.mode else { return }
      if self.playback.playing == nil { self.showBrowser(.stations); return }
      // restored paused: show the station (and its last song, if saved) on a dimmed display
      self.refreshSong()
      self.loadArt()
      self.mode = .nowPlaying
    }
  }

  private func reloadStations() {
    let all = (pandora.stations as? [Station]) ?? []
    stations = all.map { StationItem(id: $0.token, name: plain($0.name ?? ""), created: $0.created, isShuffle: $0.isQuickMix,
                                     canEdit: !$0.isQuickMix && !$0.shared) }
    refreshSong()
  }

  private func songPlayed() {
    refreshSong()
    if case .loading = mode { mode = .nowPlaying }
    loadArt()
    DispatchQueue.main.async { [weak self] in self?.reloadHistory() }
  }

  private func loadArt() {
    art = nil
    if let url = playback.playing?.playingSong?.art, !url.isEmpty {
      let expected = url
      ImageLoader().loadImageURL(artURL(url)) { [weak self] data in
        MainActor.assumeIsolated {
          guard let self, self.playback.playing?.playingSong?.art == expected, let data else { return }
          self.art = NSImage(data: data).map(trimFlatBorder)
        }
      }
    }
  }

  private func refreshSong() {
    let station = playback.playing
    let song = station?.playingSong
    currentToken = station?.token
    stationName = station.map { $0.isQuickMix ? "Shuffle" : plain($0.name ?? "") } ?? ""
    title = song?.title ?? ""
    artist = song?.artist ?? ""
    album = song?.album ?? ""
    rating = song?.nrating?.intValue ?? 0
  }

  private func stateChanged() { isPlaying = playback.playing?.isPlaying() ?? false }

  private func tick() {
    if demo { if isPlaying { elapsed += 0.25 }; return }
    var t = 0.0
    if let s = playback.playing, s.progress(&t) { elapsed = t } else if playback.playing == nil { elapsed = 0 }
    let playingNow = playback.playing?.isPlaying() ?? false
    if playingNow != isPlaying { isPlaying = playingNow }
    rememberPlayState()
  }

  /// Saved as soon as it changes (not only on a normal quit), so Walnut reopens playing or paused
  /// the way it was left even after a crash or a force quit. Buffering and errors don't count.
  private func rememberPlayState() {
    guard let s = playback.playing else { return }
    let state: Bool? = s.isPlaying() ? true : (s.isPaused() ? false : nil)
    guard let state, state != lastSavedPlayState else { return }
    lastSavedPlayState = state
    UserDefaults.standard.set(state, forKey: "walnut.playingAtQuit")
  }

  private func reloadHistory() {
    let songs = (app.history.songs as? [Song]) ?? []
    history = songs.map { HistoryItem(id: ObjectIdentifier($0), song: $0) }
  }

  // MARK: - Song links

  enum SongPart { case track, album, artist }

  /// Pandora's own page for the track, album or artist when it has one, otherwise a web search.
  func link(for part: SongPart) -> URL? {
    let song = playback.playing?.playingSong
    let pandora: String?, query: String
    switch part {
    case .track:  pandora = song?.titleUrl;  query = [title, artist].filter { !$0.isEmpty }.joined(separator: " ")
    case .album:  pandora = song?.albumUrl;  query = [album, artist].filter { !$0.isEmpty }.joined(separator: " ")
    case .artist: pandora = song?.artistUrl; query = artist
    }
    guard !query.isEmpty else { return nil }
    if let p = pandora, !p.isEmpty, let url = URL(string: p) { return url }
    var search = URLComponents(string: "https://www.google.com/search")!
    search.queryItems = [URLQueryItem(name: "q", value: query)]
    return search.url
  }

  // MARK: - Login

  func logIn() {
    let user = username.trimmingCharacters(in: .whitespaces)
    guard !user.isEmpty, !password.isEmpty else { return }
    loginError = nil
    mode = .loading("LOGGING IN")
    app.saveUsername(user, password: password)
    pandora.authenticate(user, password: password, request: nil)
  }

  // MARK: - Transport and song actions

  static let noSignal = "NO SIGNAL · PRESS PLAY"

  func playPause() {
    if demo { isPlaying.toggle(); return }
    if mode == .loading(Self.noSignal) {          // try again
      mode = .loading("TUNING IN")
      if let station = playback.playing, pandora.isAuthenticated() {
        station.clearSongList()                   // stream dropped: fetch a fresh playlist and go on
        station.next()
      } else {
        app.retry(nil)                            // couldn't reach Pandora: log in / repeat the request
      }
      return
    }
    // a station restored paused at launch hasn't started streaming yet; play starts it
    if let s = playback.playing, !s.isPlaying(), !s.isPaused() { playback.play() } else { playback.playpause(nil) }
  }
  func next() { playback.next(nil) }
  func like() {
    if demo { rating = rating == 1 ? 0 : 1; return }   // demo: just toggle the lit state
    playback.like(nil)
  }
  func dislike() { lightUp("dislike") { self.playback.dislike(nil) } }
  func tired() { lightUp("tired") { self.playback.tired(nil) } }

  private func lightUp(_ name: String, then action: @escaping () -> Void) {
    flash = name
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.flash = nil; action() }
  }

  // MARK: - Browser

  var browserItems: Int {
    switch mode {
    case .stations: return sortedStations.count
    case .history: return history.count
    case .newStation: return results.count
    default: return 0
    }
  }

  var sortedStations: [StationItem] {
    let shuffle = stations.filter(\.isShuffle)
    let rest = stations.filter { !$0.isShuffle }
    return shuffle + (sortByNewest ? rest.sorted { $0.created > $1.created }
                                   : rest.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
  }

  func showBrowser(_ m: DisplayMode) {
    if m == .history { reloadHistory() }
    mode = m
    if m == .stations { selection = sortedStations.firstIndex { $0.id == currentToken } ?? 0 } else { selection = 0 }
    if m == .history { reloadHistory() }
  }

  /// Menu button / Escape: out of a sub-screen back to the browser, out of the browser to now playing.
  func back() {
    switch mode {
    case .newStation, .editStation, .deleteStation: showBrowser(.stations)
    case .stations, .history: mode = playback.playing == nil ? .stations : .nowPlaying
    case .nowPlaying: showBrowser(.stations)
    default: break
    }
  }

  func move(_ delta: Int) {
    let n = browserItems
    guard n > 0 else { return }
    selection = ((selection + delta) % n + n) % n
  }

  /// Play button / Return in the browser.
  func choose() {
    switch mode {
    case .stations: tune(selection)
    case .history: toggleHistoryRating(selection, like: true)
    case .newStation: createStation(selection)
    case .editStation: saveEdit()
    case .deleteStation(let token): confirmDelete(token)
    default: break
    }
  }

  func tune(_ index: Int) {
    let list = sortedStations
    guard list.indices.contains(index), let station = Station(forToken: list[index].id) else { return }
    PlaybackController.setPlayOnStart(true)
    if currentToken != station.token { playback.play(station) } else if !isPlaying { playback.play() }
    mode = .nowPlaying
  }

  func toggleHistoryRating(_ index: Int, like: Bool) {
    guard history.indices.contains(index) else { return }
    let song = history[index].song
    playback.rate(song, as: like)
  }

  // New station
  func beginNewStation() {
    query = ""; results = []; selection = 0
    mode = .newStation
    if genres.isEmpty { pandora.fetchGenreStations() }
  }

  func search(_ q: String) {
    query = q
    selection = 0
    let trimmed = q.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { results = []; return }
    searchFor = trimmed
    pandora.search(trimmed)
  }

  private func searchLoaded(_ n: Notification) {
    guard let q = n.object as? String else { return }
    let info = n.userInfo ?? [:]
    let artists = (info["Artists"] as? [PandoraSearchResult] ?? []).map { SearchItem(id: $0.value, name: $0.name, detail: nil, kind: .artist) }
    let songs = (info["Songs"] as? [PandoraSearchResult] ?? []).map { r -> SearchItem in
      let parts = r.name.components(separatedBy: " - ")
      return SearchItem(id: r.value, name: parts.first ?? r.name, detail: parts.count > 1 ? parts.dropFirst().joined(separator: " - ") : nil, kind: .song)
    }
    if case .editStation = mode {
      guard q == seedQuery.trimmingCharacters(in: .whitespaces) else { return }
      seedResults = Array((artists + songs).prefix(6))
    } else if q == searchFor {
      let g = genres.filter { $0.name.localizedCaseInsensitiveContains(q) }
      results = artists + songs + g
    }
  }

  private func genresLoaded(_ n: Notification) {
    let categories = n.userInfo?["categories"] as? [[String: Any]] ?? []
    genres = categories.flatMap { cat in
      (cat["stations"] as? [[String: Any]] ?? []).compactMap { st in
        guard let name = st["stationName"] as? String, let token = st["stationToken"] as? String else { return nil }
        return SearchItem(id: token, name: name, detail: nil, kind: .genre)
      }
    }
  }

  func createStation(_ index: Int) {
    guard results.indices.contains(index) else { return }
    PlaybackController.setPlayOnStart(true)
    pandora.createStation(results[index].id)   // the engine plays it as soon as Pandora creates it
    mode = .loading("TUNING IN")
  }

  // Edit
  private var editingStation: Station?

  func beginEdit(_ index: Int) {
    let list = sortedStations
    guard list.indices.contains(index), list[index].canEdit, let st = Station(forToken: list[index].id) else { return }
    editingStation = st
    draftName = st.name ?? ""
    draftSeeds = []; seedQuery = ""; seedResults = []
    mode = .editStation(st.token)
    pandora.fetchStationInfo(st)
  }

  private func refetchStationInfo() { if let st = editingStation { pandora.fetchStationInfo(st) } }

  private func stationInfoLoaded(_ n: Notification) {
    guard case .editStation = mode, let seeds = n.userInfo?["seeds"] as? [String: Any] else { return }
    var items: [SeedItem] = []
    for (key, value) in seeds {
      for seed in value as? [[String: Any]] ?? [] {
        guard let id = seed["seedId"] as? String else { continue }
        let artist = seed["artistName"] as? String ?? ""
        let song = seed["songName"] as? String
        items.append(SeedItem(id: id, name: key == "songs" && song != nil ? "\(song!) · \(artist)" : artist))
      }
    }
    draftSeeds = items.sorted { $0.name < $1.name }
  }

  func searchSeeds(_ q: String) {
    seedQuery = q
    let trimmed = q.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { seedResults = []; return }
    pandora.search(trimmed)
  }

  func addSeed(_ item: SearchItem) {
    guard let st = editingStation else { return }
    pandora.addSeed(item.id, to: st)
    seedQuery = ""; seedResults = []
  }

  func removeSeed(_ seed: SeedItem) {
    guard draftSeeds.count > 1 else { return }   // Pandora keeps at least one
    draftSeeds.removeAll { $0.id == seed.id }
    pandora.removeSeed(seed.id)
  }

  func saveEdit() {
    if let st = editingStation {
      let name = draftName.trimmingCharacters(in: .whitespaces)
      if !name.isEmpty, name != st.name {
        st.name = name
        pandora.renameStation(st.token, to: name)
      }
    }
    editingStation = nil
    reloadStations()
    showBrowser(.stations)
  }

  // Delete
  func beginDelete(_ index: Int) {
    let list = sortedStations
    guard list.indices.contains(index), list[index].canEdit else { return }
    mode = .deleteStation(list[index].id)
  }

  func confirmDelete(_ token: String) {
    guard let st = Station(forToken: token) else { return }
    if currentToken == token { playback.play(nil) }
    pandora.removeStation(token)
    _ = st
    showBrowser(.stations)
  }

  func nameOfStation(_ token: String) -> String { stations.first { $0.id == token }?.name ?? "" }

  // MARK: - EQ

  private func applyEQ() { WalnutAudioSetEQ(Float(eqLow), Float(eqMid), Float(eqHigh)) }
}

/// Some Pandora covers come with a flat white (or near-white) frame around the artwork; it looks
/// odd on the glass, so trim any such border (up to 12% per side) off the cover.
func trimFlatBorder(_ image: NSImage) -> NSImage {
  guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
  let w = 128, h = 128
  guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
        let px = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return image }
  ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
  func light(_ x: Int, _ y: Int) -> Bool {
    let i = (y * w + x) * 4
    return px[i] > 232 && px[i + 1] > 232 && px[i + 2] > 228
  }
  func rowLight(_ y: Int) -> Bool { (0..<w).filter { light($0, y) }.count > w * 9 / 10 }
  func colLight(_ x: Int) -> Bool { (0..<h).filter { light(x, $0) }.count > h * 9 / 10 }
  let limit = w * 12 / 100
  var top = 0, bottom = 0, left = 0, right = 0
  while top < limit && rowLight(h - 1 - top) { top += 1 }        // bitmap rows run bottom-up
  while bottom < limit && rowLight(bottom) { bottom += 1 }
  while left < limit && colLight(left) { left += 1 }
  while right < limit && colLight(w - 1 - right) { right += 1 }
  // only trim a real frame (all four sides), never artwork that's simply light at one edge
  guard min(top, bottom, left, right) >= 1 else { return image }
  let inset = max(top, bottom, left, right) + 1                  // keep it square
  let sx = CGFloat(cg.width) / CGFloat(w), sy = CGFloat(cg.height) / CGFloat(h)
  let crop = CGRect(x: CGFloat(inset) * sx, y: CGFloat(inset) * sy,
                    width: CGFloat(w - 2 * inset) * sx, height: CGFloat(h - 2 * inset) * sy)
  guard let cut = cg.cropping(to: crop) else { return image }
  return NSImage(cgImage: cut, size: NSSize(width: cut.width, height: cut.height))
}

/// Station names without emoji (Pandora adds some, like the shuffle arrows), to match the display's icons.
func plain(_ name: String) -> String {
  String(name.unicodeScalars.filter { !($0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x238C)) })
    .trimmingCharacters(in: .whitespaces)
}

/// Pandora sometimes hands out art on mediaserver-… hosts that don't answer; the same image is on
/// its content CDN, so load it from there over https.
func artURL(_ url: String) -> String {
  guard let r = url.range(of: #"^https?://mediaserver[^/]*\.pandora\.com/images/"#, options: .regularExpression) else { return url }
  return "https://content-images.p-cdn.com/images/" + url[r.upperBound...]
}
