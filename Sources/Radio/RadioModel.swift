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

    progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    applyEQ()

    let user = app.getSavedUsername() ?? "", pass = app.getSavedPassword() ?? ""
    username = user
    mode = user.isEmpty || pass.isEmpty ? .login : .loading("TUNING IN")
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
    default: break   // the engine retries and reports other errors itself
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
    stations = all.map { StationItem(id: $0.token, name: $0.name ?? "", created: $0.created, isShuffle: $0.isQuickMix,
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
      ImageLoader().loadImageURL(url) { [weak self] data in
        MainActor.assumeIsolated {
          guard let self, self.playback.playing?.playingSong?.art == expected, let data else { return }
          self.art = NSImage(data: data)
        }
      }
    }
  }

  private func refreshSong() {
    let station = playback.playing
    let song = station?.playingSong
    currentToken = station?.token
    stationName = station.map { $0.isQuickMix ? "Shuffle" : ($0.name ?? "") } ?? ""
    title = song?.title ?? ""
    artist = song?.artist ?? ""
    album = song?.album ?? ""
    rating = song?.nrating?.intValue ?? 0
  }

  private func stateChanged() { isPlaying = playback.playing?.isPlaying() ?? false }

  private func tick() {
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
    if mode == .loading(Self.noSignal) {          // stream dropped: fetch a fresh playlist and go on
      mode = .loading("TUNING IN")
      playback.playing?.clearSongList()
      playback.playing?.next()
      return
    }
    // a station restored paused at launch hasn't started streaming yet; play starts it
    if let s = playback.playing, !s.isPlaying(), !s.isPaused() { playback.play() } else { playback.playpause(nil) }
  }
  func next() { playback.next(nil) }
  func like() { playback.like(nil) }
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
