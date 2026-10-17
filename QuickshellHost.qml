import QtQuick
import Quickshell
import Quickshell.Io

// The host interface the shared app (app/) needs, implemented with Quickshell.
// A port to another platform provides an object with the same three functions:
//   env(name)              -> string ("" if unset)
//   readText(path)         -> file contents, "" if missing
//   writeText(path, text)  -> writes the file (its directory already exists)
QtObject {
    function env(name) {
        return Quickshell.env(name) || "";
    }

    function readText(path) {
        if (reader.path === path) reader.reload();
        else reader.path = path;
        return reader.text();
    }

    function writeText(path, text) {
        writer.path = path;
        writer.setText(text);
    }

    property FileView reader: FileView {
        preload: false
        blockLoading: true
        printErrors: false   // a missing file just reads as ""
    }

    property FileView writer: FileView {
        preload: false
        blockWrites: true
        atomicWrites: true
        onSaveFailed: err => console.warn("couldn't write", path, ":", err)
    }
}
