// 303-style acid bass voice for bt1o1: one synth, always running

Engine_Bt1o1 : CroneEngine {

  var voice;

  *new { arg context, doneCallback;
    ^super.new(context, doneCallback);
  }

  alloc {
    var server = context.server;
    // a bundle's time: nil (right away) for no delay, else a time-stamped
    // bundle with delay 0 would arrive late
    var at = { arg delay; if(delay > 0, delay, nil) };

    SynthDef(\bt1o1, {
      arg out = 0, note = 36, legato = 0, gate = 0, t_trig = 0, acc = 0,
        wave = 0, cutoff = 400, res = 0.6, env_mod = 0.5, decay = 0.5,
        accent = 0.6, drive = 0.2, volume = 0.6;

      // slide: glide in semitones (like the 303's 1 V/oct CV), only on legato notes
      var hz = Lag.kr(note, legato * 0.06).midicps;
      var osc = Select.ar(wave, [Saw.ar(hz), Pulse.ar(hz, 0.5)]);

      // filter envelope: accented notes always decay fast
      var fdecay = Select.kr(acc, [decay, 0.2]);
      var fenv = EnvGen.kr(Env.perc(0.003, 1, 1, -4), t_trig, timeScale: fdecay);

      // accent sweep: the accent envelope smoothed, so accents in a row
      // push the filter further up; more with more resonance
      var aenv = EnvGen.kr(Env.perc(0.003, 0.2, 1, -4), t_trig) * acc;
      var sweep = Lag.kr(aenv, 0.02 + (res * 0.1));

      var fc = (cutoff * (2 ** ((fenv * env_mod * 4) + (sweep * accent * 3)))).clip(20, 18000);
      var filtered = MoogFF.ar(osc, fc, res * 3.6) * (1 + (res * 1.5));

      var amp = EnvGen.ar(Env.asr(0.003, 1, 0.01), gate) * (1 + (acc * accent));
      var g = 30 ** drive;
      var sig = (filtered * amp * g).tanh / (1 + (drive * 2));

      Out.ar(out, LeakDC.ar(sig * volume) ! 2);
    }).add;

    server.sync;

    voice = Synth.new(\bt1o1, [\out, context.out_b.index], context.xg);

    // note(delay, note, accent, legato): after `delay` seconds set the pitch;
    // legato 0 opens the gate and retriggers the envelopes, legato 1 glides
    // to the pitch and keeps the gate as it is
    this.addCommand("note", "ffii", { arg msg;
      var legato = msg[4];
      server.makeBundle(at.(msg[1]), {
        if(legato == 1, {
          voice.set(\legato, 1, \note, msg[2]);
        }, {
          voice.set(\legato, 0, \note, msg[2], \acc, msg[3], \gate, 1, \t_trig, 1);
        });
      });
    });

    // off(delay): close the gate after `delay` seconds
    this.addCommand("off", "f", { arg msg;
      server.makeBundle(at.(msg[1]), { voice.set(\gate, 0) });
    });

    [\cutoff, \res, \env_mod, \decay, \accent, \wave, \drive, \volume].do({ arg name;
      this.addCommand(name, "f", { arg msg; voice.set(name, msg[1]) });
    });
  }

  free {
    voice.free;
  }

}
