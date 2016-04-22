module gui.picker.picker;

import std.algorithm;
import std.conv;

import gui;
import gui.picker;

struct PickerConfig(T)
    if (is (T : Tiler)
) {
    Geom all;
    Geom bread;
    Geom files; // Tiler including scrollbar
    Ls ls;
}

class Picker : Element {
private:
    Breadcrumb _bread;
    Ls _ls;
    Frame _frame;
    Tiler _tiler;
    Scrollbar _scrollbar;

public:
    // Create all class objects in cfg, then give them to this constructor.
    this(T)(PickerConfig!T cfg)
    out {
        assert (_ls);
    }
    body {
        super(cfg.all);
        import graphic.color;
        undrawColor = color.transp; // Hack. Picker should not be a drawable
                                    // element, but rather only have children.
        _frame     = new Frame(cfg.files);
        _bread     = new Breadcrumb(cfg.bread);
        _ls        = cfg.ls;
        _tiler     = new T        (cfg.files.newGeomTiler);
        _scrollbar = new Scrollbar(cfg.files.newGeomScrollbar);
        _scrollbar.pageLen = _tiler.pageLen;
        addChildren(_bread, _frame, _tiler, _scrollbar);
    }

    @property Filename basedir() const { return _bread.basedir; }
    @property Filename basedir(Filename fn)
    {
        _bread.basedir = fn; // this resets currentDir if no longer child
        updateAccordingToBreadCurrentDir();
        return basedir;
    }

    @property Filename currentDir() const { return _bread.currentDir; }
    @property Filename currentDir(Filename fn)
    {
        if (fn && fn.dirRootless != currentDir.dirRootless) {
            _bread.currentDir = fn;
            updateAccordingToBreadCurrentDir();
        }
        return currentDir;
    }

    @property bool executeDir() const
    {
        return _tiler.executeDir || _bread.execute;
    }

    @property bool executeFile()   const { return _tiler.executeFile;   }
    @property int  executeFileID() const { return _tiler.executeFileID; }

    void highlightNothing() { _tiler.highlightNothing(); }
    void highlightFile(int i, CenterOnHighlightedFile chf)
    {
        _tiler.highlightFile(i, chf);
        _scrollbar.pos = _tiler.top;
    }

    Filename executeFileFilename() const
    {
        assert (executeFile, "call this only when executeFile == true");
        return _ls.files[executeFileID];
    }

    bool highlightFile(Filename fn, CenterOnHighlightedFile chf)
    {
        if (! fn)
            highlightNothing();
        currentDir = fn;
        immutable int id = _ls.files.countUntil(fn).to!int;
        if (id >= 0) {
            highlightFile(id, chf);
            return true;
        }
        else {
            highlightNothing();
            return false;
        }
    }

protected:
    override void calcSelf()
    {
        if (_bread.execute)
            updateAccordingToBreadCurrentDir();
        else if (_tiler.executeDir)
            currentDir = _ls.dirs[_tiler.executeDirID];
        else if (_scrollbar.execute)
            _tiler.top = _scrollbar.pos;
    }

private:
    void updateAccordingToBreadCurrentDir()
    {
        _ls.currentDir = currentDir;
        _tiler.loadDirsFiles(_ls.dirs, _ls.files);
        _scrollbar.totalLen = _tiler.totalLen;
        _scrollbar.pos = 0;
    }
}

private:

Geom newGeomScrollbar(Geom files) pure
{
    return new Geom(files.x + files.xl - 20, files.y, 20, files.yl);
}

Geom newGeomTiler(Geom files) pure
{
    return new Geom(files.x, files.y, files.xl - 20, files.yl);
}

