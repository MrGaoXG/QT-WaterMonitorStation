import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import QtCharts

Window {
    id: window
    width: 1920; height: 1080; visible: true; title: "水质监测地面站"
    color: "#020a0f"
    
    // 设置全屏模式与窗口模式的动态切换逻辑
    visibility: Window.FullScreen
    flags: visibility === Window.FullScreen ? Qt.FramelessWindowHint : Qt.Window

    // 快捷键支持：按 ESC 切换全屏/窗口模式
    Shortcut {
        sequence: "Esc"
        onActivated: {
            if (window.visibility === Window.FullScreen) {
                window.visibility = Window.Windowed
            } else {
                window.visibility = Window.FullScreen
            }
        }
    }
    
    // 增加全局缩放比例，让字体和元素随窗口大小自适应
    // 针对 7 寸屏进行极度优化，采用分别拉伸宽高的方式填满全屏，去除黑边
    property real scaleX: width / 1920
    property real scaleY: height / 1080
    property real scaleRatio: Math.min(scaleX, scaleY) // 仅供部分需要等比的地方使用
    
    // 基础字体大小系数，确保在小屏幕下字体不会缩得太小
    // 再次提升下限，针对 7 寸屏进行极度优化，设置为几乎不缩小
    property real fontScale: Math.max(scaleRatio, 0.95) 

    // --- 核心交互逻辑与数据 ---
    // 监听 C++ 后端的日志信号
    Connections {
        target: systemData
        function onLogMessage(msg) {
            addLog(msg)
        }
    }

    Component.onCompleted: {
        // 尝试打开默认串口（不再强制，改为用户手动在设置面板操作，或者保留尝试逻辑但不报错）
        systemData.openSerialPort("COM7", 9600)
    }

    function addLog(msg) {
        logModel.insert(0, { "time": Qt.formatDateTime(new Date(), "HH:mm:ss"), "info": msg })
        if (logModel.count > 10) logModel.remove(10)
    }

    // 模拟数据波动定时器已移除，改由 C++ 后端 SystemData 驱动

    FontLoader { id: customFont; source: "qrc:/DS-DIGIB-2.ttf" }

    // 全局缩放容器
    Item {
        id: rootContainer
        width: 1920
        height: 1080
        anchors.centerIn: parent
        // 使用独立缩放分别拉伸宽高，铺满屏幕并消除黑边
        transform: Scale { 
            origin.x: 1920 / 2
            origin.y: 1080 / 2
            xScale: window.scaleX
            yScale: window.scaleY
        }

        Image {
            id: backgroundImage; anchors.fill: parent; source: "qrc:/background.png"; fillMode: Image.PreserveAspectCrop
            Rectangle { anchors.fill: parent; color: "black"; opacity: 0.6 } // 加深背景底色，突出UI
        }
        
        // 全局报警边框 (隐藏在最底层，报警时闪烁)
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: "#FF0000"
            border.width: 10
            visible: systemData.hasAlarm
            opacity: 0
            
            SequentialAnimation on opacity {
                running: systemData.hasAlarm
                loops: Animation.Infinite
                NumberAnimation { from: 0.2; to: 0.8; duration: 600 }
                NumberAnimation { from: 0.8; to: 0.2; duration: 600 }
            }
        }

        // 顶部 Header
        Item {
            id: header; width: parent.width; height: 100; anchors.top: parent.top
            
            // 科技感背景图 (使用Canvas绘制)
            Canvas {
                anchors.fill: parent
                property color primaryColor: systemData.hasAlarm ? "#FF0000" : "#00FFFF"
                property color secondaryColor: systemData.hasAlarm ? Qt.rgba(1, 0, 0, 0.4) : Qt.rgba(0, 1, 1, 0.4)
                property color textColor: systemData.hasAlarm ? "#FF5555" : "#00A8FF"
                
                onPrimaryColorChanged: requestPaint()
                
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    
                    var cx = width / 2;
                    
                    // 1. 绘制主体折线
                    ctx.beginPath();
                    ctx.moveTo(20, 45);
                    ctx.lineTo(cx - 350, 45);
                    ctx.lineTo(cx - 280, 85);
                    ctx.lineTo(cx + 280, 85);
                    ctx.lineTo(cx + 350, 45);
                    ctx.lineTo(width - 20, 45);
                    ctx.strokeStyle = secondaryColor;
                    ctx.lineWidth = 2;
                    ctx.stroke();
                    
                    // 2. 绘制标题底部的亮色高亮线
                    ctx.beginPath();
                    ctx.moveTo(cx - 260, 85);
                    ctx.lineTo(cx + 260, 85);
                    ctx.strokeStyle = primaryColor;
                    ctx.lineWidth = 4;
                    ctx.stroke();
                    
                    // 3. 绘制两侧的装饰方块
                    ctx.fillStyle = primaryColor;
                    for(var i=0; i<5; i++) {
                        ctx.fillRect(cx - 380 - i*18, 41, 12, 8);
                        ctx.fillRect(cx + 368 + i*18, 41, 12, 8);
                    }
                    
                    // 4. 边缘装饰线条 (顶部细线)
                    ctx.beginPath();
                    ctx.moveTo(20, 15);
                    ctx.lineTo(150, 15);
                    ctx.moveTo(width - 150, 15);
                    ctx.lineTo(width - 20, 15);
                    ctx.strokeStyle = textColor;
                    ctx.lineWidth = 2;
                    ctx.stroke();
                }
            }

            // 主标题
            Text {
                text: systemData.hasAlarm ? "水质监测地面站 - 警报模式" : "水质监测地面站"
                anchors.centerIn: parent; anchors.verticalCenterOffset: -5
                font.pixelSize: 48; font.bold: true; color: "#FFFFFF"; font.family: customFont.name // 42 -> 48
                style: Text.Outline; styleColor: systemData.hasAlarm ? "#FF0000" : "#00A8FF" // 增加发光描边感
                font.letterSpacing: 2
            }
            
            // 英文副标题
            Text {
                text: "WATER QUALITY MONITORING SYSTEM"; anchors.top: parent.top; anchors.topMargin: 85
                anchors.horizontalCenter: parent.horizontalCenter
                font.pixelSize: 18; color: "#00A8FF"; font.family: customFont.name; font.letterSpacing: 5 // 16 -> 18
            }

            // 左侧状态装饰
            RowLayout {
                anchors.left: parent.left; anchors.leftMargin: 40; y: 15
                spacing: 20
                RowLayout {
                    spacing: 8
                    Rectangle { 
                        width: 14; height: 14; radius: 7; color: "#00FF00" // 12 -> 14
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 0.2; duration: 800 }
                            NumberAnimation { from: 0.2; to: 1.0; duration: 800 }
                        }
                    }
                    Text { text: "SYSTEM ONLINE"; color: "#00FF00"; font.family: customFont.name; font.pixelSize: 20 } // 18 -> 20
                }
                RowLayout {
                    spacing: 8
                    Rectangle { width: 14; height: 14; radius: 7; color: "#00A8FF" } // 12 -> 14
                    Text { text: "DATA LINK: SECURE"; color: "#00A8FF"; font.family: customFont.name; font.pixelSize: 20 } // 18 -> 20
                }
            }

            // 右侧时间显示与设置按钮
            RowLayout {
                anchors.right: parent.right; anchors.rightMargin: 40; y: 12
                spacing: 15
                
                // 系统设置按钮
                Rectangle {
                    width: 44; height: 44; radius: 22 // 40 -> 44
                    color: "transparent"; border.color: "#00A8FF"; border.width: 2
                    Text { text: "⚙️"; anchors.centerIn: parent; font.pixelSize: 22 } // 20 -> 22
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: parent.color = Qt.rgba(0, 168/255, 1, 0.2)
                        onExited: parent.color = "transparent"
                        onClicked: settingPopup.visible = true
                    }
                }
                
                Text {
                    text: "LOCAL TIME"; color: "#00A8FF"; font.family: customFont.name; font.pixelSize: 18 // 16 -> 18
                }
                Text {
                    color: "#00FFFF"; font.family: customFont.name; font.pixelSize: 28; font.bold: true // 26 -> 28
                    text: Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm:ss")
                    Timer { interval: 1000; running: true; repeat: true; onTriggered: parent.text = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm:ss") }
                }
            }
        }

        // 主内容
        Item {
            id: mainContent; anchors.fill: parent; anchors.margins: 30; anchors.topMargin: 110

        // --- 左侧面板 ---
        ColumnLayout {
            id: leftPanel
            x: -width - 50 // 初始位置在屏幕外
            anchors.top: parent.top; anchors.bottom: parent.bottom; width: parent.width * 0.22; spacing: 20
            
            // 进场动画
            NumberAnimation on x { 
                to: 0
                duration: 1200
                easing.type: Easing.OutExpo
                running: true 
                onFinished: {
                    leftPanel.anchors.left = mainContent.left
                }
            }
            HudPanel {
                title: "实时监控 (数字孪生)"
                Layout.fillWidth: true; Layout.preferredHeight: parent.height * 0.35
                
                // 将 3D 场景嵌入到左上角的红框区域内
                Tech3DScene {
                    anchors.fill: parent
                    anchors.margins: 5
                }
            }
            HudPanel {
                title: "核心指标监控"
                warning: systemData.phValue > 8.0 // 逻辑触发：PH值过高时面板报警
                Layout.fillWidth: true; Layout.fillHeight: true
                
                ColumnLayout {
                    anchors.fill: parent; spacing: 10
                    
                    // 上方：实时数据柱状图
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.preferredHeight: parent.height * 0.4
                        spacing: 20 // 15 -> 20
                        Repeater {
                            model: [ {name: "PH值", val: systemData.phValue/14, txt: systemData.phValue.toFixed(2)}, 
                                     {name: "溶解氧", val: systemData.dissolvedOxygen/10, txt: systemData.dissolvedOxygen.toFixed(2)}, 
                                     {name: "浊度", val: systemData.turbidity/10, txt: systemData.turbidity.toFixed(2)} ]
                            RowLayout {
                                Layout.fillWidth: true; Text { text: modelData.name; color: "white"; font.family: customFont.name; Layout.preferredWidth: 120; font.pixelSize: 24 } // 100 -> 120, 22 -> 24
                                Rectangle { Layout.fillWidth: true; height: 24; color: "#2000FFFF" // 20 -> 24
                                    Rectangle { width: parent.width * modelData.val; height: parent.height; color: systemData.phValue > 8 && index == 0 ? "red" : "#00FFFF"; Behavior on width { NumberAnimation{duration:1000} } }
                                }
                                Text { text: modelData.txt; color: "#00FFFF"; font.family: customFont.name; Layout.preferredWidth: 100; font.pixelSize: 24 } // 80 -> 100, 22 -> 24
                            }
                        }
                    }
                    
                    // 下方：历史趋势折线图
                    ChartView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        title: "过去24小时趋势"
                        titleColor: "#00A8FF"
                        titleFont.family: customFont.name
                        titleFont.pixelSize: 22 // 18 -> 22
                        legend.visible: true
                        legend.labelColor: "white"
                        legend.font.pixelSize: 16 // 14 -> 16
                        backgroundColor: "transparent"
                        plotAreaColor: Qt.rgba(0, 50/255, 50/255, 0.2)
                        antialiasing: true
                        margins { top: 0; bottom: 0; left: 0; right: 0 }

                        ValueAxis {
                            id: axisX
                            min: 0; max: 24
                            tickCount: 7
                            labelFormat: "%d"
                            labelsColor: "#00A8FF"
                            labelsFont.pixelSize: 16 // 14 -> 16
                            gridLineColor: Qt.rgba(0, 1.0, 1.0, 0.2)
                        }

                        ValueAxis {
                            id: axisY
                            min: 0; max: 40
                            tickCount: 5
                            labelsColor: "#00A8FF"
                            labelsFont.pixelSize: 16 // 14 -> 16
                            gridLineColor: Qt.rgba(0, 1.0, 1.0, 0.2)
                        }

                        LineSeries {
                            name: "温度(°C)"
                            axisX: axisX; axisY: axisY
                            color: "#FF5500"; width: 3
                            // 初始化模拟数据
                            Component.onCompleted: {
                                for (var i = 0; i <= 24; i++) {
                                    append(i, 20 + Math.random() * 10);
                                }
                            }
                        }
                        
                        LineSeries {
                            name: "PH值"
                            axisX: axisX; axisY: axisY
                            color: "#00FFFF"; width: 3
                            // 初始化模拟数据
                            Component.onCompleted: {
                                for (var i = 0; i <= 24; i++) {
                                    append(i, 6.5 + Math.random() * 2);
                                }
                            }
                        }
                    }
                }
            }
        }

        // --- 右侧面板 ---
        ColumnLayout {
            id: rightPanel
            x: mainContent.width // 初始位置在屏幕外 (使用父容器的宽度)
            anchors.top: parent.top; anchors.bottom: parent.bottom; width: parent.width * 0.22; spacing: 20
            
            // 注意：不能同时使用 anchors.right 和 x 动画，这会导致冲突
            // 我们在动画完成后，再动态绑定 anchors.right
            
            // 进场动画
            NumberAnimation on x { 
                to: mainContent.width - rightPanel.width
                duration: 1200
                easing.type: Easing.OutExpo
                running: true 
                onFinished: {
                    rightPanel.anchors.right = mainContent.right
                }
            }

            HudPanel {
                title: "系统实时日志"
                Layout.fillWidth: true; Layout.preferredHeight: parent.height * 0.35 // 0.45 -> 0.35 压缩高度
                ListView {
                    anchors.fill: parent; model: logModel; clip: true; spacing: 8 // 5 -> 8
                    delegate: Text {
                        width: parent.width
                        text: "[" + time + "] " + info; color: info.indexOf("报警") !== -1 ? "#FF3333" : "#00FFFF"
                        // 移除数字字体，使用标准字体提高清晰度，字号提升至 18px
                        font.pixelSize: 18; font.bold: true
                        wrapMode: Text.Wrap
                    }
                }
                ListModel { id: logModel }
            }
            
            // 新增：环境气象数据面板 (填补红色留白区域)
            HudPanel {
                title: "环境气象数据"
                Layout.fillWidth: true; Layout.fillHeight: true
                
                GridLayout {
                    anchors.centerIn: parent; width: parent.width * 0.95; anchors.verticalCenterOffset: 15 // 居中显示
                    columns: 2; columnSpacing: 25; rowSpacing: 25 
                    
                    Text { text: "温度 TEMP"; color: "#00A8FF"; font.pixelSize: 20; font.bold: true } // 18 -> 20
                    Text { text: systemData.temperature.toFixed(1) + " °C"; color: "#00FFFF"; font.family: customFont.name; font.pixelSize: 32; Layout.alignment: Qt.AlignRight } // 28 -> 32
                    
                    Text { text: "湿度 HUMID"; color: "#00A8FF"; font.pixelSize: 20; font.bold: true } // 18 -> 20
                    Text { text: systemData.humidity.toFixed(1) + " %"; color: "#00FFFF"; font.family: customFont.name; font.pixelSize: 32; Layout.alignment: Qt.AlignRight } // 28 -> 32
                    
                    Text { text: "风速 WIND"; color: "#00A8FF"; font.pixelSize: 20; font.bold: true } // 18 -> 20
                    Text { text: systemData.windSpeed.toFixed(1) + " m/s"; color: "#00FFFF"; font.family: customFont.name; font.pixelSize: 32; Layout.alignment: Qt.AlignRight } // 28 -> 32
                    
                    Text { text: "风向 DIR"; color: "#00A8FF"; font.pixelSize: 20; font.bold: true } // 18 -> 20
                    Text { text: systemData.windDirection; color: "#00FFFF"; font.family: customFont.name; font.pixelSize: 32; Layout.alignment: Qt.AlignRight } // 28 -> 32
                }
            }

            HudPanel {
                title: "实时地理位置"
                Layout.fillWidth: true; Layout.preferredHeight: parent.height * 0.3
                
                TechRadar {
                    anchors.fill: parent
                    anchors.margins: 10
                    
                    // 无人机蓝点
                    Rectangle {
                        id: dronePoint
                        width: 10; height: 10; radius: 5
                        color: "#0088FF"
                        x: parent.width * 0.7; y: parent.height * 0.3
                        visible: systemData.droneRunning
                        
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                var lat = (30.5 + Math.random() * 0.1).toFixed(4)
                                var lng = (114.3 + Math.random() * 0.1).toFixed(4)
                                msgPopup.display("无人机坐标: E" + lng + "°, N" + lat + "°")
                            }
                        }
                        
                        // 简单的呼吸动画
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 0.3; duration: 1000 }
                            NumberAnimation { from: 0.3; to: 1.0; duration: 1000 }
                        }
                    }
                    
                    // 无人船红点
                    Rectangle {
                        id: shipPoint
                        width: 10; height: 10; radius: 5
                        color: "#FF0000"
                        x: parent.width * 0.3; y: parent.height * 0.6
                        visible: systemData.shipRunning
                        
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                var lat = (30.4 + Math.random() * 0.1).toFixed(4)
                                var lng = (114.2 + Math.random() * 0.1).toFixed(4)
                                msgPopup.display("无人船坐标: E" + lng + "°, N" + lat + "°")
                            }
                        }
                        
                        // 航行交互：启动后在雷达上移动
                        NumberAnimation on x { running: systemData.shipRunning; from: shipPoint.parent.width * 0.2; to: shipPoint.parent.width * 0.8; duration: 15000; loops: Animation.Infinite }
                        NumberAnimation on y { running: systemData.shipRunning; from: shipPoint.parent.height * 0.8; to: shipPoint.parent.height * 0.2; duration: 15000; loops: Animation.Infinite }
                        
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 0.3; duration: 1000 }
                            NumberAnimation { from: 0.3; to: 1.0; duration: 1000 }
                        }
                    }
                }
            }
        }

        // --- 中心区域 (无人系统数据监测模块) ---
        Item {
            id: centerArea
            anchors.left: leftPanel.right
            anchors.right: rightPanel.left
            anchors.top: parent.top
            anchors.bottom: bottomPanel.top
            anchors.margins: 20
            
            HudPanel {
                title: "无人系统遥测监测 (Telemetry)"
                width: parent.width * 0.9; height: 220 // 0.8 -> 0.9, 180 -> 220
                anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 10
                
                RowLayout {
                    anchors.fill: parent; anchors.margins: 20; spacing: 40 // 15 -> 20, 30 -> 40
                    
                    // 无人机遥测数据
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 15 // 10 -> 15
                        Text { text: "● 无人机 (UAV)"; color: "#0088FF"; font.pixelSize: 24; font.bold: true } // 20 -> 24
                        GridLayout {
                            columns: 2; columnSpacing: 30; rowSpacing: 10 // 20 -> 30, 8 -> 10
                            Text { text: "高度 ALT:"; color: "#00A8FF"; font.pixelSize: 20; Layout.preferredWidth: 120 } // 18 -> 20, 100 -> 120
                            Text { text: systemData.droneTelemetry.altitude + " m"; color: "#00FFFF"; font.family: customFont.name; font.pixelSize: 28 } // 24 -> 28
                            Text { text: "速度 SPD:"; color: "#00A8FF"; font.pixelSize: 20 }
                            Text { text: systemData.droneTelemetry.speed + " m/s"; color: "#00FFFF"; font.family: customFont.name; font.pixelSize: 28 }
                            Text { text: "信号 SIG:"; color: "#00A8FF"; font.pixelSize: 20 }
                            Text { text: systemData.droneTelemetry.signal + "%"; color: "#00FF00"; font.family: customFont.name; font.pixelSize: 28 }
                        }
                    }
                    
                    // 垂直分割线
                    Rectangle { width: 2; Layout.fillHeight: true; color: Qt.rgba(0, 1, 1, 0.3) } // 1 -> 2
                    
                    // 无人船遥测数据
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 15
                        Text { text: "● 无人船 (USV)"; color: "#FF3333"; font.pixelSize: 24; font.bold: true } // 20 -> 24
                        GridLayout {
                            columns: 2; columnSpacing: 30; rowSpacing: 10
                            Text { text: "航速 SPD:"; color: "#00A8FF"; font.pixelSize: 20; Layout.preferredWidth: 120 } // 18 -> 20
                            Text { text: systemData.shipTelemetry.speed + " kn"; color: "#00FFFF"; font.family: customFont.name; font.pixelSize: 28 } // 24 -> 28
                            Text { text: "航向 HDG:"; color: "#00A8FF"; font.pixelSize: 20 }
                            Text { text: systemData.shipTelemetry.heading + " °"; color: "#00FFFF"; font.family: customFont.name; font.pixelSize: 28 }
                            Text { text: "通信 SIG:"; color: "#00A8FF"; font.pixelSize: 20 }
                            Text { text: systemData.shipTelemetry.signal + "%"; color: "#00FF00"; font.family: customFont.name; font.pixelSize: 28 }
                        }
                    }
                }
            }
        }

        // --- 底部控制台 (按钮位置已根据前次要求调整至红框处) ---
        RowLayout {
            id: bottomPanel
            anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.52; height: parent.height * 0.4; spacing: 30 // 0.35 -> 0.4 增加高度
            
            opacity: 0
            y: mainContent.height
            
            // 进场动画
            ParallelAnimation {
                running: true
                NumberAnimation { target: bottomPanel; property: "opacity"; to: 1.0; duration: 1500; easing.type: Easing.InOutQuad }
                NumberAnimation { target: bottomPanel; property: "y"; to: mainContent.height - bottomPanel.height; duration: 1200; easing.type: Easing.OutExpo }
            }

            // 数据分析圆饼图模块
            HudPanel {
                title: "水质数据分析"
                Layout.fillWidth: true; Layout.fillHeight: true
                TechPieChart {
                    anchors.fill: parent
                    anchors.margins: 10
                }
            }

            HudPanel {
                title: "无人机系统"
                Layout.fillWidth: true; Layout.fillHeight: true
                Item {
                    anchors.fill: parent
                    
                    // 左上：控制按钮与状态
                    RowLayout {
                        id: droneCtrlRow
                        anchors.top: parent.top; anchors.left: parent.left
                        spacing: 15
                        TechButton {
                            text: systemData.droneRunning ? "停止" : "启动巡检"; active: systemData.droneRunning
                            onClicked: {
                                systemData.droneRunning = !systemData.droneRunning
                                var action = systemData.droneRunning ? "start" : "close"
                                systemData.sendCommand("UVA", action)
                                msgPopup.display(systemData.droneRunning ? "指令确认：无人机起飞" : "指令确认：无人机降落")
                            }
                            Layout.preferredWidth: 140; Layout.preferredHeight: 50 // 进一步增大按钮
                        }
                        Text { text: "STATUS: " + (systemData.droneRunning ? "RUNNING" : "IDLE"); color: systemData.droneRunning ? "#00FF00" : "#666666"; font.family: customFont.name; font.pixelSize: 22 } // 18 -> 22
                    }
                    
                    // 居中：电量圆环 (遥测已移出)
                    Item {
                        anchors.top: droneCtrlRow.bottom; anchors.bottom: parent.bottom
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.topMargin: 10
                        
                        Item {
                            anchors.centerIn: parent
                            height: parent.height * 1.05 // 缩小比例，从 1.3 -> 1.05
                            width: height
                            
                            Canvas {
                                id: droneBatteryCanvas
                                anchors.fill: parent
                                property real value: systemData.droneTelemetry.battery / 100
                                onPaint: {
                                    var ctx = getContext("2d");
                                    var cx = width / 2; var cy = height / 2; var r = Math.min(width, height) / 2 * 0.85; // 0.88 -> 0.85
                                    ctx.clearRect(0, 0, width, height);
                                    
                                    ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                                    ctx.lineWidth = 10; ctx.strokeStyle = "rgba(0, 255, 255, 0.1)"; ctx.stroke(); // 12 -> 10
                                    
                                    ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI/2, -Math.PI/2 + value * 2 * Math.PI);
                                    ctx.lineWidth = 10; ctx.strokeStyle = value < 0.2 ? "#FF3333" : "#00FFFF"; ctx.stroke(); // 12 -> 10
                                }
                                onValueChanged: requestPaint()
                            }
                            Column {
                                anchors.centerIn: parent
                                Text { text: "电池电量"; color: "#00A8FF"; font.pixelSize: 18; anchors.horizontalCenter: parent.horizontalCenter; font.bold: true } // 24 -> 18
                                Text { text: systemData.droneTelemetry.battery + "%"; color: "white"; font.family: customFont.name; font.pixelSize: 32; anchors.horizontalCenter: parent.horizontalCenter } // 42 -> 32
                            }
                        }
                    }
                }
            }

            HudPanel {
                title: "无人船系统"
                Layout.fillWidth: true; Layout.fillHeight: true
                Item {
                    anchors.fill: parent
                    
                    // 左上：控制按钮与状态
                    RowLayout {
                        id: shipCtrlRow
                        anchors.top: parent.top; anchors.left: parent.left
                        spacing: 15
                        TechButton {
                            text: systemData.shipRunning ? "停止" : "开启航行"; active: systemData.shipRunning
                            onClicked: {
                                systemData.shipRunning = !systemData.shipRunning
                                var action = systemData.shipRunning ? "start" : "close"
                                systemData.sendCommand("USV", action)
                                msgPopup.display(systemData.shipRunning ? "指令确认：推进器已开启" : "指令确认：已切断动力")
                            }
                            Layout.preferredWidth: 140; Layout.preferredHeight: 50 // 进一步增大按钮
                        }
                        Text { text: "STATUS: " + (systemData.shipRunning ? "SAILING" : "DOCKED"); color: systemData.shipRunning ? "#00FF00" : "#666666"; font.family: customFont.name; font.pixelSize: 22 } // 18 -> 22
                    }
                    
                    // 居中：电量圆环 (遥测已移出)
                    Item {
                        anchors.top: shipCtrlRow.bottom; anchors.bottom: parent.bottom
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.topMargin: 10
                        
                        Item {
                            anchors.centerIn: parent
                            height: parent.height * 1.05 // 缩小比例，从 1.3 -> 1.05
                            width: height
                            
                            Canvas {
                                id: shipBatteryCanvas
                                anchors.fill: parent
                                property real value: systemData.shipTelemetry.battery / 100
                                onPaint: {
                                    var ctx = getContext("2d");
                                    var cx = width / 2; var cy = height / 2; var r = Math.min(width, height) / 2 * 0.85; // 0.88 -> 0.85
                                    ctx.clearRect(0, 0, width, height);
                                    
                                    ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                                    ctx.lineWidth = 10; ctx.strokeStyle = "rgba(0, 255, 255, 0.1)"; ctx.stroke(); // 12 -> 10
                                    
                                    ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI/2, -Math.PI/2 + value * 2 * Math.PI);
                                    ctx.lineWidth = 10; ctx.strokeStyle = value < 0.2 ? "#FF3333" : "#00FFFF"; ctx.stroke(); // 12 -> 10
                                }
                                onValueChanged: requestPaint()
                            }
                            Column {
                                anchors.centerIn: parent
                                Text { text: "电池电量"; color: "#00A8FF"; font.pixelSize: 18; anchors.horizontalCenter: parent.horizontalCenter; font.bold: true } // 24 -> 18
                                Text { text: systemData.shipTelemetry.battery + "%"; color: "white"; font.family: customFont.name; font.pixelSize: 32; anchors.horizontalCenter: parent.horizontalCenter } // 42 -> 32
                            }
                        }
                    }
                }
            }
        }
    }

    // 5. 指令反馈弹窗 - 修改为中心淡入
        Rectangle {
            id: msgPopup
            width: 400; height: 60; color: "#EE003333" // 深色背景
            border.color: "#00FFFF"; border.width: 1
            anchors.centerIn: parent

            opacity: 0 // 初始透明
            scale: 0.8 // 初始缩小

            Text {
                id: msgText
                anchors.centerIn: parent; color: "#00FFFF"; font.bold: true; font.pixelSize: 18; font.family: customFont.name
            }

            function display(txt) {
                msgText.text = txt
                msgText.font.pixelSize = 24 // 增大弹窗字号
                centerAnim.start()
            }

            ParallelAnimation {
                id: centerAnim
                SequentialAnimation {
                    NumberAnimation { target: msgPopup; property: "opacity"; from: 0; to: 1; duration: 300 }
                    PauseAnimation { duration: 1500 }
                    NumberAnimation { target: msgPopup; property: "opacity"; from: 1; to: 0; duration: 300 }
                }
                SequentialAnimation {
                    NumberAnimation { target: msgPopup; property: "scale"; from: 0.8; to: 1.1; duration: 300 }
                    NumberAnimation { target: msgPopup; property: "scale"; to: 1.0; duration: 100 }
                    PauseAnimation { duration: 1400 }
                    NumberAnimation { target: msgPopup; property: "scale"; to: 1.2; duration: 300 }
                }
            }
        }

        // 6. 严重报警弹窗 (居中，红色闪烁，需手动关闭)
        Rectangle {
            id: alarmPopup
            width: 500; height: 200; radius: 10
            color: Qt.rgba(50/255, 0, 0, 0.9); border.color: "#FF0000"; border.width: 3
            anchors.centerIn: parent
            visible: systemData.hasAlarm
            z: 999
            
            // 报警边框呼吸灯效果
            SequentialAnimation on border.color {
                loops: Animation.Infinite
                ColorAnimation { from: "#FF0000"; to: "#550000"; duration: 500 }
                ColorAnimation { from: "#550000"; to: "#FF0000"; duration: 500 }
            }
            
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 20
                
                RowLayout {
                    spacing: 15
                    Text { text: "⚠️"; color: "red"; font.pixelSize: 50 } // 40 -> 50
                    Text { text: "系统严重报警"; color: "white"; font.family: customFont.name; font.pixelSize: 36; font.bold: true } // 32 -> 36
                    Text { text: "⚠️"; color: "red"; font.pixelSize: 50 } // 40 -> 50
                }
                
                Text {
                    text: systemData.currentAlarmMsg
                    color: "#FF5555"; font.family: customFont.name; font.pixelSize: 24 // 20 -> 24
                    Layout.alignment: Qt.AlignHCenter
                }
                
                TechButton {
                    text: "确 认"; Layout.preferredWidth: 150; Layout.preferredHeight: 50 // 增大确认按钮
                    onClicked: systemData.acknowledgeAlarm()
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
        
        // 7. 系统设置面板 (弹出式)
        Rectangle {
            id: settingPopup
            width: 500; height: 550; radius: 10 // 400x300 -> 500x550 增加高度以容纳UDP设置
            color: Qt.rgba(0, 30/255, 40/255, 0.95); border.color: "#00A8FF"; border.width: 2
            anchors.centerIn: parent
            visible: false
            z: 1000
            
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 20
                spacing: 15 
                
                // 标题栏
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "⚙ 系统配置"; color: "#00FFFF"; font.pixelSize: 28; font.bold: true } 
                    Item { Layout.fillWidth: true } // 占位
                    Text { 
                        text: "✖"; color: "white"; font.pixelSize: 24; font.bold: true
                        MouseArea { anchors.fill: parent; onClicked: settingPopup.visible = false }
                    }
                }
                
                Rectangle { Layout.fillWidth: true; height: 1; color: "#00A8FF" } // 分割线
                
                // --- UDP 设置区 ---
                Text { text: "本地 UDP 监听设置 (接收数据)"; color: "#00FFFF"; font.pixelSize: 18; font.bold: true; Layout.topMargin: 10 }
                GridLayout {
                    columns: 2; columnSpacing: 20; rowSpacing: 15
                    Layout.fillWidth: true
                    
                    Text { text: "监听端口:"; color: "#00A8FF"; font.pixelSize: 16 }
                    TextField {
                        id: udpPortInput
                        Layout.fillWidth: true
                        text: "8080"
                        color: "white"
                        background: Rectangle { color: "#11FFFFFF"; border.color: "#00A8FF" }
                        font.pixelSize: 16
                    }
                    
                    Text { text: "当前状态:"; color: "#00A8FF"; font.pixelSize: 16 }
                    RowLayout {
                        Rectangle { width: 12; height: 12; radius: 6; color: systemData.isUdpOpen ? "#00FF00" : "#FF0000" }
                        Text { text: systemData.isUdpOpen ? "正在监听 (" + systemData.currentUdpPort + ")" : "未开启"
                               color: systemData.isUdpOpen ? "#00FF00" : "#FF0000"; font.pixelSize: 16 }
                    }
                }
                
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    TechButton {
                        text: systemData.isUdpOpen ? "停止监听" : "启动监听"
                        Layout.preferredWidth: 150; Layout.preferredHeight: 40
                        onClicked: {
                            if (systemData.isUdpOpen) {
                                systemData.closeUdpPort()
                            } else {
                                var port = parseInt(udpPortInput.text)
                                if (port > 0) {
                                    systemData.openUdpPort(port)
                                } else {
                                    msgPopup.display("请输入有效的UDP端口号")
                                }
                            }
                        }
                    }
                }
                
                Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(0, 168/255, 1, 0.3); Layout.topMargin: 10; Layout.bottomMargin: 10 } // 分割线
                
                // --- 串口设置区 (主要用于发送指令) ---
                Text { text: "硬件串口设置 (发送控制指令)"; color: "#00FFFF"; font.pixelSize: 18; font.bold: true }
                GridLayout {
                    columns: 2; columnSpacing: 20; rowSpacing: 15
                    Layout.fillWidth: true
                    
                    Text { text: "通信端口:"; color: "#00A8FF"; font.pixelSize: 16 }
                    ComboBox {
                        id: portCombo
                        Layout.fillWidth: true
                        model: systemData.getAvailablePorts()
                        onPressedChanged: {
                            if (pressed) model = systemData.getAvailablePorts() // 每次点击时刷新列表
                        }
                    }
                    
                    Text { text: "波特率:"; color: "#00A8FF"; font.pixelSize: 16 }
                    ComboBox {
                        id: baudCombo
                        Layout.fillWidth: true
                        model: ["9600", "115200", "38400", "4800"]
                        currentIndex: 1 // 默认设为 115200
                    }
                    
                    Text { text: "当前状态:"; color: "#00A8FF"; font.pixelSize: 16 }
                    RowLayout {
                        Rectangle { width: 12; height: 12; radius: 6; color: systemData.isSerialOpen ? "#00FF00" : "#FF0000" }
                        Text { text: systemData.isSerialOpen ? "已连接 (" + systemData.currentPortName + ")" : "未连接"
                               color: systemData.isSerialOpen ? "#00FF00" : "#FF0000"; font.pixelSize: 16 }
                    }
                }
                
                Item { Layout.fillHeight: true } // 弹性占位
                
                // 按钮区
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 20
                    
                    TechButton {
                        text: systemData.isSerialOpen ? "断开串口" : "连接串口"
                        Layout.fillWidth: true
                        onClicked: {
                            if (systemData.isSerialOpen) {
                                systemData.closeSerialPort()
                            } else {
                                var port = portCombo.currentText
                                var baud = parseInt(baudCombo.currentText)
                                if (port !== "") {
                                    systemData.openSerialPort(port, baud)
                                } else {
                                    msgPopup.display("请先选择一个有效的串口")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}