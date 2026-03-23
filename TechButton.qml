import QtQuick 2.15

Item {
    id: root
    width: 110; height: 35
    property string text: "BUTTON"
    property bool active: false
    signal clicked()

    Rectangle {
        id: btnBg
        anchors.fill: parent
        color: active ? Qt.rgba(0, 1, 1, 0.3) : "transparent"
        border.color: active ? "white" : "#00FFFF"
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: root.text
            color: active ? "white" : "#00FFFF"
            font.family: customFont.name; font.pixelSize: 13; font.bold: true
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: parent.border.width = 2
            onExited: parent.border.width = 1
            onClicked: root.clicked()
        }
    }
}