// ---- define the pseudo-UGen -------------------------------------------------
(
UDef(\pluck, ar: {
    |in, freq, decay, coef = 0.9, dist = 1, feedFunc = nil|
    
    // SETTINGS
    var samples = 44100;
    var bufferCount = 2;
    
    var buf = bufferCount.collect { LocalBuf(samples, 1) };
    var phase = Phasor.ar(1, 1, 0, samples);
    var delayTime = 6.collect {
        K2A.ar(freq)
            .lag(Rand(0.001, 0.02))
            * (\pluckDetune.kr(0.12) * LFDNoise3.ar(1/16)).midiratio
    }.reciprocal;
    var feed;
    var delays = delayTime / 1;
    var delayedPhase = phase - (delays * SampleRate.ir) + BlockSize.ir;
    var arc = Env.sine(1.8).ar(gate: Dust.ar(0.2)).lincurve(0, 1, 0, 1, 2);
    var arcDelay = (1/32) * [0.1, 1].resamp1(6) * arc;
    
    buf.do(_.clear);
    
    in = in + (
        -12.dbamp * [0.1, 1, 0.1].resamp1(6) * arc * CombC.ar(arc * in, 1, arcDelay, 0.2);
    ).sum;
    
    // Per-string feedback processing: leak DC, resonant EQ, allpass diffusion,
    // waveshaping, one-pole damping, and exponential decay. Override by passing
    // your own feedFunc(in, coef, delay, decay) with the same shape.
    feedFunc = feedFunc ?? {{
        |in, coef, delay, decay|
        in = LeakDC.ar(in);
        in = in.asArray;
        delay = delay.asArray;
        in.collect {
            |in, i|
            in = MidEQ.ar(
                in * -1.dbamp / 4,
                4.collect {
                    LFDNoise3.kr(\midEQRate.kr(2)).exprange(20, 8000)
                },
                0.6,
                \midEQ.kr(1).lag(0.5),
            ).sum;
            in = blend(
                in,
                -4.dbamp * AllpassC.ar(in, 1, 1 / 23, 0.52),
                LFDNoise3.ar(4).lincurve(-1, 1, 0, -6.dbamp, 4)
            );
            in = SoftClipAmp4.ar(in, dist);
            in = OnePole.ar(in, coef);
            in = (exp(log(0.001) * delay.wrapAt(i) / decay.abs)) * in;
        }
    }};
    
    feed = delayedPhase.collect {
        |readPhase, i|
        BufRd.ar(1, buf.wrapAt(i), readPhase, interpolation: 4);
    };
    
    feed = feedFunc.(feed, coef, delays, decay);
    feed.assertChannels(6);
    
    feed.size.do {
        |i|
        (in + feed).wrapAt(i).assertChannels(1);
        BufWr.ar((in + feed).wrapAt(i), buf.wrapAt(i), phase, 1);
    };
    
    feed.sum;
});
)

// ---- play it ----------------------------------------------------------------
// Excite the string with periodic impulses and let it ring.
(
{
    var trig = Impulse.ar(1) + Dust.ar(5.5);
    var sig = UDef(\pluck).ar(
        in: Decay.ar(trig, 0.1) * ClipNoise.ar * 0.5,
        freq: TChoose.ar(trig, DC.ar(2.3 * [40, 110, 166, 110, 112])).lag(0.01),
        decay: 26,
        coef: 0.95,
        dist: 1.2
    );
    sig = sig * 0.2;
    Splay.ar(sig ! 2).sum ! 2;    // mono core -> gentle stereo
}.play;
)

// ---- as a SynthDef, driven by a pattern -------------------------------------
(
SynthDef(\pluckString, {
    |out = 0, freq = 220, decay = 6, amp = 0.2, gate = 1|
    var trig = Impulse.ar(0);      // single excitation at note onset
    var env = EnvGen.kr(Env.asr(0.001, 1, 2), gate, doneAction: Done.freeSelf);
    var sig = UDef(\pluck).ar(in: trig, freq: freq, decay: decay, coef: 0.92, dist: 1.5);
    Out.ar(out, (sig * env * amp) ! 2);
}).add;
)

(
Pbind(
    instrument: \pluckString,
    degree: Pseq([0, 2, 4, 5, 7, 4, 2, 0], inf),
    octave: 4,
    dur: 0.5,
    decay: Pwhite(4, 9),
    amp: 0.25
).play;
)


/* ============================================================================
   FOUR VOICES FROM THE "LEOPARD" SYNTH  (reverse-engineered from JS1)

   These reproduce the pluck core of the leopard synth in JS1's final version
   (acid-wet-stone.scd): a synthetic click/noise burst excites the string, and
   the "pluck-differencing" idiom runs two copies at different decay times and
   subtracts them (sigA - sigB) to pull out the in-between resonance. Each Ndef
   uses the coef / decayMult / dist / boost values from a different JS1 state.

   The original chain used HardCompress + NHHall (both private). Here that tail
   is rebuilt with stock UGens: JPverb for the reverb and Compander for the
   glue compression -- the "similar thing" you asked about.

   The reverb tail is stock UGens only. The pluck UDef above uses SoftClipAmp4
   (BerlachUGens / sc3-plugins) -- same requirement as the UDef itself.
   Boot the server, then evaluate the setup block, then any voice.
   ============================================================================ */

// ---- shared building blocks -------------------------------------------------
(
// A click/noise excitation: sparse impulses shaped into short bright bursts.
~excite = { |density = 3, bright = 6000, level = 0.5|
    var trig = Dust.ar(density) + Impulse.ar(density / 4);
    var burst = Decay2.ar(trig, 0.001, 0.03) * PinkNoise.ar;
    burst = burst + (Decay2.ar(trig, 0.0005, 0.008) * ClipNoise.ar * 0.6);
    LPF.ar(HPF.ar(burst, 200), bright) * level;
};

// The leopard pluck core: excite -> two plucks at decay*[1,k] -> difference.
// freqs is an array of candidate pitches; a new one is chosen on each impulse.
~leopardVoice = { |in, freqs, coef, decayMult, dist, boostDb = 0, decayRatio = 2.66|
    var chooseTrig = Impulse.ar(1/8) + Dust.ar(2);
    2.collect {
        var freq = TChoose.ar(chooseTrig, DC.ar(freqs));
        var sigA = UDef(\pluck).ar(in: in, freq: freq, decay: 3 * decayMult, coef: coef, dist: dist);
        var sigB = UDef(\pluck).ar(in: in, freq: freq, decay: 3 * decayRatio * decayMult, coef: coef, dist: dist);
        boostDb.dbamp * (sigA - sigB)
    };
};

// Reverb tail: Compander glue (in place of HardCompress) + JPverb (in place of
// NHHall), plus a darker second reverb send like the original's LPF'd tail.
~leopardTail = { |sig, revAmp = 0.1, t60 = 6|
    sig = sig + (revAmp * JPverb.ar(sig.sum, t60: t60, damp: 0.3, size: 1.6, high: 0.6, highcut: 6000));
    sig = Compander.ar(sig, sig, thresh: 0.3, slopeBelow: 1, slopeAbove: 1/200, clampTime: 0.01, relaxTime: 0.1);
    sig = sig + (revAmp * 0.5 * JPverb.ar(LPF.ar(sig, 400).sum, t60: t60 * 1.6, damp: 0.6, size: 2.4));
    Limiter.ar(sig * 0.9);
};
)

// ---- Voice 1: state-5 -- mellow, long-ringing, sparse -----------------------
// coef 0.82, long decayMult (~19), low boost. Slow chiming plucks.
(
Ndef(\leopard1, {
    var in = ~excite.(density: 1.5, bright: 5000, level: 0.5);
    var sig = ~leopardVoice.(
        in: in,
        freqs: [55, 82.4, 110, 165] * 1.5,     // low, sparse pitch set
        coef: LFTri.ar(0.2).exprange(0.80, 0.86),
        decayMult: 19,
        dist: 0.9,
        boostDb: -6
    );
    ~leopardTail.(sig, revAmp: 0.18, t60: 9);
}).play;
)

// ---- Voice 2: state-2 -- bright, augmented, animated damping ----------------
// coef sweeps 0.72..0.99, decayMult ~8. Restless, metallic-to-woody morph.
(
Ndef(\leopard2, {
    var in = ~excite.(density: 4, bright: 9000, level: 0.45);
    var sig = ~leopardVoice.(
        in: in,
        freqs: (Scale.augmented.degrees + 60).midicps,    // augmented harmony
        coef: LFTri.ar(LFDNoise3.ar(1/4).exprange(0.25, 4)).exprange(0.72, 0.99),
        decayMult: LFDNoise3.kr(LFDNoise3.kr(0.5).exprange(0.25, 2)).exprange(5.6, 9.6),
        dist: 0.9,
        boostDb: -4
    );
    ~leopardTail.(sig, revAmp: 0.14, t60: 5);
}).play;
)

// ---- Voice 3: state-4 -- dense, driven, high boost --------------------------
// coef 0.93..0.99, decayMult 6.6..10, pluckDist 0.98, hot boost. Aggressive.
(
Ndef(\leopard3, {
    var in = ~excite.(density: 8, bright: 11000, level: 0.5);
    var sig = ~leopardVoice.(
        in: in,
        freqs: (Scale.hexSus.degrees + 60).midicps,      // sus/quartal color
        coef: LFTri.ar(LFDNoise3.ar(1/4).exprange(0.25, 4)).exprange(0.93, 0.99),
        decayMult: LFDNoise3.kr(LFDNoise3.kr(0.25).exprange(0.25, 2)).exprange(6.6, 10),
        dist: 0.98,
        boostDb: 6
    );
    ~leopardTail.(sig, revAmp: 0.1, t60: 4);
}).play;
)

// ---- Voice 4: state-6 -- huge, slow, cavernous ------------------------------
// coef 0.82, very long decayMult (~19+), big reverb. Bell-like, distant.
(
Ndef(\leopard4, {
    var in = ~excite.(density: 0.8, bright: 4000, level: 0.6);
    var sig = ~leopardVoice.(
        in: in,
        freqs: (Scale.diminished.degrees + 48).midicps,   // diminished, low
        coef: 0.82,
        decayMult: LFDNoise3.kr(0.1).range(18, 26),
        dist: 0.85,
        boostDb: -8,
        decayRatio: 3.2
    );
    ~leopardTail.(sig, revAmp: 0.28, t60: 14);
}).play;
)

// stop everything
// Ndef(\leopard1).clear; Ndef(\leopard2).clear; Ndef(\leopard3).clear; Ndef(\leopard4).clear;
