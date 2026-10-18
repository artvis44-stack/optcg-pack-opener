import QtQuick
import "sync.js" as Sync
import "progress.js" as Progress

// The sync account screen (Y): sign in to (or create an account on) your sync
// server, then your collection, berries and wanted posters stay the same on
// every computer signed in to it. Signed in: status, sync now, your devices,
// change password, sign out, delete the account.
Item {
    id: panel

    property Item stage
    readonly property QtObject host: stage ? stage.host : null
    readonly property string dataDir: stage ? stage.dataDir : ""

    property var acc: ({})
    readonly property bool signedIn: Sync.signedIn(acc)
    readonly property bool choosing: signedIn && !!acc.pending
    property string message: ""
    property bool messageIsError: false
    property bool working: false
    property var devices: []
    property bool confirmDelete: false

    function refresh() {
        if (!host) return;
        acc = Sync.account(host, dataDir);
        stage.syncRound();
    }

    function say(text, isError) {
        message = text;
        messageIsError = !!isError;
        working = false;
    }

    function loadDevices() {
        if (!signedIn || choosing) return;
        Sync.call(host, dataDir, "GET", "/v1/sessions", undefined, (err, json) => {
            if (!err) devices = json.devices || [];
        });
    }

    onVisibleChanged: {
        if (!visible) return;
        message = "";
        confirmDelete = false;
        refresh();
        if (!serverField.text) serverField.text = acc.server || "https://";
        if (!userField.text) userField.text = acc.username || "";
        if (!deviceField.text) deviceField.text = acc.device || host.env("HOSTNAME") || "my computer";
        loadDevices();
    }

    // this computer has played (more than a starter save)?
    function hasLocalSaves() {
        try {
            var col = JSON.parse(host.readText(dataDir + "/collection.json") || "{}");
            if (Object.keys(col.cards || {}).length) return true;
            var p = JSON.parse(host.readText(dataDir + "/progress.json") || "{}");
            return !!(p.stats && p.stats.packs);
        } catch (e) {
            return true;
        }
    }

    function signIn(create) {
        if (working) return;
        working = true;
        message = create ? "Creating your account..." : "Signing in...";
        messageIsError = false;
        var form = { server: serverField.text, username: userField.text.trim(), password: passwordField.text,
                     device: deviceField.text.trim(), invite: inviteField.text.trim() };
        Sync.signIn(host, dataDir, form, create, (err, info) => {
            passwordField.text = "";
            if (err) {
                say(err, true);
                return;
            }
            refresh();
            if (info.hasData && !hasLocalSaves()) {
                finish(true);   // a fresh computer: just take the account's
            } else {
                say(info.hasData ? "" : "Signed in. Your saves are uploading now.");
                loadDevices();
            }
        });
    }

    function finish(useAccount) {
        working = true;
        message = useAccount ? "Downloading your saves..." : "Combining...";
        Sync.finishLink(host, dataDir, stage.sets, useAccount, err => {
            if (err) {
                say(err, true);
                return;
            }
            refresh();
            stage.reloadCollection();
            stage.reloadProgress();
            say(useAccount ? "Done: this computer now has your account's saves." : "Done: both are combined.");
            loadDevices();
        });
    }

    function signOut() {
        Sync.signOut(host, dataDir, () => {
            devices = [];
            refresh();
            say("Signed out. Your saves stay on this computer.");
        });
    }

    function changePassword() {
        working = true;
        Sync.call(host, dataDir, "POST", "/v1/account/password", { old: oldPassword.text, new: newPassword.text }, err => {
            oldPassword.text = "";
            newPassword.text = "";
            say(err || "Password changed. Your other computers need to sign in again.", !!err);
            loadDevices();
        });
    }

    function deleteAccount() {
        if (!confirmDelete) {
            confirmDelete = true;
            say("Click again to delete the account and everything on the server. Your saves stay on this computer.", true);
            return;
        }
        working = true;
        Sync.call(host, dataDir, "POST", "/v1/account/delete", { password: deletePassword.text }, err => {
            deletePassword.text = "";
            confirmDelete = false;
            if (err) {
                say(err, true);
                return;
            }
            Sync.signOut(host, dataDir, () => {
                devices = [];
                refresh();
                say("Account deleted.");
            });
        });
    }

    Timer {   // keep the status line fresh
        interval: 1000
        running: panel.visible
        repeat: true
        onTriggered: panel.acc = Sync.account(panel.host, panel.dataDir)
    }

    Rectangle {
        anchors.fill: parent
        color: "#05070d"
        opacity: 0.95
    }
    MouseArea {
        anchors.fill: parent   // keep clicks away from what's underneath
    }

    component Field: Column {
        id: field
        property alias text: input.text
        property alias label: caption.text
        property bool secret: false
        property string placeholder: ""
        property Item next: null
        signal accepted()
        width: 420
        spacing: 4
        Text {
            id: caption
            color: "#9aa0ad"
            font.pixelSize: 12
        }
        Rectangle {
            width: parent.width
            height: 34
            radius: 6
            color: "#151b2c"
            border.color: input.activeFocus ? "#ffd56b" : "#2c3550"
            TextInput {
                id: input
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                verticalAlignment: TextInput.AlignVCenter
                color: "#e8e8ee"
                font.pixelSize: 15
                clip: true
                selectByMouse: true
                echoMode: field.secret ? TextInput.Password : TextInput.Normal
                KeyNavigation.tab: field.next ? field.next.input : null
                onAccepted: field.accepted()
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !input.text && !input.activeFocus
                    text: field.placeholder
                    color: "#4a5370"
                    font.pixelSize: 15
                }
            }
        }
        property alias input: input
    }

    Flickable {
        anchors.fill: parent
        contentHeight: content.height + 80
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            anchors.horizontalCenter: parent.horizontalCenter
            y: 50
            width: 420
            spacing: 14

            Text {
                text: "Sync"
                color: "#ffd56b"
                font { pixelSize: 30; weight: Font.Black; italic: true }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: panel.signedIn
                      ? "Signed in as " + panel.acc.username + " on " + panel.acc.server.replace(/^https?:\/\//, "")
                        + "  ·  this computer: " + panel.acc.device
                      : "Sign in to your sync server and your collection, berries, streak and wanted posters stay "
                        + "the same on every computer you sign in on. New here? Create an account."
                color: "#d0d4dc"
                font.pixelSize: 14
            }

            // ---- signed out: sign in / create an account ----
            Column {
                visible: !panel.signedIn
                spacing: 10
                Field { id: serverField; label: "Sync server"; placeholder: "https://sync.example.com"; next: userField }
                Field { id: userField; label: "Username"; next: passwordField }
                Field { id: passwordField; label: "Password (10+ characters for a new account)"; secret: true; next: deviceField
                        onAccepted: panel.signIn(false) }
                Field { id: deviceField; label: "This computer's name"; next: inviteField }
                Field { id: inviteField; label: "Invite code (only for a new account, if your server asks for one)"; next: serverField }
                Row {
                    spacing: 10
                    PillButton { text: "Sign in"; enabledLook: !panel.working; onClicked: panel.signIn(false) }
                    PillButton { text: "Create account"; accent: "#7fd1b9"; enabledLook: !panel.working; onClicked: panel.signIn(true) }
                }
            }

            // ---- just signed in to an account that has saves ----
            Column {
                visible: panel.choosing
                spacing: 10
                width: parent.width
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "This account already has saves. Use them on this computer, or combine them with this computer's?"
                    color: "#fff6e0"
                    font { pixelSize: 16; weight: Font.Bold }
                }
                PillButton { text: "Use the account's saves"; enabledLook: !panel.working; onClicked: panel.finish(true) }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "This computer's saves are replaced (a copy is kept in the sync folder)."
                    color: "#7a8090"
                    font.pixelSize: 12
                }
                PillButton { text: "Combine both"; accent: "#7fd1b9"; enabledLook: !panel.working; onClicked: panel.finish(false) }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Adds this computer's cards, berries, packs and posters to the account's."
                    color: "#7a8090"
                    font.pixelSize: 12
                }
                PillButton { text: "Cancel and sign out"; accent: "#7a8090"; onClicked: panel.signOut() }
            }

            // ---- signed in ----
            Column {
                visible: panel.signedIn && !panel.choosing
                spacing: 12
                width: parent.width
                Text {
                    text: panel.stage ? panel.stage.syncStatus : ""
                    color: panel.stage && panel.stage.syncStatus.indexOf("synced") === 0 ? "#7fd1b9" : "#ff9a7a"
                    font { pixelSize: 15; weight: Font.Bold }
                }
                Row {
                    spacing: 10
                    PillButton {
                        text: "Sync now"
                        onClicked: Sync.syncOnce(panel.host, panel.dataDir, panel.stage.sets, "opener", changed => {
                            panel.stage.reloadCollection();
                            panel.stage.reloadProgress();
                            panel.stage.syncRound();
                        })
                    }
                    PillButton { text: "Sign out"; accent: "#7a8090"; onClicked: panel.signOut() }
                }

                Text {
                    topPadding: 10
                    text: "Your computers"
                    color: "#ffd56b"
                    font { pixelSize: 17; weight: Font.Black }
                }
                Repeater {
                    model: panel.devices
                    Row {
                        required property var modelData
                        spacing: 10
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 300
                            elide: Text.ElideRight
                            text: modelData.device + (modelData.current ? "  (this one)" : "")
                                  + "  ·  last synced " + new Date(modelData.last_used * 1000).toLocaleString(Qt.locale(), "d MMM HH:mm")
                            color: "#d0d4dc"
                            font.pixelSize: 13
                        }
                        PillButton {
                            visible: !modelData.current
                            text: "remove"
                            fontSize: 11
                            accent: "#ff8a7a"
                            onClicked: Sync.call(panel.host, panel.dataDir, "DELETE", "/v1/sessions/" + modelData.id, undefined,
                                                 err => { panel.say(err || "Removed: that computer is signed out.", !!err); panel.loadDevices(); })
                        }
                    }
                }

                Text {
                    topPadding: 10
                    text: "Change password"
                    color: "#ffd56b"
                    font { pixelSize: 17; weight: Font.Black }
                }
                Field { id: oldPassword; label: "Current password"; secret: true; next: newPassword }
                Field { id: newPassword; label: "New password (10+ characters)"; secret: true; next: oldPassword
                        onAccepted: panel.changePassword() }
                PillButton { text: "Change password"; enabledLook: !panel.working; onClicked: panel.changePassword() }

                Text {
                    topPadding: 10
                    text: "Delete account"
                    color: "#ff8a7a"
                    font { pixelSize: 17; weight: Font.Black }
                }
                Field { id: deletePassword; label: "Password"; secret: true }
                PillButton {
                    text: panel.confirmDelete ? "Yes, delete it" : "Delete account"
                    accent: "#ff8a7a"
                    enabledLook: !panel.working
                    onClicked: panel.deleteAccount()
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: panel.message !== ""
                text: panel.message
                color: panel.messageIsError ? "#ff8a7a" : "#7fd1b9"
                font { pixelSize: 14; weight: Font.Bold }
            }
        }
    }

    Text {
        anchors { bottom: parent.bottom; bottomMargin: 14; horizontalCenter: parent.horizontalCenter }
        text: "Y or Esc: back"
        color: "#9aa0ad"
        font.pixelSize: 14
    }
}
