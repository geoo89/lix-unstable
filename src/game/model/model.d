module game.model.model;

/* Everything from the physics collected in one class, according to MVC.
 *
 * Does not manage the replay. Whenever you want to advance physics, cut off
 * from the replay the correct hunk, and feed it one-by-one to the model.
 *
 * To do automated replay checking, don't use a model directly! Make a nurse,
 * and have her check the replay!
 */

import std.algorithm;
import std.array;
import std.conv;
import std.range;

import basics.help; // len
import net.repdata;
import hardware.tharsis;
import game.effect;
import game.physdraw;
import game.replay;
import game.tribe;
import game.model.state;
import game.model.init;
import graphic.gadget;
import graphic.torbit;
import hardware.sound;
import level.level;
import lix;
import net.permu;
import tile.phymap;

class GameModel {
private:
    GameState     _cs;            // owned (current state)
    PhysicsDrawer _physicsDrawer; // owned
    EffectManager _effect;        // not owned. May be null.

package: // eventually delete cs() and alias cs this;
    @property inout(GameState) cs() inout { return _cs; }

public:
    // This remembers the effect manager, but not anything else.
    // We don't own the effect manager.
    this(in Level level, in Style[] tribesToMake,
         in Permu permu, EffectManager ef)
    {
        _effect = ef;
        _cs = newZeroState(level, tribesToMake, permu,
            ef ? ef.localTribe : Style.garden // only to make hatches blink
        );
        _physicsDrawer = new PhysicsDrawer(_cs.land, _cs.lookup);
        finalizePhyuAnimateGadgets();
    }

    void takeOwnershipOf(GameState s)
    {
        _cs = s;
        _physicsDrawer.rebind(_cs.land, _cs.lookup);
        finalizePhyuAnimateGadgets();
    }

    void applyChangesToLand() {
        _physicsDrawer.applyChangesToLand(_cs.update);
    }

    /* Design burden: These methods must all be called in the correct order:
     *  1. incrementPhyu()
     *  2. applyReplayData(...) for each piece of data from that update
     *  3. advance()
     * Refactor this eventually!
     */

    void incrementPhyu()
    {
        ++_cs.update;
    }

    void applyReplayData(
        ref const(ReplayData) i,
        in Style tribeStyle
    ) {
        assert (i.update == _cs.update,
            "increase update manually before applying replay data");
        implApplyReplayData(i, tribeStyle);
    }

    void advance()
    {
        updateNuke(); // sets lixHatch = 0, thus affects spawnLixxiesFromHatch
        spawnLixxiesFromHatches();
        updateLixxies();
        finalizePhyuAnimateGadgets();
        if (_cs.overtimeRunning && _cs.multiplayer && _effect)
            _effect.announceOvertime(_cs.update, _cs.overtimeAtStartInPhyus);
    }

    void dispose()
    {
        if (_physicsDrawer)
            _physicsDrawer.dispose();
        _physicsDrawer = null;
    }

private:

    lix.OutsideWorld
    makeGypsyWagon(Tribe tribe, in int lixID)
    {
        OutsideWorld ow;
        ow.state         = _cs;
        ow.physicsDrawer = _physicsDrawer;
        ow.effect        = _effect;
        ow.tribe         = tribe;
        ow.lixID         = lixID;
        return ow;
    }

    void
    implApplyReplayData(
        ref const(ReplayData) i,
        in Style tribeStyle,
    ) {
        immutable upd = _cs.update;
        auto tribe = tribeStyle in _cs.tribes;
        if (! tribe)
            // Ignore bogus data that can come from anywhere
            return;
        if (tribe.nukePressed || _cs.nuking)
            // Game rule: After you call for the nuke, you may not assign
            // other things, nuke again, or do whatever we allow in the future.
            // During the nuke, nobody can assign or save lixes.
            return;
        if (i.isSomeAssignment) {
            // never assert based on the content in ReplayData, which may have
            // been a maleficious attack from a third party, carrying a lix ID
            // that is not valid. If bogus data comes, do nothing.
            if (i.toWhichLix < 0 || i.toWhichLix >= tribe.lixlen)
                return;
            Lixxie lixxie = tribe.lixvec[i.toWhichLix];
            assert (lixxie);
            if (lixxie.priorityForNewAc(i.skill) <= 1
                || tribe.skills[i.skill] == 0
                || (lixxie.facingLeft  && i.action == RepAc.ASSIGN_RIGHT)
                || (lixxie.facingRight && i.action == RepAc.ASSIGN_LEFT))
                return;
            // Physics
            ++(tribe.skillsUsed);
            if (tribe.skills[i.skill] != lix.skillInfinity)
                --(tribe.skills[i.skill]);
            OutsideWorld ow = makeGypsyWagon(*tribe, i.toWhichLix);
            lixxie.assignManually(&ow, i.skill);

            if (_effect) {
                _effect.addSound(upd, tribe.style, i.toWhichLix, Sound.ASSIGN);
                _effect.addArrow(upd, tribe.style, i.toWhichLix,
                                 lixxie.ex, lixxie.ey, i.skill);
            }
        }
        else if (i.action == RepAc.NUKE) {
            tribe.nukePressedSince = upd;
            if (_effect)
                _effect.addSound(upd, tribe.style, 0, Sound.NUKE);
        }
    }

    void spawnLixxiesFromHatches()
    {
        foreach (int teamNumber, Tribe tribe; _cs.tribes) {
            if (tribe.lixHatch == 0
                || _cs.update < 60
                || _cs.update < tribe.updatePreviousSpawn + tribe.spawnint)
                continue;
            // the only interesting part of OutsideWorld right now is the
            // lookupmap inside the current state. Everything else will be
            // passed anew when the lix are updated.
            auto ow = makeGypsyWagon(tribe, tribe.lixlen);
            tribe.spawnLixxie(&ow);
        }
    }

    void updateNuke()
    {
        if (! _cs.nuking)
            return;
        foreach (int tribeID, tribe; _cs.tribes) {
            tribe.lixHatch = 0;
            foreach (int lixID, lix; tribe.lixvec.enumerate!int) {
                if (! lix.healthy || lix.ploderTimer > 0)
                    continue;
                auto ow = makeGypsyWagon(tribe, lixID);
                lix.assignManually(&ow, Ac.exploder);
                break; // only one lix is hit by the nuke per update
            }
        }
    }

    void updateLixxies()
    {
        version (tharsisprofiling)
            Zone zone = Zone(profiler, "PhysSeq updateLixxies()");
        bool anyFlingers     = false;

        /* Refactoring idea:
         * Put this sorting into State, and do it only once at the beginning
         * of a game. Encapsulate (Tribe[Style] tribes) and offer methods that
         * provide the mutable tribe, but don't allow to rewrite the array.
         */
        auto sortedTribes = _cs.tribes.byValue.array.sort!"a.style < b.style";

        void foreachLix(void delegate(Tribe, in int, Lixxie) func)
        {
            foreach (tribe; sortedTribes)
                foreach (int lixID, lixxie; tribe.lixvec.enumerate!int)
                    func(tribe, lixID, lixxie);
        }

        void performFlingersUnmarkOthers()
        {
            foreachLix((Tribe tribe, in int lixID, Lixxie lixxie) {
                lixxie.setNoEncountersNoBlockerFlags();
                if (lixxie.ploderTimer != 0) {
                    auto ow = makeGypsyWagon(tribe, lixID);
                    handlePloderTimer(lixxie, &ow);
                }
                if (lixxie.updateOrder == PhyuOrder.flinger) {
                    lixxie.marked = true;
                    anyFlingers = true;
                    auto ow = makeGypsyWagon(tribe, lixID);
                    lixxie.perform(&ow);
                }
                else
                    lixxie.marked = false;
            });
        }

        void applyFlinging()
        {
            if (! anyFlingers)
                return;
            foreachLix((Tribe tribe, in int lixID, Lixxie lixxie) {
                auto ow = makeGypsyWagon(tribe, lixID);
                lixxie.applyFlingXY(&ow);
            });
        }

        void performUnmarked(PhyuOrder uo)
        {
            foreachLix((Tribe tribe, in int lixID, Lixxie lixxie) {
                if (! lixxie.marked && lixxie.updateOrder == uo) {
                    lixxie.marked = true;
                    auto ow = makeGypsyWagon(tribe, lixID);
                    lixxie.perform(&ow);
                }
            });
        }

        performFlingersUnmarkOthers();
        applyFlinging();
        _physicsDrawer.applyChangesToPhymap();

        performUnmarked(PhyuOrder.blocker);
        performUnmarked(PhyuOrder.remover);
        _physicsDrawer.applyChangesToPhymap();

        performUnmarked(PhyuOrder.adder);
        _physicsDrawer.applyChangesToPhymap();

        performUnmarked(PhyuOrder.peaceful);
    }

    void finalizePhyuAnimateGadgets()
    {
        // Animate after we had the traps eat lixes. Eating a lix sets a flag
        // in the trap to run through the animation, showing the first killing
        // frame after this next animate() call. Physics depend on this anim!
        foreach (hatch; _cs.hatches)
            hatch.animate(_effect, _cs.update);
        _cs.foreachGadget((Gadget g) {
            g.animateForPhyu(_cs.update);
        });
    }
}
