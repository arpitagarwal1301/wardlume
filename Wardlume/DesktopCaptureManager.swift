//  DesktopCaptureManager.swift
//  Wardlume
//
//  Phase 1c: Captures the live desktop via ScreenCaptureKit and feeds a
//  zero-copy IOSurface-backed MTLTexture into MetalOverlayView each frame.
//
//  Concurrency note:
//    SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor makes all types implicitly
//    @MainActor. SCStreamOutput and SCStreamDelegate callbacks are delivered
//    on SCKit's internal background thread, so both callback methods carry
//    an explicit `nonisolated` annotation to opt out of MainActor isolation.
//    Properties accessed from those callbacks are marked nonisolated(unsafe)
//    and are safe because:
//      • `device` — MTLDevice texture-creation API is thread-safe.
//      • `view`   — only touched inside `Task { @MainActor in … }`.

import ScreenCaptureKit
import CoreMedia
import CoreVideo
import Metal
import AppKit

/// Notified when the capture stream stops unexpectedly (e.g. Screen Recording
/// permission revoked mid-session). The ward's input lock is independent of the
/// stream, so without this the overlay would freeze on its last frame while
/// input stays fully locked — a lockout behind a stale image. The delegate is
/// expected to tear the ward down so the user can recover.
@MainActor
protocol DesktopCaptureManagerDelegate: AnyObject {
    func desktopCaptureDidStop(_ manager: DesktopCaptureManager, error: Error?)
}

final class DesktopCaptureManager: NSObject {

    // MTLDevice is accessed from the nonisolated SCStreamOutput callback.
    // Metal device methods used here (makeTexture) are documented thread-safe.
    nonisolated(unsafe) private let device: MTLDevice

    // Accessed only inside Task { @MainActor in … } dispatches.
    private weak var view: MetalOverlayView?

    /// Notified on the MainActor when the stream stops unexpectedly.
    weak var captureDelegate: DesktopCaptureManagerDelegate?

    private var stream: SCStream?

    /// Set true by stopCapture() so the SCStreamDelegate didStopWithError path can
    /// distinguish an intentional teardown (no delegate notification) from an
    /// unexpected stop such as permission revocation (notify so the ward recovers).
    nonisolated(unsafe) private var intentionalStop = false

    init(device: MTLDevice, view: MetalOverlayView) {
        self.device = device
        self.view   = view
    }

    // -------------------------------------------------------------------------
    // MARK: — Public API (called on the main thread / MainActor)
    // -------------------------------------------------------------------------

    /// Discovers shareable content, builds a filter that excludes the Wardlume
    /// overlay window, and starts the SCStream at 60 fps.
    func startCapture(excludingWindow overlayWindow: NSWindow) {
        Task {
            do {
                try await startCaptureTask(excludingWindow: overlayWindow)
            } catch {
                print("Wardlume [DesktopCaptureManager]: startCapture failed — \(error)")
                // Fail closed: an armed ward without live capture is a blank
                // shield over a real input lock. Route through the same
                // delegate path as a mid-session capture loss so the ward
                // tears down and the user gets the alert.
                captureDelegate?.desktopCaptureDidStop(self, error: error)
            }
        }
    }

    func stopCapture() {
        guard let stream else { return }
        intentionalStop = true   // suppress the didStopWithError recovery path
        self.stream = nil
        Task {
            try? await stream.stopCapture()
        }
    }

    // -------------------------------------------------------------------------
    // MARK: — Private capture setup
    // -------------------------------------------------------------------------

    private func startCaptureTask(excludingWindow overlayWindow: NSWindow) async throws {
        // Enumerate all shareable content (windows + displays).
        // This call triggers the Screen Recording permission dialog on first use.
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        // Exclude the Wardlume overlay window by CGWindowID to prevent the
        // captured frame from containing the overlay → feedback loop.
        let wardlumeWindowID = CGWindowID(overlayWindow.windowNumber)
        let excludedWindows  = content.windows.filter {
            $0.windowID == wardlumeWindowID
        }

        let filter = SCContentFilter(display: display,
                                     excludingWindows: excludedWindows)

        // Capture at the display's native pixel resolution so the UV mapping
        // in the fragment shader is 1-to-1 with the Metal drawable.
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let scale  = screen.backingScaleFactor

        let config = SCStreamConfiguration()
        config.width               = Int(screen.frame.width  * scale)
        config.height              = Int(screen.frame.height * scale)
        config.pixelFormat         = kCVPixelFormatType_32BGRA  // matches .bgra8Unorm
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor         = false
        config.capturesAudio       = false

        let captureStream = SCStream(filter: filter,
                                     configuration: config,
                                     delegate: self)

        // Deliver frames on a dedicated background queue.
        // The nonisolated callback handles the thread-boundary crossing.
        try captureStream.addStreamOutput(
            self,
            type: .screen,
            sampleHandlerQueue: DispatchQueue(label: "wardlume.capture",
                                              qos: .userInteractive))

        try await captureStream.startCapture()
        stream = captureStream
    }

    // -------------------------------------------------------------------------
    // MARK: — Errors
    // -------------------------------------------------------------------------

    enum CaptureError: Error {
        case noDisplay
    }
}

// -------------------------------------------------------------------------
// MARK: — SCStreamOutput
// -------------------------------------------------------------------------

extension DesktopCaptureManager: SCStreamOutput {

    /// Called on `wardlume.capture` background queue by SCKit.
    /// `nonisolated` opts this method out of the implicit @MainActor isolation
    /// so SCKit can call it from any thread without a Swift 6 concurrency error.
    nonisolated func stream(_ stream: SCStream,
                            didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard type == .screen,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }

        // ---- Zero-copy IOSurface → MTLTexture --------------------------------
        // CVPixelBufferGetIOSurface returns an Unmanaged<IOSurface>.
        // takeUnretainedValue() gives us the IOSurface without a retain, which is
        // correct here because CMSampleBuffer already owns the IOSurface's lifetime
        // and `sampleBuffer` stays alive across this function scope.
        guard let ioSurface = CVPixelBufferGetIOSurface(pixelBuffer)?
                                  .takeUnretainedValue()
        else { return }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,   // matches kCVPixelFormatType_32BGRA
            width:  w,
            height: h,
            mipmapped: false)
        desc.usage       = [.shaderRead]
        // .shared is required for IOSurface-backed textures — Metal maps into
        // the IOSurface's existing GPU-accessible memory, no pixel copy occurs.
        desc.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: desc,
                                               iosurface: ioSurface,
                                               plane: 0)
        else { return }

        // Swap the texture on the MainActor so draw() always reads a consistent
        // pointer on the same thread as MTKView's display-link callback.
        Task { @MainActor [weak self] in
            self?.view?.desktopTexture = texture
        }
    }
}

// -------------------------------------------------------------------------
// MARK: — SCStreamDelegate
// -------------------------------------------------------------------------

extension DesktopCaptureManager: SCStreamDelegate {

    /// Called if the stream stops unexpectedly (e.g. permission revoked).
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Wardlume [DesktopCaptureManager]: SCStream stopped — \(error)")
        let wasIntentional = intentionalStop
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.stream = nil
            // Only escalate if WE didn't ask it to stop. An unexpected stop while
            // the ward is up (Screen Recording revoked, display reconfig) would
            // otherwise leave the overlay frozen on its last frame with input
            // still locked — notify the delegate to tear the ward down.
            if !wasIntentional {
                self.captureDelegate?.desktopCaptureDidStop(self, error: error)
            }
        }
    }
}
