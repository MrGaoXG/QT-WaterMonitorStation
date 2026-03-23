import QtQuick 2.15

// 2.5D 贴图伪造技术的数字孪生场景
Item {
    id: root
    anchors.fill: parent

    // ========================================================
    // 1. 静态高清底图
    // ========================================================
    Image {
        id: bgImage
        anchors.fill: parent
        source: "qrc:/dam_isometric.png"
        fillMode: Image.PreserveAspectCrop // 保证图片填满整个面板而不留黑边
        smooth: true
        mipmap: true
        
        // 增加一层极淡的深色遮罩，让上层的发光特效更明显
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.15
        }

        // ========================================================
        // 2. 动态光效叠加 (发光管道/数据流)
        // ========================================================
        Canvas {
            id: flowEffect
            anchors.fill: parent
            property real offset: 0
            
            NumberAnimation on offset {
                from: 0; to: 20; duration: 500; loops: Animation.Infinite; running: true
            }

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                
                // 蓝色光流：沿着大坝下方的水流方向
                ctx.strokeStyle = "#00FFFF";
                ctx.lineWidth = 3;
                ctx.shadowColor = "#00FFFF";
                ctx.shadowBlur = 10;
                ctx.setLineDash([15, 10]);
                ctx.lineDashOffset = -offset;

                ctx.beginPath();
                ctx.moveTo(width * 0.3, height * 0.8);
                ctx.lineTo(width * 0.45, height * 0.7); 
                ctx.lineTo(width * 0.6, height * 0.7);
                ctx.stroke();
                
                // 红色警报流：沿着右侧发电机组塔柱
                ctx.strokeStyle = "#FF0000";
                ctx.shadowColor = "#FF0000";
                ctx.beginPath();
                ctx.moveTo(width * 0.8, height * 0.6);
                ctx.lineTo(width * 0.8, height * 0.3);
                ctx.stroke();
            }
            onOffsetChanged: requestPaint()
        }

        // ========================================================
        // 3. 动态元素：无人机巡检 (悬停在左侧上方)
        // ========================================================
        Item {
            id: drone
            width: 80; height: 80
            x: bgImage.width * 0.2; y: bgImage.height * 0.2
            visible: systemData.droneRunning

            // 更有科技感的无人机占位符
            Item {
                anchors.centerIn: parent
                width: 40; height: 15
                Rectangle { anchors.fill: parent; radius: 7; color: "#0a1526"; border.color: "#00ffff"; border.width: 1 }
                // 四个旋翼
                Rectangle { x: -10; y: -5; width: 15; height: 3; color: "#00ffff"; rotation: 45 }
                Rectangle { x: 35; y: -5; width: 15; height: 3; color: "#00ffff"; rotation: -45 }
                // 呼吸指示灯
                Rectangle {
                    anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: "#00ffff"
                    SequentialAnimation on opacity { 
                        loops: Animation.Infinite
                        NumberAnimation {from: 0.2; to: 1.0; duration: 500}
                        NumberAnimation {from: 1.0; to: 0.2; duration: 500} 
                    }
                }
            }

            // 底部扫描光锥
            Canvas {
                anchors.top: parent.verticalCenter; anchors.horizontalCenter: parent.horizontalCenter
                width: 120; height: 150
                onPaint: {
                    var ctx = getContext("2d");
                    var grad = ctx.createLinearGradient(0, 0, 0, height);
                    grad.addColorStop(0, "rgba(0, 255, 255, 0.4)"); grad.addColorStop(1, "rgba(0, 255, 255, 0)");
                    ctx.fillStyle = grad; ctx.beginPath(); ctx.moveTo(60, 0); ctx.lineTo(120, 150); ctx.lineTo(0, 150); ctx.fill();
                }
                SequentialAnimation on rotation { 
                    loops: Animation.Infinite
                    NumberAnimation { from: -20; to: 20; duration: 1500; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 20; to: -20; duration: 1500; easing.type: Easing.InOutSine } 
                }
            }

            // 巡检路径动画：在水面上方盘旋
            SequentialAnimation on x {
                running: systemData.droneRunning; loops: Animation.Infinite
                NumberAnimation { to: bgImage.width * 0.7; duration: 6000; easing.type: Easing.InOutSine } 
                NumberAnimation { to: bgImage.width * 0.2; duration: 6000; easing.type: Easing.InOutSine } 
            }
            SequentialAnimation on y {
                running: systemData.droneRunning; loops: Animation.Infinite
                NumberAnimation { to: bgImage.height * 0.15; duration: 3000; easing.type: Easing.InOutSine } 
                NumberAnimation { to: bgImage.height * 0.25; duration: 3000; easing.type: Easing.InOutSine } 
            }
        }

        // ========================================================
        // 4. 动态元素：无人船 (在下方的水面上)
        // ========================================================
        Item {
            id: ship
            width: 50; height: 30
            x: bgImage.width * 0.1; y: bgImage.height * 0.75 
            visible: systemData.shipRunning

            // 更有科技感的船体占位符 (菱形)
            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.fillStyle = "rgba(255, 0, 0, 0.7)";
                    ctx.strokeStyle = "#ff0000";
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    ctx.moveTo(25, 0); ctx.lineTo(50, 15); ctx.lineTo(25, 30); ctx.lineTo(0, 15);
                    ctx.closePath();
                    ctx.fill(); ctx.stroke();
                }
            }

            // 水面雷达扩散波纹
            Rectangle {
                anchors.centerIn: parent
                width: 120; height: 60; radius: 60 // 椭圆模拟透视
                color: "transparent"; border.color: "red"; border.width: 1
                SequentialAnimation on scale { 
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.1; to: 1.5; duration: 1500 } 
                }
                SequentialAnimation on opacity { 
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.8; to: 0.0; duration: 1500 } 
                }
            }

            // 沿着下方的水流路径巡航
            SequentialAnimation on x {
                running: systemData.shipRunning; loops: Animation.Infinite
                NumberAnimation { to: bgImage.width * 0.8; duration: 10000; easing.type: Easing.InOutQuad }
                NumberAnimation { to: bgImage.width * 0.1; duration: 10000; easing.type: Easing.InOutQuad }
            }
            SequentialAnimation on y {
                running: systemData.shipRunning; loops: Animation.Infinite
                NumberAnimation { to: bgImage.height * 0.85; duration: 10000; easing.type: Easing.InOutQuad }
                NumberAnimation { to: bgImage.height * 0.75; duration: 10000; easing.type: Easing.InOutQuad }
            }
        }
        
        // ========================================================
        // 5. 交互式数据标签 (固定在图中的大坝机组上方)
        // ========================================================
        Item {
            // 将坐标定位到图片中央偏上的大坝厂房位置
            x: bgImage.width * 0.5; y: bgImage.height * 0.4
            
            // 跳动的小光点指示器
            Rectangle {
                id: dot
                width: 16; height: 16; radius: 8; color: "#00ffff"
                SequentialAnimation on scale { 
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.8; to: 1.3; duration: 800 }
                    NumberAnimation { from: 1.3; to: 0.8; duration: 800 } 
                }
                // 外圈光晕
                Rectangle {
                    anchors.centerIn: parent; width: 24; height: 24; radius: 12; color: "transparent"; border.color: "#00ffff"; border.width: 1
                }
            }
            
            // 悬浮数据框
            Rectangle {
                anchors.bottom: dot.top; anchors.bottomMargin: 20; anchors.horizontalCenter: dot.horizontalCenter
                width: 140; height: 70; color: Qt.rgba(0, 30/255, 60/255, 0.85); border.color: "#00ffff"; radius: 4
                // 科技感小角标
                Rectangle { width: 8; height: 8; color: "#00ffff"; anchors.top: parent.top; anchors.left: parent.left }
                
                Column {
                    anchors.centerIn: parent; spacing: 8
                    Text { text: "1号水轮发电机组"; color: "#aaddff"; font.pixelSize: 12; font.family: customFont.name }
                    Text { text: "瞬时流速: 45 m³/s"; color: "#00ffff"; font.pixelSize: 15; font.bold: true; font.family: customFont.name }
                }
            }
            
            // 连接线
            Rectangle { width: 2; height: 20; color: "#00ffff"; anchors.bottom: dot.top; anchors.horizontalCenter: dot.horizontalCenter }
        }
    }
}
