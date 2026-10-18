import QtQuick
import Quickshell
import Quickshell.Io

// The host interface the shared app (app/) needs, implemented with Quickshell.
// A port to another platform provides an object with the same functions:
//   env(name)                       -> string ("" if unset)
//   readText(path)                  -> file contents, "" if missing
//   writeText(path, text)           -> writes the file (its directory already exists)
//   run(command, onLine, onDone)    -> runs a program (argv list) in the background,
//                                      onLine(text) per stdout line, onDone(exitCode)
//   startShowcase()                 -> starts the desktop showcase if it isn't running
//   appPath(relative)               -> filesystem path of a file in this folder (e.g. "app/sets.json")
//   openInspect()                   -> opens the overlay showing the showcased card big
QtObject {
    id: host

    function env(name) {
        return Quickshell.env(name) || "";
    }

    function appPath(relative) {
        return Quickshell.shellPath(relative);   // Qt.resolvedUrl gives qs:@/... URLs here
    }

    function openInspect() {
        Quickshell.execDetached(["env", "OPTCG_INSPECT=1", "qs", "-n", "-p", appPath("shell.qml")]);
    }

    function startShowcase() {
        // detached, so it outlives the pack opener; -n: no second copy
        Quickshell.execDetached(["qs", "-n", "-p", appPath("showcase.qml")]);
    }

    // a fresh FileView per call: one reused across paths can hand back the
    // previous file's text when the new path doesn't exist
    function readText(path) {
        var view = readerComponent.createObject(host, { path: path });
        var text = view.text();
        view.destroy();
        return text;
    }

    function writeText(path, text) {
        var view = writerComponent.createObject(host, { path: path });
        view.setText(text);
        view.destroy();
    }

    function run(command, onLine, onDone) {
        var proc = processComponent.createObject(host, { command: command, onLine: onLine, onDone: onDone });
        proc.running = true;
    }

    property Component readerComponent: Component {
        FileView {
            blockLoading: true
            printErrors: false   // a missing file just reads as ""
        }
    }

    property Component writerComponent: Component {
        FileView {
            preload: false
            blockWrites: true
            atomicWrites: true
            onSaveFailed: err => console.warn("couldn't write", path, ":", err)
        }
    }

    property Component processComponent: Component {
        Process {
            id: proc
            property var onLine
            property var onDone
            stdout: SplitParser {
                onRead: data => { if (proc.onLine) proc.onLine(data); }
            }
            onExited: (code, status) => {
                if (proc.onDone) proc.onDone(code);
                proc.destroy();
            }
        }
    }
}
