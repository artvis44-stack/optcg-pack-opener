#!/usr/bin/env python3
"""OPTCG pack opener for macOS: a PySide6 host for the shared app in ../app.

usage: optcg.py [box]          toggle the overlay (box = start in booster box mode)
       optcg.py --showcase      the desktop showcase (a card you picked with D)
       optcg.py --inspect       the overlay showing the showcased card big (double-click it)
       optcg.py --ipc CMD [ARG] send a command to the running overlay, e.g.
                                --ipc advance, --ipc chooseSet OP-05, --ipc snapshot /tmp/x.png

The app itself (UI, shaders, pack logic, downloader) is shared with the Linux
version; this file only provides what the app asks its host for -- env(),
readText(), writeText(), run(), appPath(), startShowcase(), openInspect(), openOverlay(),
isIdle(), notify() -- plus the windows,
single-instance toggle and
the --ipc commands (the Linux version's `qs ipc`). It runs on Linux too,
which is how it's tested.
"""
import os
import sys
from pathlib import Path

from PySide6.QtCore import QMetaObject, QObject, QProcess, Q_ARG, Slot
from PySide6.QtGui import QCursor, QGuiApplication
from PySide6.QtNetwork import QLocalServer, QLocalSocket
from PySide6.QtQml import QJSValue, QQmlApplicationEngine

HERE = Path(__file__).resolve().parent
SOCKET = "optcg-pack-opener"
SHOWCASE_SOCKET = "optcg-showcase"
# commands --ipc can send -> functions on the window in main.qml
COMMANDS = {name: name for name in ("advance", "revealAll", "newPack", "inspect", "binder", "switchMode",
                                    "openAll", "openPack", "sets", "chooseSet", "snapshot", "showcase",
                                    "board", "sellBulk", "binderAll", "testDiamond")}
COMMANDS["close"] = "closeOverlay"


class Host(QObject):
    """The host interface the shared app needs (see ../QuickshellHost.qml)."""

    def __init__(self):
        super().__init__()
        self._procs = []

    @Slot(str, result=str)
    def env(self, name):
        return os.environ.get(name, "")

    @Slot(str, result=str)
    def appPath(self, relative):
        return str(HERE.parent / relative)

    @Slot("QVariantList")
    def openOverlay(self, args):
        QProcess.startDetached(sys.executable, [str(HERE / "optcg.py"), *[str(a) for a in args]])

    @Slot(result=bool)
    def isIdle(self):
        """Away from the computer 5+ minutes (macOS: seconds since the last input event)."""
        if sys.platform != "darwin":
            return False
        try:
            from Quartz import CGEventSourceSecondsSinceLastEventType
            return CGEventSourceSecondsSinceLastEventType(1, 0xFFFFFFFF) >= 300   # HID state, any input
        except Exception:
            return False

    @Slot(str, str)
    def notify(self, title, text):
        if sys.platform == "darwin":
            esc = lambda s: s.replace("\\", "\\\\").replace('"', '\\"')
            QProcess.startDetached("osascript", ["-e", f'display notification "{esc(text)}" with title "{esc(title)}"'])
        else:
            QProcess.startDetached("notify-send", ["-a", "OPTCG", title, text])

    @Slot()
    def openInspect(self):
        QProcess.startDetached(sys.executable, [str(HERE / "optcg.py"), "--inspect"])

    @Slot()
    def startShowcase(self):
        # detached, so it outlives the pack opener; it quits if one is already running
        QProcess.startDetached(sys.executable, [str(HERE / "optcg.py"), "--showcase"])

    @Slot(str, result=str)
    def readText(self, path):
        try:
            return Path(path).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            return ""

    @Slot(str, str)
    def writeText(self, path, text):
        p = Path(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        tmp = p.with_name(p.name + ".tmp")
        tmp.write_text(text, encoding="utf-8")
        os.replace(tmp, p)   # atomic, like the Quickshell host

    @Slot("QVariantList", QJSValue, QJSValue)
    def run(self, command, on_line, on_done):
        proc = QProcess(self)
        self._procs.append(proc)
        buffered = bytearray()

        def read():
            buffered.extend(bytes(proc.readAllStandardOutput()))
            while b"\n" in buffered:
                line, _, rest = bytes(buffered).partition(b"\n")
                buffered[:] = rest
                if on_line.isCallable():
                    on_line.call([line.decode("utf-8", "replace")])

        def done(code, _status):
            read()
            if on_done.isCallable():
                on_done.call([code])
            self._procs.remove(proc)
            proc.deleteLater()

        proc.readyReadStandardOutput.connect(read)
        proc.finished.connect(done)
        proc.start(str(command[0]), [str(a) for a in command[1:]])


def send(message, socket=SOCKET):
    """Send a message to a running instance; False if none is running."""
    sock = QLocalSocket()
    sock.connectToServer(socket)
    if not sock.waitForConnected(300):
        return False
    sock.write(message.encode())
    sock.waitForBytesWritten(1000)
    sock.disconnectFromServer()
    return True


def mac_window_tweaks(window):
    """Float above the menu bar and full-screen apps, without a Dock icon.
    Needs PyObjC (pyobjc-framework-Cocoa); skipped quietly without it."""
    if sys.platform != "darwin":
        return
    try:
        import objc
        from AppKit import NSApplication
    except ImportError:
        return
    app = NSApplication.sharedApplication()
    app.setActivationPolicy_(1)              # NSApplicationActivationPolicyAccessory: no Dock icon
    app.activateIgnoringOtherApps_(True)     # take keyboard focus from the app you were in
    nswindow = objc.objc_object(c_void_p=int(window.winId())).window()
    nswindow.setLevel_(25)                   # NSStatusWindowLevel: above the menu bar
    nswindow.setCollectionBehavior_((1 << 0) | (1 << 8))   # all Spaces + over full-screen apps


def mac_desktop_tweaks(window):
    """Showcase window: on the desktop (just above the icons), on every Space,
    left out of window cycling and Mission Control. Needs PyObjC."""
    if sys.platform != "darwin":
        return
    try:
        import objc
        from AppKit import NSApplication
    except ImportError:
        return
    NSApplication.sharedApplication().setActivationPolicy_(1)   # no Dock icon
    nswindow = objc.objc_object(c_void_p=int(window.winId())).window()
    nswindow.setLevel_(-2147483603 + 1)   # kCGDesktopIconWindowLevel + 1
    # canJoinAllSpaces | stationary | ignoresCycle
    nswindow.setCollectionBehavior_((1 << 0) | (1 << 4) | (1 << 6))


def run_showcase(app):
    if send("ping", SHOWCASE_SOCKET):   # already running: it picks up the new card itself
        return 0
    QLocalServer.removeServer(SHOWCASE_SOCKET)
    server = QLocalServer()
    server.setSocketOptions(QLocalServer.SocketOption.UserAccessOption)   # only this user can send commands
    server.listen(SHOWCASE_SOCKET)
    host = Host()
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("macHost", host)
    engine.load(str(HERE / "showcase.qml"))
    if not engine.rootObjects():
        return "couldn't load showcase.qml"
    mac_desktop_tweaks(engine.rootObjects()[0])
    code = app.exec()
    server.close()
    return code


def main():
    args = sys.argv[1:]
    QGuiApplication.setApplicationName("optcg")
    app = QGuiApplication(sys.argv[:1])

    if args[:1] == ["--ipc"]:
        if len(args) < 2 or args[1] not in COMMANDS:
            sys.exit(f"usage: optcg.py --ipc {{{','.join(sorted(COMMANDS))}}} [ARG]")
        sys.exit(0 if send(" ".join(args[1:])) else "the overlay isn't running")
    # macOS-native locations for the card cache and the collection
    if sys.platform == "darwin":
        os.environ.setdefault("XDG_CACHE_HOME", str(Path.home() / "Library" / "Caches"))
        os.environ.setdefault("XDG_DATA_HOME", str(Path.home() / "Library" / "Application Support"))
    os.environ.setdefault("OPTCG_PYTHON", sys.executable)   # runs fetch_cards.py
    if args[:1] == ["--showcase"]:
        sys.exit(run_showcase(app))

    if "--inspect" in args:
        os.environ["OPTCG_INSPECT"] = "1"
        if send("ping"):   # the overlay is already up
            return
    elif send("close"):   # already open -> this was a toggle
        return
    if "box" in args:
        os.environ["OPTCG_MODE"] = "box"

    host = Host()
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("macHost", host)
    engine.load(str(HERE / "main.qml"))
    if not engine.rootObjects():
        sys.exit("couldn't load main.qml")
    window = engine.rootObjects()[0]

    screen = QGuiApplication.screenAt(QCursor.pos()) or QGuiApplication.primaryScreen()
    window.setGeometry(screen.geometry())
    window.show()
    mac_window_tweaks(window)
    window.requestActivate()

    QLocalServer.removeServer(SOCKET)   # a stale socket from a crash
    server = QLocalServer()
    server.setSocketOptions(QLocalServer.SocketOption.UserAccessOption)   # only this user can send commands
    server.listen(SOCKET)

    def on_connection():
        sock = server.nextPendingConnection()

        def handle():
            name, _, arg = bytes(sock.readAll()).decode().partition(" ")
            if name in COMMANDS:
                if arg:
                    QMetaObject.invokeMethod(window, COMMANDS[name], Q_ARG("QVariant", arg))
                else:
                    QMetaObject.invokeMethod(window, COMMANDS[name])

        sock.readyRead.connect(handle)
        sock.disconnected.connect(sock.deleteLater)

    server.newConnection.connect(on_connection)
    code = app.exec()
    server.close()
    sys.exit(code)


if __name__ == "__main__":
    main()
