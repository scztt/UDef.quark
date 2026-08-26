UDef : Singleton {
    var <>arFunc, <>krFunc, <>irFunc;
    var <path, <>multichannelExpand = false;
    
    *new {
        |name, ar, kr, ir|
        ^super.new(name, ar, kr, ir)
    }
    
    *flopKwargs {
        |kwargs|
        kwargs = kwargs.clump(2).flop;
        ^kwargs[1].flop.collect {
            |v|
            [kwargs[0], v].flop.flatten(1)
        }
    }
    
    set {
        |ar, kr, ir|
        
        path = thisProcess.nowExecutingPath ?? path;
        
        if (ar.notNil) {
            this.arFunc_(ar)
        };
        
        if (kr.notNil) {
            this.krFunc_(kr)
        };
        
        if (ir.notNil) {
            this.irFunc_(ir)
        };
    }
    
    arArgs {
        ^(arFunc !? {
            [arFunc.def.argNames, arFunc.def.prototypeFrame].flop.flatten.asEvent
        })
    }
    
    krArgs {
        ^(krFunc !? {
            [krFunc.def.argNames, krFunc.def.prototypeFrame].flop.flatten.asEvent
        })
    }
    
    irArgs {
        ^(irFunc !? {
            [irFunc.def.argNames, irFunc.def.prototypeFrame].flop.flatten.asEvent
        })
    }
    
    ar_ { |func| this.arFunc = func }
    kr_ { |func| this.krFunc = func }
    ir_ { |func| this.irFunc = func }
    
    wrap {
        |wrapName, ar, kr, ir|
        var newName = "%.%".format(name, wrapName).asSymbol;
        
        ar = ar !? {
            arFunc !? {
                ar.partialApplication(func: arFunc)
            }
        };
        kr = kr !? {
            krFunc !? {
                kr.partialApplication(func: krFunc)
            }
        };
        ir = ir !? {
            irFunc !? {
                ir.partialApplication(func: irFunc)
            }
        };
        
        ^UDef(newName, ar: ar, kr: kr, ir: ir)
    }
    
    multichannelPerform {
        |function, args, kwargs|
        var size;
        
        args = args.flop;
        kwargs = UDef.flopKwargs(kwargs);
        size = max(args.size, kwargs.size);
        ^size.collect {
            |i|
            function.performArgs(\value, args.wrapAt(i), kwargs.wrapAt(i));
        }
    }
    
    ar {
        |...args, kwargs|
        if (multichannelExpand) {
            ^this.multichannelPerform(arFunc, args, kwargs)
        } {
            ^arFunc.performArgs(\value, args, kwargs);
        }
    }
    
    kr {
        |...args, kwargs|
        if (multichannelExpand) {
            ^this.multichannelPerform(krFunc, args, kwargs)
        } {
            ^krFunc.performArgs(\value, args, kwargs);
        }
    }
    
    ir {
        |...args, kwargs|
        if (multichannelExpand) {
            ^this.multichannelPerform(irFunc, args, kwargs)
        } {
            ^irFunc.performArgs(\value, args, kwargs);
        }
    }
    
    open {
        if (path.notNil) {
            Document.open(path.asString);
        }
    }
}
