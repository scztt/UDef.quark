UnitTest2("UDef", { |test|

	test.section("registration and identity") {
		var a = UDef(\utest_id, ar: { |x = 1| x });
		test.identical(UDef(\utest_id), a, "same name returns the same instance");
		test.checkIsKindOf(a, Singleton, "UDef is a Singleton");
		UDef(\utest_id).clear;
	};

	test.section("stores rate functions") {
		var f = { |x = 1| x * 2 };
		UDef(\utest_fn, ar: f);
		test.identical(UDef(\utest_fn).arFunc, f, "arFunc holds the ar function");
		test.valueIsNil(UDef(\utest_fn).krFunc, "krFunc is nil when not set");
		UDef(\utest_fn).clear;
	};

	test.section("arArgs reports names and defaults") {
		var args;
		UDef(\utest_args, ar: { |freq = 440, amp = 0.1| freq });
		args = UDef(\utest_args).arArgs;
		test.equals(args[\freq], 440, "default for freq");
		test.equals(args[\amp], 0.1, "default for amp");
		test.valueIsNil(UDef(\utest_args).krArgs, "krArgs nil when kr undefined");
		UDef(\utest_args).clear;
	};

	test.section("ar evaluates the function") {
		// a non-UGen ar function: UDef just forwards args and returns the value
		UDef(\utest_eval, ar: { |a = 0, b = 0| a + b });
		test.section("keyword args") {
			test.equals(UDef(\utest_eval).ar(a: 3, b: 4), 7, "forwards keyword args");
		};
		test.section("uses defaults") {
			test.equals(UDef(\utest_eval).ar(a: 10), 10, "b falls back to its default");
		};
		UDef(\utest_eval).clear;
	};

	test.section("evaluates inside a real UGen graph") {
		UDef(\utest_ugen, ar: { |freq = 440| SinOsc.ar(freq) });
		test.noError({
			SynthDef(\utest_ugen_def, {
				Out.ar(0, UDef(\utest_ugen).ar(freq: 220) * 0.1)
			}).asBytes;
		}, "UDef.ar splices into a SynthDef without error");
		UDef(\utest_ugen).clear;
	};

	test.section("wrap injects the base function as `func`") {
		var base, wrapped;
		base = UDef(\utest_base, ar: { |x = 2| x });
		wrapped = base.wrap(\times10, ar: { |func, mul = 10| func.value * mul });
		test.identical(UDef('utest_base.times10'), wrapped, "wrap registers name.wrapName");
		test.equals(wrapped.ar(mul: 5), 10, "base func (x=2) is bound, mul=5 => 10");
		test.equals(wrapped.ar, 20, "wrapper default mul=10 => 20");
		UDef(\utest_base).clear;
		UDef('utest_base.times10').clear;
	};

	test.section("multichannelExpand maps over array args") {
		var u = UDef(\utest_mce, ar: { |a = 0, b = 0| a + b });
		u.multichannelExpand = true;
		test.equals(u.ar(a: [1, 2, 3], b: 10), [11, 12, 13], "expands across array arg");
		u.clear;
	};

}).runOrAdd;
