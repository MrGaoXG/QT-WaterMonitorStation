import QtQuick 2.15

Item {
    id: root
    property string title: "标题"
    property bool warning: false // 是否处于报警状态
    default property alias content: container.data

    Rectangle {
        id: bg
        anchors.fill: parent
        color: root.warning ? Qt.rgba(0.2, 0, 0, 0.7) : Qt.rgba(0, 0.05, 0.1, 0.6)
        border.color: root.warning ? "#FF3333" : Qt.rgba(0, 1, 1, 0.4)
        border.width: 1
        clip: true

        Behavior on color { ColorAnimation { duration: 500 } }
        Behavior on border.color { ColorAnimation { duration: 500 } }

        // 四个角的装饰线
        property color decoColor: root.warning ? "#FF3333" : "#00FFFF"
        Rectangle { width: 10; height: 2; color: bg.decoColor; x: 0; y: 0 }
        Rectangle { width: 2; height: 10; color: bg.decoColor; x: 0; y: 0 }
        Rectangle { width: 10; height: 2; color: bg.decoColor; anchors.right: parent.right; y: 0 }
        Rectangle { width: 2; height: 10; color: bg.decoColor; anchors.right: parent.right; y: 0 }
        Rectangle { width: 10; height: 2; color: bg.decoColor; x: 0; anchors.bottom: parent.bottom }
        Rectangle { width: 2; height: 10; color: bg.decoColor; x: 0; anchors.bottom: parent.bottom }
        Rectangle { width: 10; height: 2; color: bg.decoColor; anchors.right: parent.right; anchors.bottom: parent.bottom }
        Rectangle { width: 2; height: 10; color: bg.decoColor; anchors.right: parent.right; anchors.bottom: parent.bottom }

        Text {
            text: (root.warning ? "⚠ " : "● ") + root.title
            x: 15; y: 8
            color: bg.decoColor
            font.family: customFont.name
            font.pixelSize: 20; font.bold: true // 16 -> 20
        }

        Item {
            id: container
            anchors.fill: parent; anchors.topMargin: 35; anchors.margins: 15
        }
    }
}