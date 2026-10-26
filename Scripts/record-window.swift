// Records the Walnut window, transparency included, to a ProRes 4444 movie.
//
//   swift Scripts/record-window.swift [seconds] [output.mov]
//
// Needs Screen Recording permission for the app running it (System Settings →
// Privacy & Security → Screen Recording). Walnut must be open and on screen.

import AppKit
import AVFoundation
import ScreenCaptureKit

_ = NSApplication.shared   // connects to the window server before ScreenCaptureKit is used
let seconds = Double(CommandLine.arguments.dropFirst().first ?? "") ?? 8
let output = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "build/walnut-window.mov")

final class Recorder: NSObject, SCStreamOutput {
  let writer: AVAssetWriter
  let input: AVAssetWriterInput
  private var started = false

  init(url: URL, width: Int, height: Int) throws {
    try? FileManager.default.removeItem(at: url)
    writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.proRes4444,   // keeps the alpha channel
      AVVideoWidthKey: width, AVVideoHeightKey: height])
    input.expectsMediaDataInRealTime = true
    writer.add(input)
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .screen, buffer.isValid,
          let info = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
          let raw = info.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
    if !started {
      writer.startWriting()
      writer.startSession(atSourceTime: buffer.presentationTimeStamp)
      started = true
    }
    if input.isReadyForMoreMediaData { input.append(buffer) }
  }
}

let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
guard let window = content.windows.first(where: { $0.owningApplication?.applicationName == "Walnut" && $0.frame.width > 400 }) else {
  print("Walnut's window isn't on screen."); exit(1)
}

let filter = SCContentFilter(desktopIndependentWindow: window)
let scale = CGFloat(filter.pointPixelScale)
let config = SCStreamConfiguration()
config.width = Int(window.frame.width * scale)
config.height = Int(window.frame.height * scale)
config.pixelFormat = kCVPixelFormatType_32BGRA
config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
config.showsCursor = false
config.ignoreShadowsSingleWindow = true
config.shouldBeOpaque = false

let recorder = try Recorder(url: output, width: config.width, height: config.height)
let stream = SCStream(filter: filter, configuration: config, delegate: nil)
try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: DispatchQueue(label: "frames"))
try await stream.startCapture()
print("Recording \(config.width)×\(config.height) for \(seconds) s…")
try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
try await stream.stopCapture()
recorder.input.markAsFinished()
await recorder.writer.finishWriting()
print(recorder.writer.status == .completed ? "Saved \(output.path)" : "Failed: \(String(describing: recorder.writer.error))")
