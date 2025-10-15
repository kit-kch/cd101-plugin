import std;

import ftdi;

int main(string[] args)
{
    if (args.length < 2)
        return -1;
    
    SPIDriver dev;
    enforce(dev.open(), "Could not find USB device");
    if (args[1] == "trig")
    {
        if (args.length > 2)
            return -1;

        while (true)
        {
            write("Press enter to enable trigger");
            stdout.flush();
            readln();
            enforce(dev.writeTrigger(true));
            write("Press enter to disable trigger");
            stdout.flush();
            readln();
            enforce(dev.writeTrigger(false));
        }
    }
    else
    {
        enforce(args.length == 7, "Usage: ./cd101 HZ FILT A D S R");
        SynthConfig cfg;
        cfg.setOscillatorHz(args[1].to!ushort);
        cfg.setFilterD(args[2].to!double);
        cfg.setADSR(args[3].to!double, args[4].to!double, args[5].to!double, args[6].to!double);
        dev.writeConfig(cfg);
        writefln("OSC: %d FILT_A: %d, FILT_B: %d, AI: %d, DI: %d, S: %d, RI: %d",
            cfg.osc_count, cfg.filter_a, cfg.filter_b, cfg.adsr_ai, cast(int8_t)cfg.adsr_di, cfg.adsr_s, cast(int8_t)cfg.adsr_ri);
    }

    dev.close();
    return 0;
}