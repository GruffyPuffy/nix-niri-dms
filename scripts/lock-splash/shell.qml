import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: shell

    readonly property string splashTitle: Quickshell.env("QS_LOCK_SPLASH_TITLE") || "Locking session"
    readonly property string splashMessage: Quickshell.env("QS_LOCK_SPLASH_MESSAGE") || "Please wait for GDM to start"
    readonly property int splashTimeout: Number(Quickshell.env("QS_LOCK_SPLASH_TIMEOUT_MS") || "5000")

    Timer {
        interval: shell.splashTimeout
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: splash

            required property var modelData

            screen: modelData
            visible: true
            color: "transparent"

            WlrLayershell.namespace: "niri:gdm-lock-splash"
            WlrLayershell.layer: WlrLayershell.Overlay
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            anchors {
                left: true
                right: true
                top: true
                bottom: true
            }

            Rectangle {
                anchors.fill: parent
                color: "#080a0f"
                opacity: 0.78
            }

            Rectangle {
                id: card

                width: Math.min(parent.width - 64, 620)
                height: 230
                radius: 28
                anchors.centerIn: parent
                color: "#171b24"
                border.color: "#6ea5ff"
                border.width: 1

                Column {
                    width: parent.width - 48
                    anchors.centerIn: parent
                    spacing: 16

                    Rectangle {
                        id: lockIcon

                        width: 72
                        height: 72
                        radius: 36
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: "transparent"
                        border.color: "#9ece6a"
                        border.width: 4

                        Rectangle {
                            width: 30
                            height: 18
                            radius: 9
                            color: "#9ece6a"
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Text {
                        text: shell.splashTitle
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        color: "#f4f7ff"
                        font.pixelSize: 34
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: shell.splashMessage
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        color: "#aeb7c8"
                        font.pixelSize: 18
                    }
                }
            }
        }
    }
}
