/**
Copyright: Guillaume Piolat 2015-2017.
Copyright: Ethan Reker 2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module main;

import std.math;
import core.stdc.stdio;

import dplug.core,
       dplug.client;

import gui;
import ftdi;

// This define entry points for plugin formats, 
// depending on which version identifiers are defined.
mixin(pluginEntryPoints!ClipitClient);

enum : int
{
    paramAttack,
    paramDecay,
    paramSustain,
    paramRelease,
    paramFilter
}

/**
    A small clipper plug-in named ClipIt!

    It demonstrates:
         - parameters
         - I/O settings (mono or stereo)
         - presets
         - buffer-split
         - using biquads from dplug:dsp
         - resizeable UI
         - use of dplug:flat-widgets

    To go further:
        - Examples:     Distort and Template.
        - FAQ:          https://dplug.org/tutorials
        - Inline Doc:   https://dplug.dpldocs.info/dplug.html
*/
final class ClipitClient : dplug.client.Client
{
private:
    bool _spiOK = false;
    SPIDriver _spi;
    SynthParams _lastParams;
    bool _trigger = false;
    FILE* _fp;

public:
nothrow:
@nogc:

    this()
    {
        _spiOK = _spi.open();
        _fp = fopen("debug.txt", "w");
        fprintf(_fp, "SPI Status: %s\n", _spiOK ? "ok".ptr : "fail".ptr);
        fflush(_fp);
    }

    override PluginInfo buildPluginInfo()
    {
        // Plugin info is parsed from plugin.json here at compile time.
        // Indeed it is strongly recommended that you do not fill PluginInfo 
        // manually, else the information could diverge.
        static immutable PluginInfo pluginInfo = parsePluginInfo(import("plugin.json"));
        return pluginInfo;
    }

    // This is an optional overload, default is zero parameter.
    // Caution when adding parameters: always add the indices
    // in the same order as the parameter enum.
    override Parameter[] buildParameters()
    {   
        auto params = makeVec!Parameter();
        params ~= mallocNew!LinearFloatParameter(paramAttack, "attack", "ms", 3.2f, 409.6f, 10.0f) ;
        params ~= mallocNew!LinearFloatParameter(paramDecay, "decay", "ms", 3.2f, 409.6, 30.0f) ;
        params ~= mallocNew!LinearFloatParameter(paramSustain, "sustain", "%", 0.0, 100.0f, 20.0f) ;
        params ~= mallocNew!LinearFloatParameter(paramRelease, "release", "ms", 3.2f, 409.6f, 100.0f) ;
        params ~= mallocNew!LinearFloatParameter(paramFilter, "filter", "Hz", 0.0f, 20000.0f, 1000.0f) ;
        return params.releaseData();
    }

    override LegalIO[] buildLegalIO()
    {
        auto io = makeVec!LegalIO();
        io ~= LegalIO(0, 0);
        return io.releaseData();
    }

    override int maxFramesInProcess() pure const
    {
        return 32; // samples only processed by a maximum of 32 samples
    }

    override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) 
    {
        _spi.close();
        _spiOK = _spi.open();
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames, TimeInfo info)
    {
        auto params = getParameters();
        params.noteNumber = _lastParams.noteNumber;

        // Full Update
        bool updateCfg = (params != _lastParams);
        bool updated = false;

        foreach (MidiMessage msg; getNextMidiMessages(frames))
        {
            if (msg.isNoteOn())
            {
                fprintf(_fp, "Note on (SPI %s)\n", _spiOK ? "OK".ptr : "FAIL".ptr);
                fflush(_fp);
                params.noteNumber = msg.noteNumber;
                updateCfg = (params != _lastParams);
                _trigger = true;
                if (updateCfg)
                    updateConfig(params);
                else
                    updateTrigger();
                updated = true;
            }
            else if (msg.isNoteOff() || msg.isAllNotesOff() || msg.isAllSoundsOff())
            {
                fprintf(_fp, "Note off (SPI %s)\n", _spiOK ? "OK".ptr : "FAIL".ptr);
                fflush(_fp);
                _trigger = false;
                if (updateCfg)
                    updateConfig(params);
                else
                    updateTrigger();
                updated = true;
            }
        }

        if (!updated && updateCfg)
            updateConfig(params);
    }

    override IGraphics createGraphics()
    {
        return mallocNew!ClipitGUI(this);
    }

    SynthParams getParameters() @nogc nothrow
    {
        SynthParams result;
        result.a = readParam!float(paramAttack);
        result.d = readParam!float(paramDecay);
        result.s = readParam!float(paramSustain);
        result.r = readParam!float(paramRelease);
        result.filter = readParam!float(paramFilter);
        return result;
    }

    // FIXME: Writeconfig stalls for 3.125ms. Split into two calls
    void updateConfig(SynthParams params) @nogc nothrow
    {
        SynthConfig cfg;
        cfg.trigger = _trigger;
        cfg.setOscillatorHz(cast(ushort)convertMIDINoteToFrequency(params.noteNumber));
        cfg.setFilterHz(cast(ushort)params.filter);
        cfg.setADSR(params.a, params.d, params.s / 100.0, params.r);
        fprintf(_fp, "Config: %d %d %d %d %d %d %d (SPI %s)\n", cfg.adsr_ai, cfg.adsr_di, cfg.adsr_s, cfg.adsr_ri, cfg.osc_count, cfg.filter_a, cfg.filter_b, _spiOK ? "OK".ptr : "FAIL".ptr);
        fflush(_fp);
        if (_spiOK)
            _spi.writeConfig(cfg);
        _lastParams = params;
    }

    void updateTrigger() @nogc nothrow
    {
        fprintf(_fp, "updateTrigger (SPI %s)\n", _spiOK ? "OK".ptr : "FAIL".ptr);
        fflush(_fp);
        if (_spiOK)
            auto result = _spi.writeTrigger(_trigger);
    }
}

struct SynthParams
{
    int noteNumber;
    float a, d, s, r;
    float filter;
}
