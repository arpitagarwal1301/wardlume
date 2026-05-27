//  MetalOverlayView.swift
//  Wardlume
//
//  Phase 1c: Opaque MTKView. Binds a live desktop MTLTexture (supplied by
//  DesktopCaptureManager) to [[texture(0)]] each frame so the fragment shader
//  can perform true refraction and chromatic aberration on real desktop pixels.

import MetalKit
import QuartzCore

// ---------------------------------------------------------------------------
// ShaderParams — must match the struct in WardShader.metal byte-for-byte.
// ---------------------------------------------------------------------------
struct ShaderParams {
    var time:             Float = 0.0
    var rippleStrength:   Float = 0.018
    var rippleSpeed:      Float = 0.35
    var shimmerIntensity: Float = 0.18
    var baseAlpha:        Float = 0.05   // kept for struct alignment; unused in Phase 1c
    var tintR:            Float = 0.35
    var tintG:            Float = 0.60
    var tintB:            Float = 1.00
    var aspectRatio:      Float = 1.77
    // Phase 2a: shader time of the last intercepted input event.
    // Default -9999 → pulseAge >> 0.20 s → pulseMult = 1.0 → no burst at startup.
    var lastIntrusionT:   Float = -9999.0
}

// ---------------------------------------------------------------------------
// MetalOverlayView
// ---------------------------------------------------------------------------
class MetalOverlayView: MTKView {

    // Phase 1c: opaque — the shader renders the full desktop + all effects.
    // The compositor no longer needs to see through this view.
    override var isOpaque: Bool { true }

    private var commandQueue:  MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!

    var params = ShaderParams()

    private var startTime: CFTimeInterval = CACurrentMediaTime()

    // Live desktop texture from DesktopCaptureManager, updated ~60 fps.
    // Initialized to a 1×1 opaque-black texture so the shader never receives
    // a nil binding before the first SCStream frame arrives.
    var desktopTexture: MTLTexture!

    // Written by InputLockManager on the main run loop thread when an input
    // event is intercepted and consumed. draw() copies it into params.lastIntrusionT
    // each frame. nonisolated(unsafe) satisfies Swift 6 without a lock —
    // both writer (run-loop callback) and reader (draw()) run on the main thread.
    nonisolated(unsafe) var intrusionTime: Float = -9999.0

    // ---------------------------------------------------------------------------
    // MARK: — Initialisation
    // ---------------------------------------------------------------------------
    init(frame: CGRect) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Wardlume: No Metal-capable GPU found.")
        }
        super.init(frame: frame, device: device)
        configureSurface()
        buildPipeline()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) not used") }

    // ---------------------------------------------------------------------------
    // MARK: — Surface configuration
    // ---------------------------------------------------------------------------
    private func configureSurface() {
        // Opaque CAMetalLayer — the compositor doesn't peek behind this window.
        layer?.isOpaque = true

        // Opaque black clear (alpha = 1). The shader covers every pixel.
        clearColor = MTLClearColorMake(0, 0, 0, 1)

        colorPixelFormat = .bgra8Unorm

        isPaused = false
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 60

        delegate = self

        wantsLayer = true
        layer?.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    }

    // ---------------------------------------------------------------------------
    // MARK: — Pipeline construction
    // ---------------------------------------------------------------------------
    private func buildPipeline() {
        guard let device = device else { return }

        guard let library = device.makeDefaultLibrary() else {
            fatalError("Wardlume: Could not load Metal shader library. " +
                       "Make sure WardShader.metal is in Compile Sources.")
        }

        let vertexFn   = library.makeFunction(name: "wardVertex")
        let fragmentFn = library.makeFunction(name: "wardFragment")

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction   = vertexFn
        desc.fragmentFunction = fragmentFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Blending is kept so effects (border, motes, sigils) can composite
        // with additive/over blending on top of the desktop base layer.
        let att = desc.colorAttachments[0]!
        att.isBlendingEnabled           = true
        att.sourceRGBBlendFactor        = .sourceAlpha
        att.destinationRGBBlendFactor   = .oneMinusSourceAlpha
        att.sourceAlphaBlendFactor      = .one
        att.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Wardlume: Failed to build pipeline — \(error)")
        }

        commandQueue = device.makeCommandQueue()

        // 1×1 opaque-black fallback texture.
        // Prevents a null-texture GPU crash in the first few frames before
        // DesktopCaptureManager delivers its first SCStream sample.
        let fallback = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        fallback.usage       = [.shaderRead]
        fallback.storageMode = .shared
        desktopTexture = device.makeTexture(descriptor: fallback)!
        // Texture memory is zero-initialised (BGRA 0,0,0,0 = transparent black).
        // The shader treats alpha=1 as the window is opaque, so the first frame
        // will show a black screen until the first real desktop frame arrives
        // (typically within 1–2 display refresh cycles).
    }
}

// ---------------------------------------------------------------------------
// MARK: — MTKViewDelegate (60 fps)
// ---------------------------------------------------------------------------
extension MetalOverlayView: MTKViewDelegate {

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        params.time = Float(CACurrentMediaTime() - startTime)

        guard
            let drawable  = currentDrawable,
            let passDesc  = currentRenderPassDescriptor,
            let cmdBuffer = commandQueue.makeCommandBuffer(),
            let encoder   = cmdBuffer.makeRenderCommandEncoder(descriptor: passDesc)
        else { return }

        encoder.setRenderPipelineState(pipelineState)

        // Snapshot the intrusion time set by InputLockManager into params so
        // the GPU receives it this frame. Both are on the main thread.
        params.lastIntrusionT = intrusionTime

        var p = params
        withUnsafeBytes(of: &p) { raw in
            encoder.setFragmentBytes(raw.baseAddress!, length: raw.count, index: 0)
        }

        // Bind the live desktop texture at index 0, matching [[texture(0)]]
        // declared in wardFragment. DesktopCaptureManager swaps this each frame.
        encoder.setFragmentTexture(desktopTexture, index: 0)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        encoder.endEncoding()
        cmdBuffer.present(drawable)
        cmdBuffer.commit()
    }
}
