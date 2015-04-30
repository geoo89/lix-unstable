module basics.demo;

import basics.alleg5;
import basics.globals;
import file.filename;
import game.lookup;
import graphic.cutbit;
import graphic.gralib;
import graphic.graphic;
import graphic.textout;
import graphic.torbit;
import gui;
import hardware.mouse;
import hardware.mousecur;
import hardware.keyboard;
import hardware.display;
import hardware.sound;
import level.tilelib;

/* right now, this class tests various other classes. There will be a lot
 * of random things created here.
 * the loop runs by itself until ESC is pressed, because it's an old class.
 *
 *  void main_loop()
 *
 *      create an object and call this method once, then kill the demo.
 */

class Demo {

private:

    bool   exit;
    AlBit[] wuerste;
    Torbit osd;
    Graphic myhatch1;
    Graphic myhatch2;
    Element[] elems;

    Torbit land;
    Lookup lookup;



public:

this()
{
    exit = false;

    import graphic.color;

    wuerste ~= al_load_bitmap("./images/proxima/tile/blue1a.png");
    assert (wuerste[0]);
    al_convert_mask_to_alpha(wuerste[0], AlCol(1,0,1,1));
    foreach (i; 1 .. 4) {
        AlBit wurst = albit_create(50 + 31 * (i % 2), 50 + 21 * (i/2));
        mixin(temp_target!"wurst");
        al_clear_to_color(AlCol(1,0,0,1));
        wuerste ~= wurst;
    }

    osd = new Torbit(al_get_display_width (display),
                     al_get_display_height(display), true, true);

    const(Cutbit) hatch_cb = get_tile("geoo/construction/Hatch.H").cb;
    myhatch1 = new Graphic(hatch_cb, osd);
    myhatch2 = new Graphic(hatch_cb, osd);

    // test gui elements
    elems ~= new Frame (Geom.From.BOTTOM_RIGHT, 40, 50, 60, 70);
    elems ~= new Button(Geom.From.BOTTOM_RIGHT, 40, 50, 60, 50);
    elems ~= () {
        auto a = new TextButton(Geom.From.BOTTOM, 0, 20);
        import file.language;
        a.set_text(transl(Lang.editor_button_SELECT_COPY));
        return a;
    } ();
    foreach (e; elems) gui.add_elder(e);

    // test level input/output
    import level.level;
    Level lv = new Level(new Filename("./levels/atest.txt"));
    lv.save_to_file(new Filename("./levels/aout.txt"));

    import game.lookup;

    land   = new Torbit(lv.size_x, lv.size_y, lv.torus_x, lv.torus_y);
    lookup = new Lookup(lv.size_x, lv.size_y, lv.torus_x, lv.torus_y);

    // not testing the level drawing right now
    static if (false) {
        lv.draw_terrain_to(land, lookup);
        land.save_to_file(new Filename("z-landtest.png"));
        lookup.save_to_file(new Filename("y-lookuptest.png"));
    }

    // This test class does lots of drawing during calc().
    // Since that is skipped when it's first created, make one osd-clear here.
    mixin(temp_target!"osd.get_albit()");
    al_clear_to_color(AlCol(0, 0, 0, 1));
}



~this()
{
    if (lookup) destroy(lookup);
    if (land)   destroy(land);

    destroy(myhatch2);
    destroy(myhatch1);

    destroy(osd);

    foreach (ref wurst; wuerste) {
        if (wurst) al_destroy_bitmap(wurst);
        wurst = null;
    }
    assert (wuerste[0] == null);
}



private double
wurstrotation(int tick)
{
    int phase = tick / 150;
    int mod = tick % 150;

    if (mod >= 100) {
        mod = 0;
        phase += 1;
    }
    return phase + mod / 100.0;
}


void
calc()
{
    int tick = al_get_timer_count(basics.alleg5.timer) % (2 << 30);

    mixin(temp_target!"osd.get_albit()");
    al_clear_to_color(AlCol(0, 0, 0, 1));
    al_draw_triangle(20+tick, 20, 30, 80, 40, 20, AlCol(0.3, 0.5, 0.7, 1), 3);

    osd.draw_rectangle(100 + tick*2, 100 + tick*3, 130, 110, AlCol(0.2, 1, 0.3, 1));
    osd.draw_from(wuerste[0], 100 + 0, 100, false, wurstrotation(tick));
    osd.draw_from(wuerste[1], 200 + 0, 100, true, wurstrotation(tick/2));
    osd.draw_from(wuerste[2], 100 + 0, 200, true, wurstrotation(tick/3));
    osd.draw_from(wuerste[3], 200 + 0, 200, false, wurstrotation(tick/5));

    import std.math, std.conv;
    myhatch1.set_xy(300 + to!int(40*sin(tick/41.0)),
                    300 + to!int(30*sin(tick/25.0)));
    myhatch2.set_xy(450 + to!int(50*sin(tick/47.0)),
                    280 + to!int(42*sin(tick/27.0)));
    myhatch1.set_x_frame(to!int(2.5 + 2.49 * sin(tick/20.0)));
    myhatch2.set_x_frame(to!int(2.5 + 6.3  * sin(tick/25.0)));
    myhatch1.draw();
    myhatch2.draw();

    static string typetext = "Type some UTF-8 chars: ";
    typetext ~= get_utf8_input();
    if (get_backspace()) {
        typetext = basics.help.backspace(typetext);
    }
    if (key_once(ALLEGRO_KEY_A)) {
        play_loud(Sound.CLOCK);
    }

    import basics.user;
    import std.string;
    import lix.enums;

    drtx(typetext ~ (tick % 30 < 15 ? "_" : ""), 300, 100);
    drtx(format("Your builder hotkey scancode: %d", key_skill[Ac.BUILDER]), 20, 400);
    drtx("Builder key once: " ~ (key_once(key_skill[Ac.BUILDER])?"now":"--"), 20, 420);
    drtx("Builder key hold: " ~ (key_hold(key_skill[Ac.BUILDER])?"now":"--"), 20, 440);
    drtx("Builder key rlsd: " ~ (key_rlsd(key_skill[Ac.BUILDER])?"now":"--"), 20, 460);
    drtx("Press [A] to playback a sound. Does it play immediately (correct) or with 0.5 s delay (bug)?", 20, 480);
    drtx("Non-square rectangles jump when they", 300, 120);
    drtx("finish a half rotation, this is intended.", 300, 140);

    if (tick % 120 >= 30 || tick % 10 < 5)
        drtx("--> PRESS [SHIFT] + [ESC] TO EXIT! <--", 5, 5);

    import basics.globals;
    import basics.globconf;
    import basics.versioning;
    import file.language;
    drtx(transl(Lang.net_chat_welcome_unstable)
        ~ " or enjoy hacking in D. " ~ get_version_string(), 20, 360);

    static bool showstring = false;
    import std.array;
    if (basics.globconf.user_name.empty) {
        drtx("Enter your username in data/config.txt for a greeting", 20, 380);
    }
    else {
        drtx("Hello " ~ user_name ~ ", loading the config file works.", 20, 380);
    }

    // random text in the text button
    if (tick % 50 == 0) {
        import std.random;
        auto but = cast (TextButton) elems[2];
        but.set_text(uniform(0, Lang.MAX).to!Lang.transl);

        switch (tick / 50 % 4) {
        case 0: but.set_align_left(true);  break;
        case 1: but.set_check_frame(1);    break;
        case 2: but.set_align_left(false); break;
        case 3: but.set_check_frame(0);    break;
        default: break;
        }
    }
    if (tick % 240 == 0) {
        play_loud(Sound.HATCH_OPEN);
    }

    import level.tilelib;
    import level.tile;
    const(Tile) mytile = get_tile("geoo/sandstone/arc_big");
    assert (mytile, "mytile not exist");
    assert (mytile.cb, "mytile.cb not exist");
    mytile.cb.draw(osd, 500 + to!int(50 * sin(tick / 30.0)), 10);
}



void
draw()
{
    osd.copy_to_screen();
}

}
// end class