import QtQuick
import QtMultimedia

// The sound effects (app/sounds/*.wav, made by tools/make_sounds.py). The pack
// opener loads this with a Loader, so without Qt Multimedia it just stays quiet.
Item {
    id: sounds

    property string dir          // file:// URL of app/sounds
    property real volume: 0.7
    readonly property var names: ["tear", "flip", "charge", "rare", "epic", "legendary", "god", "coin", "poster", "chime", "box"]
    property var effects: ({})

    Component {
        id: effect
        SoundEffect {}
    }

    onDirChanged: {   // set by the pack opener once this is loaded
        Object.keys(effects).forEach(n => effects[n].destroy());
        var e = {};
        names.forEach(n => e[n] = effect.createObject(sounds, { source: dir + "/" + n + ".wav", volume: volume }));
        effects = e;
    }

    function play(name) {
        var e = effects[name];
        if (!e) return;
        e.stop();
        e.play();
    }

    function stop(name) {
        if (effects[name]) effects[name].stop();
    }
}
