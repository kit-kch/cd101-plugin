/**
Copyright: Guillaume Piolat 2015-2017
Copyright: Ethan Reker 2017
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module gui;

import dplug.gui;
import dplug.flatwidgets;
import dplug.client;
import dplug.canvas;

import main;

// Plugin GUI, based on FlatBackgroundGUI.
// This allows to use knobs rendered with Knobman
class ClipitGUI : FlatBackgroundGUI!("background.png",

                                     // In development, enter here the absolute path to the gfx directory.
                                     // This allows to reload background images at debug-time when pressing the RETURN key.
                                     `/home/myuser/my/path/to/Dplug/examples/clipit/gfx/`)
{
public:
nothrow:
@nogc:

    ClipitClient _client;

    this(ClipitClient client)
    {
        _client = client;

        static immutable float[7] ratios = [0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 1.75f, 2.0f];
        super( makeSizeConstraintsDiscrete(500, 719, ratios) );

        // Sets the number of pixels recomputed around dirtied controls.
        // Since we aren't using PBR we can set this value to 0 to save
        // on resources.
        // If you are mixing PBR and flat elements, you may want to set this
        // to a higher value such as 20.
        setUpdateMargin(0);

        // All resources are bundled as a string import.
        // You can avoid resource compilers that way.
        // The only cost is that each resource is in each binary, this creates overhead 
        OwnedImage!RGBA knobImage = loadOwnedImage(cast(ubyte[])(import("knob.png")));

        // In the ClipIt case, all images have 101 frames.
        int numFrames = 101;

        // Creates all widgets and adds them as children to the GUI
        // widgets are not visible until their positions have been set, in reflow.

        _attackKnob = mallocNew!UIFilmstripKnob(context(), cast(FloatParameter) _client.param(paramAttack), knobImage, numFrames);
        addChild(_attackKnob);

        _decayKnob = mallocNew!UIFilmstripKnob(context(), cast(FloatParameter) _client.param(paramDecay), knobImage, numFrames);
        addChild(_decayKnob);

        _sustainKnob = mallocNew!UIFilmstripKnob(context(), cast(FloatParameter) _client.param(paramSustain), knobImage, numFrames);
        addChild(_sustainKnob);

        _releaseKnob = mallocNew!UIFilmstripKnob(context(), cast(FloatParameter) _client.param(paramRelease), knobImage, numFrames);
        addChild(_releaseKnob);
        
        _filterKnob = mallocNew!UIFilmstripKnob(context(), cast(FloatParameter) _client.param(paramFilter), knobImage, numFrames);
        addChild(_filterKnob);
    }

    override void reflow()
    {
        super.reflow();

        int W = position.width;
        int H = position.height;

        float S = W / cast(float)(context.getDefaultUIWidth());

        _attackKnob.position  = rectangle(70, 101, 128, 128).scaleByFactor(S);
        _sustainKnob.position   = rectangle(308, 101, 128, 128).scaleByFactor(S);
        _decayKnob.position = rectangle(70, 320, 128, 128).scaleByFactor(S);
        _releaseKnob.position = rectangle(308, 320, 128, 128).scaleByFactor(S);
        _filterKnob.position  = rectangle(70, 539, 128, 128).scaleByFactor(S);
    }

private:
    UIFilmstripKnob _attackKnob;
    UIFilmstripKnob _decayKnob;
    UIFilmstripKnob _sustainKnob;
    UIFilmstripKnob _releaseKnob;
    UIFilmstripKnob _filterKnob;
}
