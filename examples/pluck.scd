// ---- define the pseudo-UGen -------------------------------------------------
(
UDef(\pluck, ar: {
    |in, freq, decay, coef = 0.9, dist = 1, pluckDetune = 0.12, midEQ = 1, midEQRate = 2, feedFunc = nil|
    
    // SETTINGS
    var samples = 44100;
    var bufferCount = 2;
    
    var buf = bufferCount.collect { LocalBuf(samples, 1) };
    var phase = Phasor.ar(1, 1, 0, samples);
    var delayTime = 6.collect {
        K2A.ar(freq)
            .lag(Rand(0.001, 0.02))
            * (pluckDetune * LFDNoise3.ar(1/16)).midiratio
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
        |in, coef, delay, decay, midEQ, midEQRate|
        in = LeakDC.ar(in);
        in = in.asArray;
        delay = delay.asArray;
        in.collect {
            |in, i|
            in = MidEQ.ar(
                in * -1.dbamp / 4,
                4.collect {
                    LFDNoise3.kr(midEQRate).exprange(20, 8000)
                },
                0.6,
                midEQ.lag(0.5),
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
    
    feed = feedFunc.(feed, coef, delays, decay, midEQ, midEQRate);
    feed.assertChannels(6);
    
    feed.size.do {
        |i|
        (in + feed).wrapAt(i).assertChannels(1);
        BufWr.ar((in + feed).wrapAt(i), buf.wrapAt(i), phase, 1);
    };
    
    feed.sum;
});
)

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
~leopardVoice = { |in, freqs, coef, decayMult, dist, boostDb = 0, decayRatio = 2.66,
    midEQ = 4, midEQRate = 2, pluckDetune = 0.12|
    var chooseTrig = Impulse.ar(1/8) + Dust.ar(1);
    2.collect {
        var freq = TChoose.ar(chooseTrig, DC.ar(freqs));
        var sigA = UDef(\pluck).ar(in: in, freq: freq, decay: 3 * decayMult, coef: coef, dist: dist,
            midEQ: midEQ, midEQRate: midEQRate, pluckDetune: pluckDetune);
        var sigB = UDef(\pluck).ar(in: in, freq: freq, decay: 3 * decayRatio * decayMult, coef: coef, dist: dist,
            midEQ: midEQ, midEQRate: midEQRate, pluckDetune: pluckDetune);
        boostDb.dbamp * (sigA - sigB)
    };
};

// Reverb tail: Compander glue (in place of HardCompress) + JPverb (in place of
// NHHall), plus a darker second reverb send like the original's LPF'd tail.
~leopardTail = { |sig, revAmp = 0.1, t60 = 6|
    sig = sig + (revAmp * JPverb.ar(-40.dbamp * sig.sum, t60: t60, damp: 0.3, size: 1.6, high: 0.6, highcut: 6000));
    sig = Compander.ar(
        sig, sig[0], 
        thresh: -20.dbamp, 
        slopeBelow: 1, 
        slopeAbove: 1/200, 
        clampTime: 0.01, 
        relaxTime: 2.1
    );
    sig = sig + (revAmp * JPverb.ar(LPF.ar(-40.dbamp * sig, 400).sum, t60: t60 * 1.6, damp: 0.6, size: 2.4));
    Limiter.ar(sig * 0.9);
};
)

// ---- Voice 1: state-5 -- mellow, long-ringing, sparse -----------------------
(
Ndef(\leopard1, {
    var in = ~excite.(density: 1.5, bright: 5000, level: 0.5);
    var sig = ~leopardVoice.(
        in: in,
        freqs: [55, 50, 50.2, 65] * 1,     // low, sparse pitch set
        coef: LFTri.ar(0.2).exprange(0.80, 0.86),
        decayMult: 19,
        dist: 0.9,
        boostDb: 6,
        midEQ: 4, midEQRate: 3
    );
    ~leopardTail.(sig, revAmp: 0.18, t60: 9);
}).play;
)

// ---- Voice 2: state-2 -- bright, augmented, animated damping ----------------
// coef sweeps 0.72..0.99, decayMult ~8. Restless, metallic-to-woody morph.
(
Ndef(\leopard2, {
    var in = ~excite.(density: 1, bright: 9000, level: 0.45);
    var sig = ~leopardVoice.(
        in: in,
        freqs: (Scale.augmented.degrees + 40).midicps,    // augmented harmony
        coef: LFTri.ar(LFDNoise3.ar(1/4).exprange(0.25, 4)).exprange(0.52, 0.99),
        decayMult: LFDNoise3.kr(LFDNoise3.kr(0.5).exprange(0.25, 2)).exprange(5.6, 19.6),
        dist: 0.96,
        boostDb: 4,
        midEQ: 6, midEQRate: 4, pluckDetune: 0.5
    );
    ~leopardTail.(sig, revAmp: 0.6, t60: 15);
}).play;
)

// ---- Voice 3: state-4 -- dense, driven, high boost --------------------------
(
Ndef(\leopard3, {
    var in = ~excite.(density: 8, bright: 11000, level: 0.5);
    var sig = ~leopardVoice.(
        in: in,
        freqs: (Scale.hexSus.degrees + 30).midicps,      // sus/quartal color
        coef: LFTri.ar(LFDNoise3.ar(1/4).exprange(1/8, 1)).exprange(0.33, 0.99),
        decayMult: LFDNoise3.kr(LFDNoise3.kr(0.25).exprange(0.25, 2)).exprange(6.6, 10),
        dist: 0.98,
        boostDb: 6,
        midEQ: 3.7, midEQRate: 1
    );
    ~leopardTail.(sig, revAmp: 0.1, t60: 4);
}).play;
)

// ---- Voice 4: state-6 -- huge, slow, cavernous ------------------------------
(
Ndef(\leopard4, {
    var in = ~excite.(density: 1.8, bright: 4000, level: 0.6);
    var sig = ~leopardVoice.(
        in: in,
        freqs: (Scale.diminished.degrees[0,2..] + 48).midicps,   // diminished, low
        coef: 0.32,
        decayMult: LFDNoise3.kr(0.1).range(18, 26),
        dist: 1.0,
        boostDb: -8,
        decayRatio: 3.2,
        midEQ: 2, midEQRate: 1
    );
    ~leopardTail.(sig, revAmp: 0.28, t60: 14);
}).play;
)

// stop everything
// Ndef(\leopard1).clear; Ndef(\leopard2).clear; Ndef(\leopard3).clear; Ndef(\leopard4).clear;
