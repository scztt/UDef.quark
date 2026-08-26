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
                \midEQ.kr(4).lag(0.5),
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
    var trig = Impulse.ar(1) + Dust.ar(0.5);
    var sig = UDef(\pluck).ar(
        in: trig * 0.5,
        freq: TChoose.ar(trig, DC.ar([110, 165, 220, 330])),
        decay: 6,
        coef: 0.92,
        dist: 1.5
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
