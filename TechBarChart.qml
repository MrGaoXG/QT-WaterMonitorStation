import QtQuick 2.15
import QtQuick.Layouts 1.15

RowLayout {
    id: chartRoot
    anchors.fill: parent; spacing: 8
    property variant dataModel: [0, 0, 0, 0, 0, 0, 0]

    Repeater {
        model: chartRoot.dataModel
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; Layout.maximumWidth: 15
            Layout.alignment: Qt.AlignBottom
            color: Qt.rgba(1, 1, 1, 0.05)

            Rectangle {
                width: parent.width
                height: parent.height * (modelData / 100)
                anchors.bottom: parent.bottom
                color: "#00FFFF"
                Behavior on height { NumberAnimation { duration: 800; easing.type: Easing.OutElastic } }
            }
        }
    }
}