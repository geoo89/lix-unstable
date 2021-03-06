module graphic.internal;

/* Graphics library, loads spritesheets and offers them for use via string
 * lookup. This does not handle Lix terrain, special objects, or L1/L2 graphics
 * sets. All of those are handled by the tile library.
 */

import basics.cmdargs;
import file.filename;
import graphic.cutbit;
import graphic.internal.getters;
import graphic.internal.vars;

void initialize(Runmode runmode)
{
    nullCutbit = new Cutbit(cast (Cutbit) null);

    final switch (runmode) {
        case Runmode.VERIFY:
            dontWantRecoloredGraphics = true;
            break;
        case Runmode.INTERACTIVE:
        case Runmode.EXPORT_IMAGES:
            break;
        case Runmode.PRINT_AND_EXIT:
            assert (false);
    }
}

void initializeScale(float scale) { implSetScale(scale); }

const(Cutbit) getInternal    (Filename fn) { return getInternalMutable  (fn); }
const(Cutbit) getLixSpritesheet (Style st) { return implGetLixSprites   (st); }
const(Cutbit) getPanelInfoIcon  (Style st) { return implGetPanelInfoIcon(st); }
const(Cutbit) getSkillButtonIcon(Style st) { return implGetSkillButton  (st); }

const(Alcol3D) getAlcol3DforStyle(Style st) { return implGetAlcol3D(st); }

const(typeof(graphic.internal.vars.eyesOnSpritesheet)) eyesOnSpritesheet()
{
    assert (graphic.internal.vars.eyesOnSpritesheet,
        "Generate at least one Lix style first before finding eyes."
        ~ " We require this for efficiency to lock the bitmap only once.");
    return graphic.internal.vars.eyesOnSpritesheet;
}
