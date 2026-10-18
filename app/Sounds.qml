import QtQuick
import QtMultimedia

// The sound effects (app/sounds/*.wav, made by tools/make_sounds.py). The pack
// opener loads this with a Loader, so without Qt Multimedia it just stays quiet.
Item {
    id: sounds

    property string dir          // file:// URL of app/sounds
    property real volume: 0.6   // overall
    // each sound's own level: the ones that play all the time are quiet
    readonly property var levels: ({ flip: 0.25, tear: 0.5, coin: 0.5, chime: 0.6, box: 0.6, charge: 0.6,
                                     rare: 0.8, epic: 0.85, poster: 0.9, legendary: 1, god: 1 })
    readonly property var names: ["tear", "flip", "charge", "rare", "epic", "legendary", "god", "coin", "poster", "chime", "box"]
    property var effects: ({})

    Component {
        id: effect
        SoundEffect {}
    }

    onDirChanged: {   // set by the pack opener once this is loaded
        Object.keys(effects).forEach(n => effects[n].destroy());
        var e = {};
        names.forEach(n => e[n] = effect.createObject(sounds, { source: dir + "/" + n + ".wav", volume: volume * (levels[n] || 1) }));
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
