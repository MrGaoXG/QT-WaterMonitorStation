import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import QtCharts

Window {
    id: window
    width: 1920; height: 1080; visible: true; title: "水质监测地面站"
    color: "#020a0f"
    
    // 增加全局缩放比例，让字体和元素随窗口大小自适应
    property real scaleRatio: Math.min(width / 1920, height / 1080)

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
        scale: window.scaleRatio

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
                property color secondaryColor: systemData.hasAlarm ? "rgba(255, 0, 0, 0.4)" : "rgba(0, 255, 255, 0.4)"
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
                font.pixelSize: 42; font.bold: true; color: "#FFFFFF"; font.family: customFont.name
                style: Text.Outline; styleColor: systemData.hasAlarm ? "#FF0000" : "#00A8FF" // 增加发光描边感
            }
            
            // 英文副标题
            Text {
                text: "WATER QUALITY MONITORING SYSTEM"; anchors.top: parent.top; anchors.topMargin: 85
                anchors.horizontalCenter: parent.horizontalCenter
                font.pixelSize: 14; color: "#00A8FF"; font.family: customFont.name; font.letterSpacing: 5
            }

            // 左侧状态装饰
            RowLayout {
                anchors.left: parent.left; anchors.leftMargin: 40; y: 15
                spacing: 20
                RowLayout {
                    spacing: 8
                    Rectangle { 
                        width: 12; height: 12; radius: 6; color: "#00FF00" 
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 0.2; duration: 800 }
                            NumberAnimation { from: 0.2; to: 1.0; duration: 800 }
                        }
                    }
                    Text { text: "SYSTEM ONLINE"; color: "#00FF00"; font.family: customFont.name; font.pixelSize: 18 }
                }
                RowLayout {
                    spacing: 8
                    Rectangle { width: 12; height: 12; radius: 6; color: "#00A8FF" }
                    Text { text: "DATA LINK: SECURE"; color: "#00A8FF"; font.family: customFont.name; font.pixelSize: 18 }
                }
            }

            // 右侧时间显示与设置按钮
            RowLayout {
                anchors.right: parent.right; anchors.rightMargin: 40; y: 12
                spacing: 15
                
                // 系统设置按钮
                Rectangle {
                    width: 40; height: 40; radius: 20
                    color: "transparent"; border.color: "#00A8FF"; border.width: 2
                    Text { text: "⚙️"; anchors.centerIn: parent; font.pixelSize: 20 }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: parent.color = "rgba(0, 168, 255, 0.2)"
                        onExited: parent.color = "transparent"
                        onClicked: settingPopup.visible = true
                    }
                }
                
                Text {
                    text: "LOCAL TIME"; color: "#00A8FF"; font.family: customFont.name; font.pixelSize: 16
                }
                Text {
                    color: "#00FFFF"; font.family: customFont.name; font.pixelSize: 26; font.bold: true
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
                        spacing: 15
                        Repeater {
                            model: [ {name: "PH值", val: systemData.phValue/14, txt: systemData.phValue.toFixed(2)}, 
                                     {name: "溶解氧", val: systemData.dissolvedOxygen/10, txt: systemData.dissolvedOxygen.toFixed(2)}, 
                                     {name: "浊度", val: systemData.turbidity/10, txt: systemData.turbidity.toFixed(2)} ]
                            RowLayout {
                                Layout.fillWidth: true; Text { text: modelData.name; color: "white"; font.family: customFont.name; Layout.preferredWidth: 60 }
                                Rectangle { Layout.fillWidth: true; height: 12; color: "#2000FFFF"
                                    Rectangle { width: parent.width * modelData.val; height: parent.height; color: systemData.phValue > 8 && index == 0 ? "red" : "#00FFFF"; Behavior on width { NumberAnimation{duration:1000} } }
                                }
                                Text { text: modelData.txt; color: "#00FFFF"; font.family: customFont.name; Layout.preferredWidth: 40 }
                            }
                        }
                    }
                    
                    // 下方：历史趋势折线图
                    ChartView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        title: "过去24小时趋势"
                        titleColor: "#00A8FF"
                        titleFont.family: customFont.name
                        titleFont.pixelSize: 14
                        legend.visible: true
                        legend.labelColor: "white"
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
                            gridLineColor: Qt.rgba(0, 1.0, 1.0, 0.2)
                        }

                        ValueAxis {
                            id: axisY
                            min: 0; max: 40
                            tickCount: 5
                            labelsColor: "#00A8FF"
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
                Layout.fillWidth: true; Layout.preferredHeight: parent.height * 0.45 // 调小日志面板高度
                ListView {
                    anchors.fill: parent; model: logModel; clip: true; spacing: 5
                    delegate: Text {
                        text: "[" + time + "] " + info; color: info.indexOf("报警") !== -1 ? "red" : "#00FFFF"
                        font.family: customFont.name; font.pixelSize: 12
                    }
                }
                ListModel { id: logModel }
            }
            
            // 新增：环境气象数据面板 (填补红色留白区域)
            HudPanel {
                title: "环境气象数据"
                Layout.fillWidth: true; Layout.fillHeight: true
                
                GridLayout {
                    anchors.fill: parent; anchors.margins: 10
                    columns: 2; columnSpacing: 15; rowSpacing: 15
                    
                    Text { text: "温度 TEMP"; color: "#00A8FF"; font.pixelSize: 12 }
                    Text { text: systemData.temperature.toFixed(1) + " °C"; color: "#00FFFF"; font.family: customFont.name; font.pixelSize: 18; Layout.alignment: Qt.AlignRight }
                    
                    Text { text: "湿度 HUMID"; color: "#00A8FF"; font.pixelSize: 12 }
                    Text { text: systemData.humidity.toFixed(1) + " %"; color: "#00FFFF"; font.family: customFont.name; font.pixelSize: 18; Layout.alignment: Qt.AlignRight }
                    
                    Text { text: "风速 WIND"; color: "#00A8FF"; font.pixelSize: 12 }
                    Text { text: systemData.windSpeed.toFixed(1) + " m/s"; color: "#00FFFF"; font.family: customFont.name; font.pixelSize: 18; Layout.alignment: Qt.AlignRight }
                    
                    Text { text: "风向 DIR"; color: "#00A8FF"; font.pixelSize: 12 }
                    Text { text: systemData.windDirection; color: "#00FFFF"; font.family: customFont.name; font.pixelSize: 18; Layout.alignment: Qt.AlignRight }
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

        // --- 中心区域 (留白，展示背景图) ---
        Item {
            anchors.left: leftPanel.right
            anchors.right: rightPanel.left
            anchors.top: parent.top
            anchors.bottom: bottomPanel.top
            anchors.margins: 20
        }

        // --- 底部控制台 (按钮位置已根据前次要求调整至红框处) ---
        RowLayout {
            id: bottomPanel
            anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.52; height: parent.height * 0.35; spacing: 30
            
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
                        spacing: 10
                        TechButton {
                            text: systemData.droneRunning ? "停止" : "启动巡检"; active: systemData.droneRunning
                            onClicked: {
                                systemData.droneRunning = !systemData.droneRunning
                                var action = systemData.droneRunning ? "start" : "close"
                                systemData.sendCommand("UVA", action)
                                msgPopup.display(systemData.droneRunning ? "指令确认：无人机起飞" : "指令确认：无人机降落")
                            }
                        }
                        Text { text: "STATUS: " + (systemData.droneRunning ? "RUNNING" : "IDLE"); color: systemData.droneRunning ? "#00FF00" : "#666666"; font.family: customFont.name }
                    }
                    
                    // 右上：遥测参数显示
                    Column {
                        anchors.top: parent.top; anchors.right: parent.right; anchors.rightMargin: 5
                        spacing: 4
                        
                        RowLayout {
                            Text { text: "高度 ALT:"; color: "#00A8FF"; font.pixelSize: 12; Layout.preferredWidth: 60 }
                            Text { text: systemData.droneTelemetry.altitude + " m"; color: "#00FFFF"; font.family: customFont.name; font.pixelSize: 14 }
                        }
                        RowLayout {
                            Text { text: "速度 SPD:"; color: "#00A8FF"; font.pixelSize: 12; Layout.preferredWidth: 60 }
                            Text { text: systemData.droneTelemetry.speed + " m/s"; color: "#00FFFF"; font.family: customFont.name; font.pixelSize: 14 }
                        }
                        RowLayout {
                            Text { text: "信号 SIG:"; color: "#00A8FF"; font.pixelSize: 12; Layout.preferredWidth: 60 }
                            Text { text: systemData.droneTelemetry.signal + "%"; color: "#00FF00"; font.family: customFont.name; font.pixelSize: 14 }
                        }
                    }
                    
                    // 中下：电量饼图居中
                    Item {
                        anchors.top: droneCtrlRow.bottom; anchors.bottom: parent.bottom
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.topMargin: 5
                        
                        Item {
                            anchors.centerIn: parent
                            height: parent.height
                            width: height
                            
                            Canvas {
                                id: droneBatteryCanvas
                                anchors.fill: parent
                                property real value: systemData.droneTelemetry.battery / 100
                                onPaint: {
                                    var ctx = getContext("2d");
                                    var cx = width / 2; var cy = height / 2; var r = Math.min(width, height) / 2 * 0.8;
                                    ctx.clearRect(0, 0, width, height);
                                    
                                    ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                                    ctx.lineWidth = 6; ctx.strokeStyle = "rgba(0, 255, 255, 0.1)"; ctx.stroke();
                                    
                                    ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI/2, -Math.PI/2 + value * 2 * Math.PI);
                                    ctx.lineWidth = 6; ctx.strokeStyle = value < 0.2 ? "#FF3333" : "#00FFFF"; ctx.stroke();
                                }
                                onValueChanged: requestPaint()
                            }
                            Column {
                                anchors.centerIn: parent
                                Text { text: "电量"; color: "#00A8FF"; font.pixelSize: 10; anchors.horizontalCenter: parent.horizontalCenter }
                                Text { text: systemData.droneTelemetry.battery + "%"; color: "white"; font.family: customFont.name; font.pixelSize: 14; anchors.horizontalCenter: parent.horizontalCenter }
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
                        spacing: 10
                        TechButton {
                            text: systemData.shipRunning ? "停止" : "开启航行"; active: systemData.shipRunning
                            onClicked: {
                                systemData.shipRunning = !systemData.shipRunning
                                var action = systemData.shipRunning ? "start" : "close"
                                systemData.sendCommand("USV", action)
                                msgPopup.display(systemData.shipRunning ? "指令确认：推进器已开启" : "指令确认：已切断动力")
                            }
                        }
                        Text { text: "STATUS: " + (systemData.shipRunning ? "SAILING" : "DOCKED"); color: systemData.shipRunning ? "#00FF00" : "#666666"; font.family: customFont.name }
                    }
                    
                    // 右上：遥测参数显示
                    Column {
                        anchors.top: parent.top; anchors.right: parent.right; anchors.rightMargin: 5
                        spacing: 4
                        
                        RowLayout {
                            Text { text: "航速 SPD:"; color: "#00A8FF"; font.pixelSize: 12; Layout.preferredWidth: 60 }
                            Text { text: systemData.shipTelemetry.speed + " kn"; color: "#00FFFF"; font.family: customFont.name; font.pixelSize: 14 }
                        }
                        RowLayout {
                            Text { text: "航向 HDG:"; color: "#00A8FF"; font.pixelSize: 12; Layout.preferredWidth: 60 }
                            Text { text: systemData.shipTelemetry.heading + " °"; color: "#00FFFF"; font.family: customFont.name; font.pixelSize: 14 }
                        }
                        RowLayout {
                            Text { text: "通信 SIG:"; color: "#00A8FF"; font.pixelSize: 12; Layout.preferredWidth: 60 }
                            Text { text: systemData.shipTelemetry.signal + "%"; color: "#00FF00"; font.family: customFont.name; font.pixelSize: 14 }
                        }
                    }
                    
                    // 中下：电量饼图居中
                    Item {
                        anchors.top: shipCtrlRow.bottom; anchors.bottom: parent.bottom
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.topMargin: 5
                        
                        Item {
                            anchors.centerIn: parent
                            height: parent.height
                            width: height
                            
                            Canvas {
                                id: shipBatteryCanvas
                                anchors.fill: parent
                                property real value: systemData.shipTelemetry.battery / 100
                                onPaint: {
                                    var ctx = getContext("2d");
                                    var cx = width / 2; var cy = height / 2; var r = Math.min(width, height) / 2 * 0.8;
                                    ctx.clearRect(0, 0, width, height);
                                    
                                    ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                                    ctx.lineWidth = 6; ctx.strokeStyle = "rgba(0, 255, 255, 0.1)"; ctx.stroke();
                                    
                                    ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI/2, -Math.PI/2 + value * 2 * Math.PI);
                                    ctx.lineWidth = 6; ctx.strokeStyle = value < 0.2 ? "#FF3333" : "#00FFFF"; ctx.stroke();
                                }
                                onValueChanged: requestPaint()
                            }
                            Column {
                                anchors.centerIn: parent
                                Text { text: "电量"; color: "#00A8FF"; font.pixelSize: 10; anchors.horizontalCenter: parent.horizontalCenter }
                                Text { text: systemData.shipTelemetry.battery + "%"; color: "white"; font.family: customFont.name; font.pixelSize: 14; anchors.horizontalCenter: parent.horizontalCenter }
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
                    Text { text: "⚠️"; color: "red"; font.pixelSize: 40 }
                    Text { text: "系统严重报警"; color: "white"; font.family: customFont.name; font.pixelSize: 32; font.bold: true }
                    Text { text: "⚠️"; color: "red"; font.pixelSize: 40 }
                }
                
                Text {
                    text: systemData.currentAlarmMsg
                    color: "#FF5555"; font.family: customFont.name; font.pixelSize: 20
                    Layout.alignment: Qt.AlignHCenter
                }
                
                // 确认并关闭按钮
                Rectangle {
                    width: 150; height: 40; radius: 5; color: "#FF0000"
                    Layout.alignment: Qt.AlignHCenter
                    Text { text: "确认并关闭"; color: "white"; font.family: customFont.name; font.pixelSize: 18; anchors.centerIn: parent; font.bold: true }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            systemData.acknowledgeAlarm()
                        }
                    }
                }
            }
        }
        
        // 7. 系统设置面板 (弹出式)
        Rectangle {
            id: settingPopup
            width: 400; height: 300; radius: 10
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
                    Text { text: "⚙ 系统配置"; color: "#00FFFF"; font.pixelSize: 22; font.bold: true }
                    Item { Layout.fillWidth: true } // 占位
                    Text { 
                        text: "✖"; color: "white"; font.pixelSize: 20 
                        MouseArea { anchors.fill: parent; onClicked: settingPopup.visible = false }
                    }
                }
                
                Rectangle { Layout.fillWidth: true; height: 1; color: "#00A8FF" } // 分割线
                
                // 串口设置区
                GridLayout {
                    columns: 2; columnSpacing: 20; rowSpacing: 20
                    Layout.fillWidth: true; Layout.topMargin: 10
                    
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
                        currentIndex: 0
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
                        text: systemData.isSerialOpen ? "断开连接" : "连接串口"
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