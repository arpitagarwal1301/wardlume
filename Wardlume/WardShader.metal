//  WardShader.metal
//  Wardlume — Phase 1c: ScreenCaptureKit Desktop Texture
//
//  Changes from Phase 1b (v5):
//    - wardFragment now takes texture2d<float> desktopTex [[texture(0)]].
//    - Desktop pixels are sampled three times (one per RGB channel) at the
//      already-computed displaced UV coordinates uvR, uvDisp, and uvB, giving
//      zero-extra-cost chromatic aberration on real desktop content.
//    - All border, mote, sigil, and sheen effects layer on top unchanged.
//    - Alpha is hardcoded to 1.0 — the window is now fully opaque.
//    - baseAlpha is preserved in ShaderParams for struct compatibility but is
//      no longer added to the alpha accumulator.

#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Uniforms — mirror byte-for-byte in Swift ShaderParams.
// ---------------------------------------------------------------------------
struct ShaderParams {
    float time;
    float rippleStrength;
    float rippleSpeed;
    float shimmerIntensity;
    float baseAlpha;
    float tintR;             // affects center accents (sigils, sheen, shimmer)
    float tintG;
    float tintB;
    float aspectRatio;       // screen width ÷ height. MacBook 14/16" ≈ 1.55, iMac 24" ≈ 1.78
    float lastIntrusionT;    // shader time of last intercepted input event; -9999 = none
};

// ---------------------------------------------------------------------------
// Vertex — full-screen triangle
// ---------------------------------------------------------------------------
struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut wardVertex(uint vid [[vertex_id]]) {
    float2 pos[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
    VertexOut o;
    o.position = float4(pos[vid], 0, 1);
    o.uv = pos[vid] * float2(0.5, -0.5) + 0.5;
    return o;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
static float hash21(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}
static float2 hash22(float2 p) {
    return float2(fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453),
                  fract(sin(dot(p, float2(269.5, 183.3))) * 43758.5453));
}

static float sdRing(float2 p, float r, float ht) {
    return abs(length(p) - r) - ht;
}
static float sdSpoke(float2 p, float2 dir, float len, float ht) {
    float t = clamp(dot(p, dir), 0.0, len);
    return length(p - dir * t) - ht;
}
static float sdMask(float d) { return smoothstep(0.003, -0.001, d); }

// ---------------------------------------------------------------------------
// Sigils (unchanged from v4)
// ---------------------------------------------------------------------------
static float sigilA(float2 p, float rot) {
    float c = cos(rot), s = sin(rot);
    float2 r = float2(c*p.x - s*p.y, s*p.x + c*p.y);
    float d = sdRing(r, 0.042, 0.0013);
    d = min(d, sdRing(r,  0.022, 0.0010));
    d = min(d, sdSpoke(r, float2( 1.000,  0.000), 0.044, 0.0010));
    d = min(d, sdSpoke(r, float2( 0.500,  0.866), 0.044, 0.0010));
    d = min(d, sdSpoke(r, float2(-0.500,  0.866), 0.044, 0.0010));
    d = min(d, sdSpoke(r, float2(-1.000,  0.000), 0.044, 0.0010));
    d = min(d, sdSpoke(r, float2(-0.500, -0.866), 0.044, 0.0010));
    d = min(d, sdSpoke(r, float2( 0.500, -0.866), 0.044, 0.0010));
    return sdMask(d);
}
static float sigilB(float2 p, float rot) {
    float c = cos(rot), s = sin(rot);
    float2 r = float2(c*p.x - s*p.y, s*p.x + c*p.y);
    float d = sdRing(r, 0.045, 0.0013);
    d = min(d, sdRing(r, 0.028, 0.0010));
    d = min(d, sdRing(r, 0.012, 0.0009));
    d = min(d, sdSpoke(r, float2( 1, 0), 0.047, 0.0010));
    d = min(d, sdSpoke(r, float2( 0, 1), 0.047, 0.0010));
    d = min(d, sdSpoke(r, float2(-1, 0), 0.047, 0.0010));
    d = min(d, sdSpoke(r, float2( 0,-1), 0.047, 0.0010));
    return sdMask(d);
}
static float sigilC(float2 p, float rot) {
    float c = cos(rot), s = sin(rot);
    float2 r = float2(c*p.x - s*p.y, s*p.x + c*p.y);
    float d = sdRing(r, 0.040, 0.0013);
    d = min(d, length(r - float2( 0.040,  0.000)) - 0.008);
    d = min(d, length(r - float2( 0.028,  0.028)) - 0.008);
    d = min(d, length(r - float2( 0.000,  0.040)) - 0.008);
    d = min(d, length(r - float2(-0.028,  0.028)) - 0.008);
    d = min(d, length(r - float2(-0.040,  0.000)) - 0.008);
    d = min(d, length(r - float2(-0.028, -0.028)) - 0.008);
    d = min(d, length(r - float2( 0.000, -0.040)) - 0.008);
    d = min(d, length(r - float2( 0.028, -0.028)) - 0.008);
    d = min(d, length(r) - 0.008);
    return sdMask(d);
}

// ---------------------------------------------------------------------------
// Aurora Gradient — 5 colors, branch-free, wraps continuously.
//
// Implemented using step()-gated mix() calls so the GPU never diverges
// across the warp. All 5 interpolations are computed but only the correct
// one survives the sequential mix() gates.
// ---------------------------------------------------------------------------
static float3 auroraGradient(float t) {
    t = fract(t) * 5.0; // remap 0..1 → 0..5

    // Aurora palette — saturated but not neon, aurora borealis register
    float3 c0 = float3(0.92, 0.28, 0.66); // soft magenta-rose
    float3 c1 = float3(0.56, 0.09, 0.91); // electric violet
    float3 c2 = float3(0.09, 0.16, 0.90); // deep blue
    float3 c3 = float3(0.04, 0.76, 0.84); // cyan-teal
    float3 c4 = float3(0.94, 0.50, 0.26); // warm pink-gold

    // Piecewise smooth interpolation (smoothstep removes visible "kinks" at stops)
    float3 m01 = mix(c0, c1, smoothstep(0.0, 1.0, t));
    float3 m12 = mix(c1, c2, smoothstep(0.0, 1.0, t - 1.0));
    float3 m23 = mix(c2, c3, smoothstep(0.0, 1.0, t - 2.0));
    float3 m34 = mix(c3, c4, smoothstep(0.0, 1.0, t - 3.0));
    float3 m40 = mix(c4, c0, smoothstep(0.0, 1.0, t - 4.0));

    // Select the correct segment using step() — 0.0 below threshold, 1.0 above.
    float3 col = m01;
    col = mix(col, m12, step(1.0, t));
    col = mix(col, m23, step(2.0, t));
    col = mix(col, m34, step(3.0, t));
    col = mix(col, m40, step(4.0, t));
    return col;
}

// ---------------------------------------------------------------------------
// Fragment
// ---------------------------------------------------------------------------
fragment float4 wardFragment(VertexOut in           [[stage_in]],
                             constant ShaderParams &p [[buffer(0)]],
                             texture2d<float> desktopTex [[texture(0)]]) {
    // Clamp-to-edge linear sampler for the live desktop texture.
    // clamp_to_edge prevents out-of-bounds UVs (from displacement) from wrapping.
    constexpr sampler tex_s(address::clamp_to_edge, filter::linear);
    float2 uv = in.uv;
    float  t  = p.time * p.rippleSpeed;

    // -----------------------------------------------------------------------
    // 1. RIPPLE DISPLACEMENT FIELD (unchanged from v4)
    // -----------------------------------------------------------------------
    float wave1 = sin(uv.x * 3.0 + uv.y * 2.0 + t * 0.50) * 0.5 + 0.5;
    float wave2 = sin(uv.x * 1.8 - uv.y * 3.5 + t * 0.65 + 1.3) * 0.5 + 0.5;

    float2 wCentre = float2(0.5 + sin(t * 0.15) * 0.18,
                            0.5 + cos(t * 0.11) * 0.14);
    float  wDist   = length(uv - wCentre);
    float  wave3   = sin(wDist * 10.0 - t * 0.9) * 0.5 + 0.5;

    float  rippleField = wave1 * 0.40 + wave2 * 0.35 + wave3 * 0.25;
    float  ripplePeak  = smoothstep(0.75, 1.0, rippleField);

    // uvDisp: all center accents are sampled here, creating the refraction illusion.
    float2 uvDisp = uv + float2(
        (wave1 - 0.5) * p.rippleStrength * 1.2 + (wave3 - 0.5) * p.rippleStrength * 0.6,
        (wave2 - 0.5) * p.rippleStrength * 1.0 + (wave1 - 0.5) * p.rippleStrength * 0.4
    );

    // -----------------------------------------------------------------------
    // 2. IRIDESCENT SHEEN (unchanged from v4)
    // -----------------------------------------------------------------------
    float  sheenAngle = p.time * (6.28318 / 20.0);
    float2 sheenDir   = float2(cos(sheenAngle), sin(sheenAngle));
    float  sheenT     = dot(uvDisp - 0.5, sheenDir) * 0.5 + 0.5;

    float3 sheenA    = float3(p.tintR * 0.85, p.tintG * 0.90, p.tintB);
    float3 sheenB    = float3(p.tintR * 0.60, p.tintG * 1.30, p.tintB * 0.80);
    float3 sheen     = mix(sheenA, sheenB, sin(sheenT * 6.28318) * 0.5 + 0.5) * 0.018;

    // -----------------------------------------------------------------------
    // 3. SCREEN-WIDE CHROMATIC SHIMMER (unchanged from v4)
    // -----------------------------------------------------------------------
    float  chromaAmt = p.rippleStrength * ripplePeak * 0.9;
    float2 uvR = uvDisp + float2( chromaAmt * 0.9, -chromaAmt * 0.4);
    float2 uvB = uvDisp + float2(-chromaAmt * 0.7,  chromaAmt * 0.5);
    float  shimR = sin(uvR.x * 3.0 + uvR.y * 2.0 + t * 0.50) * 0.5 + 0.5;
    float  shimB = sin(uvB.x * 2.5 + uvB.y * 1.5 + t * 0.55 + 2.7) * 0.5 + 0.5;
    // Green channel (shimR + shimB) * 0.20 balances luminance — the previous
    // G = 0.0 created a blue-magenta cast that killed perceived desktop brightness.
    float3 shimmer = float3(shimR * p.tintR, (shimR + shimB) * 0.20, shimB * p.tintB)
                     * ripplePeak * p.shimmerIntensity * 0.40;

    // -----------------------------------------------------------------------
    // 3b. DESKTOP TEXTURE — sampled at the displaced/aberrated UVs computed above.
    //
    //  uvDisp: refraction-displaced UV (green channel — closest to undisplaced)
    //  uvR:    chromatic-red UV  (shifted +X, -Y)
    //  uvB:    chromatic-blue UV (shifted -X, +Y)
    //
    //  Sampling each channel from a different UV gives chromatic aberration on
    //  real desktop pixels at zero additional UV computation cost — uvR/uvB were
    //  already computed for the shimmer effect in section 3 above.
    // -----------------------------------------------------------------------
    float3 desktop = float3(
        desktopTex.sample(tex_s, uvR).r,
        desktopTex.sample(tex_s, uvDisp).g,
        desktopTex.sample(tex_s, uvB).b
    );

    // -----------------------------------------------------------------------
    // 4. FLOWING RAINBOW BORDER
    //
    //  Arc-length parameterization:
    //    The perimeter is divided into 4 edges with fractions proportional
    //    to their physical pixel length (top/bottom longer on wide screens).
    //    Gradient position travels clockwise from top-left, 0 → 1.
    //
    //    eh = top/bottom fraction  = AR / (2(AR+1))
    //    ev = left/right fraction  = 1  / (2(AR+1))
    //    2·eh + 2·ev = 1  ✓
    //
    //  Seamless corner blending:
    //    Rather than switching abruptly between edges at corners, we compute
    //    perimT for all four edges and average them weighted by (1/distance).
    //    At corners, adjacent edge perimT values converge to the same value,
    //    so the weighted average is smooth and produces no visible seam.
    // -----------------------------------------------------------------------
    float AR = p.aspectRatio;
    float eh = AR / (2.0 * (AR + 1.0));        // top/bottom fraction each
    float ev = 1.0 / (2.0 * (AR + 1.0));       // left/right fraction each

    // Pixel distances to each screen edge (0 = at edge)
    float dTop    = uv.y;
    float dBottom = 1.0 - uv.y;
    float dLeft   = uv.x;
    float dRight  = 1.0 - uv.x;
    float dMin    = min(min(dTop, dBottom), min(dLeft, dRight));

    // Perimeter position per edge (clockwise from top-left):
    //   Top:    0        → eh          (x: 0→1)
    //   Right:  eh       → eh+ev       (y: 0→1)
    //   Bottom: eh+ev    → 2·eh+ev     (x: 1→0)
    //   Left:   2·eh+ev  → 1.0         (y: 1→0)
    float tTop    = uv.x * eh;
    float tRight  = eh + uv.y * ev;
    float tBottom = eh + ev + (1.0 - uv.x) * eh;
    float tLeft   = 2.0*eh + ev + (1.0 - uv.y) * ev;

    // Inverse-distance blend (tiny eps prevents divide-by-zero at screen edge)
    const float eps = 0.0001;
    float wTop    = 1.0 / (dTop    + eps);
    float wRight  = 1.0 / (dRight  + eps);
    float wBottom = 1.0 / (dBottom + eps);
    float wLeft   = 1.0 / (dLeft   + eps);
    float wSum    = wTop + wRight + wBottom + wLeft;
    float perimT  = (tTop*wTop + tRight*wRight + tBottom*wBottom + tLeft*wLeft) / wSum;

    // Animate: subtract time so the gradient moves clockwise.
    // Flip sign to reverse direction. kLapTime = seconds per full lap.
    const float kLapTime = 5.0;
    float perimTAnim = fract(perimT - p.time / kLapTime);

    // Sample aurora palette
    float3 borderColor = auroraGradient(perimTAnim);

    // Organic shimmer: 3 slow saturation waves traveling around the border.
    // 18.849 ≈ 3 × 2π = 3 full saturation cycles around the perimeter.
    float organicWave = sin(perimTAnim * 18.849 + p.time * 0.22) * 0.10 + 0.90;
    float borderLum   = dot(borderColor, float3(0.299, 0.587, 0.114)); // luminance
    // Mix toward gray (desaturate) in troughs, toward full color at peaks.
    borderColor = mix(float3(borderLum), borderColor, organicWave);

    // Thickness falloff: 1.0 at screen edge → 0.0 at 0.030 UV (≈57px at 1920p).
    float borderFade = smoothstep(0.030, 0.001, dMin);

    // Bloom: extra brightness within the outermost ~0.008 UV (≈15px at 1920p),
    // simulating the glow of light bleeding off the surface toward the screen edge.
    // This adds to colour but not alpha, creating the "lit from within" appearance.
    float bloomBoost = smoothstep(0.008, 0.0, dMin) * 0.50;

    // -----------------------------------------------------------------------
    // 5. FLOATING SIGILS — ghost tuning
    //
    //  Size:     SDF input scaled ×2 → halves apparent diameter (~200px → ~100px)
    //  Drift:    ~0.030–0.035 UV/s → full-screen traverse in ~30 s
    //  Rotation: 0.251–0.377 rad/s → one full turn in 17–25 s
    //  Color:    near-white (0.88, 0.93, 1.00) — faint ghost, not a tinted logo
    //  Alpha:    ×0.10 cap + fade³ exponent — above 50% opacity only 29% of cycle
    // -----------------------------------------------------------------------
    float3 sigilColor = float3(0.0);
    float  sigilAlpha = 0.0;

    // Near-white ghost tint shared by all three sigils.
    // tintR/G/B are intentionally NOT used here — we want the sigils to read
    // as colourless spirits, not as tinted icons.
    const float3 ghostColor = float3(0.88, 0.93, 1.00);

    // Sigil A — hexagonal ward
    {
        float2 seed     = float2(0.137, 0.271);
        float2 drift    = normalize(hash22(seed + 0.5) - 0.5) * 0.033;   // ~30 s traverse
        float2 center   = fract(hash22(seed) + drift * p.time);
        float  rotation = p.time * 0.314;                                  // 20 s / full turn
        float  fade     = pow(sin(p.time * 0.209 + hash21(seed + 2.0) * 6.28318) * 0.5 + 0.5, 3.0);
        float  mask     = sigilA((uvDisp - center) * 2.0, rotation);      // ×2 → half size
        sigilColor += ghostColor * mask * fade * 0.10;
        sigilAlpha += mask * fade * 0.07;
    }

    // Sigil B — cardinal cross
    {
        float2 seed     = float2(0.651, 0.493);
        float2 drift    = normalize(hash22(seed + 0.5) - 0.5) * 0.027;   // ~37 s traverse
        float2 center   = fract(hash22(seed) + drift * p.time);
        float  rotation = p.time * -0.251;                                 // 25 s / full turn, CCW
        float  fade     = pow(sin(p.time * 0.171 + hash21(seed + 2.0) * 6.28318) * 0.5 + 0.5, 3.0);
        float  mask     = sigilB((uvDisp - center) * 2.0, rotation);
        sigilColor += ghostColor * mask * fade * 0.10;
        sigilAlpha += mask * fade * 0.07;
    }

    // Sigil C — octagram seal
    {
        float2 seed     = float2(0.319, 0.847);
        float2 drift    = normalize(hash22(seed + 0.5) - 0.5) * 0.035;   // ~29 s traverse
        float2 center   = fract(hash22(seed) + drift * p.time);
        float  rotation = p.time * 0.377;                                  // 16.7 s / full turn
        float  fade     = pow(sin(p.time * 0.233 + hash21(seed + 2.0) * 6.28318) * 0.5 + 0.5, 3.0);
        float  mask     = sigilC((uvDisp - center) * 2.0, rotation);
        sigilColor += ghostColor * mask * fade * 0.10;
        sigilAlpha += mask * fade * 0.07;
    }

    // -----------------------------------------------------------------------
    // 6. MOTES — 12, spread across full screen (unchanged from v4)
    // -----------------------------------------------------------------------
    float3 moteColor    = float3(0.0);
    float  moteAlphaAdd = 0.0;

    for (int i = 0; i < 12; i++) {
        float  fi   = float(i);
        float2 seed = float2(fi * 0.2137, fi * 0.3719 + 0.571);
        float2 basePos  = hash22(seed);
        float2 drift    = (hash22(seed + 0.31) - 0.5) * float2(0.05, -0.08);
        float  speed    = 0.025 + hash21(seed + 0.73) * 0.035;
        float2 motePos  = fract(basePos + drift * p.time * speed);

        float  phase     = hash21(seed + 1.37) * 6.28318;
        float  fadeSpeed = 0.785 + hash21(seed + 2.11) * 0.472;
        float  fade      = pow(sin(p.time * fadeSpeed + phase) * 0.5 + 0.5, 3.5);

        float  d      = length(uv - motePos);
        float  radius = 0.003 + hash21(seed + 3.51) * 0.002;
        float  blob   = exp(-(d * d) / (radius * radius));

        float3 mc = mix(float3(0.80, 0.95, 1.00),
                        float3(p.tintR, p.tintG, p.tintB), 0.25);
        moteColor    += mc  * blob * fade * 0.40;
        moteAlphaAdd += blob * fade * 0.15;
    }

    // -----------------------------------------------------------------------
    // 8. FINAL COLOR — desktop base + all Phase 1b effects on top.
    //
    //  Phase 1c change: alpha is always 1.0 (window is now opaque).
    //  The desktop texture provides the base layer; sheen, shimmer, sigils,
    //  motes, and the rainbow border all composite additively on top.
    //  baseAlpha is preserved in ShaderParams for struct compatibility but is
    //  no longer used here — the desktop replaces the old glass base.
    // -----------------------------------------------------------------------
    float3 colour = desktop + sheen + shimmer + sigilColor + moteColor;

    // Border: base glow + intrusion reactivity pulse.
    //
    // pulseAge: seconds since the last intercepted input event.
    //   -9999 default → pulseAge >> 0.20 → saturate(...) = 0 → pulseMult = 1.0
    //   On intrusion → pulseAge ≈ 0 → pulseMult = 1.30 (30% brighter border)
    //   After 200 ms → pulseAge = 0.20 → pulseMult eases back to 1.0
    //
    // saturate() = clamp(x, 0.0, 1.0) — Metal built-in.
    float pulseAge  = p.time - p.lastIntrusionT;
    float pulseMult = 1.0 + 0.30 * saturate(1.0 - pulseAge / 0.20);
    colour += borderColor * (borderFade * pulseMult + bloomBoost);
    colour  = clamp(colour, float3(0.0), float3(1.0));

    // alpha = 1.0: opaque window. The compositor sees no transparency here.
    return float4(colour, 1.0);
}
