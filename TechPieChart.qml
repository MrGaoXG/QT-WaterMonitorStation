import QtQuick 2.15

Item {
    id: root
    property variant slices: [
        { "value": 30, "color": "#00FFFF", "label": "正常" },
        { "value": 45, "color": "#0088FF", "label": "轻度污染" },
        { "value": 15, "color": "#FF8800", "label": "中度污染" },
        { "value": 10, "color": "#FF0000", "label": "重度污染" }
    ]

    // 静态部分（饼图本体、标签、阴影）使用单独的 Canvas 绘制，避免频繁重绘
    Canvas {
        id: staticCanvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject // 提升性能
        renderStrategy: Canvas.Threaded        // 异步渲染
        
        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            var cx = width / 2;
            var cy = height / 2;
            var radius = Math.min(width, height) / 2 * 0.75;

            // --- 1. 绘制发光阴影层 (固定) ---
            ctx.beginPath();
            ctx.arc(cx, cy, radius, 0, 2 * Math.PI);
            ctx.fillStyle = "rgba(0, 255, 255, 0.05)";
            ctx.shadowColor = "#00FFFF";
            ctx.shadowBlur = 15; // 降低模糊度提升性能
            ctx.fill();
            ctx.shadowBlur = 0; // 重置阴影

            // --- 2. 绘制核心数据饼图及标签 ---
            var total = 0;
            for (var i = 0; i < slices.length; i++) {
                total += slices[i].value;
            }

            var startAngle = -Math.PI / 2;
            
            for (var j = 0; j < slices.length; j++) {
                var sliceAngle = (slices[j].value / total) * 2 * Math.PI;
                var endAngle = startAngle + sliceAngle;

                ctx.beginPath();
                ctx.moveTo(cx, cy);
                ctx.arc(cx, cy, radius, startAngle, endAngle);
                ctx.closePath();

                // 使用渐变色增强立体感
                var gradient = ctx.createRadialGradient(cx, cy, radius * 0.5, cx, cy, radius);
                gradient.addColorStop(0, "rgba(2, 10, 15, 0.8)"); // 内部深色
                gradient.addColorStop(1, slices[j].color);

                ctx.fillStyle = gradient;
                ctx.fill();

                // 绘制科技感边界线
                ctx.lineWidth = 2;
                ctx.strokeStyle = "#020a0f";
                ctx.stroke();

                // --- 绘制标签引线 ---
                var midAngle = startAngle + sliceAngle / 2;
                
                var startX = cx + Math.cos(midAngle) * radius;
                var startY = cy + Math.sin(midAngle) * radius;
                
                var turnDist = radius + 15;
                var turnX = cx + Math.cos(midAngle) * turnDist;
                var turnY = cy + Math.sin(midAngle) * turnDist;
                
                var endDist = turnDist + 30;
                var endX;
                var textAlign;
                
                if (Math.cos(midAngle) > 0) {
                    endX = cx + endDist;
                    textAlign = "left";
                } else {
                    endX = cx - endDist;
                    textAlign = "right";
                }

                ctx.beginPath();
                ctx.moveTo(startX, startY);
                ctx.lineTo(turnX, turnY);
                ctx.lineTo(endX, turnY);
                ctx.strokeStyle = slices[j].color;
                ctx.lineWidth = 1;
                ctx.setLineDash([3, 3]);
                ctx.stroke();
                ctx.setLineDash([]); 
                
                // 增加标签字体大小
                ctx.fillStyle = slices[j].color;
                ctx.font = "bold 18px " + (typeof customFont !== 'undefined' ? customFont.name : "Arial"); // 14px -> 18px
                ctx.textAlign = textAlign;
                ctx.fillText(slices[j].label + ": " + slices[j].value + "%", endX, turnY - 8);
                
                ctx.beginPath();
                ctx.arc(endX, turnY, 3, 0, 2 * Math.PI); // 2 -> 3
                ctx.fillStyle = slices[j].color;
                ctx.fill();

                startAngle = endAngle; // 确保 startAngle 在循环末尾更新
            }
            
            // --- 3. 绘制中心空心遮罩（甜甜圈效果） ---
            ctx.beginPath();
            ctx.arc(cx, cy, radius * 0.55, 0, 2 * Math.PI);
            ctx.fillStyle = "#020a0f";
            ctx.fill();

            // --- 4. 中心文字 ---
            ctx.fillStyle = "#00FFFF";
            ctx.font = "bold 24px sans-serif"; // 20px -> 24px
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillText("水质", cx, cy - 14);
            ctx.fillText("分析", cx, cy + 14);
        }
    }

    // 动态外环旋转角度
    property real outerRotation: 0
    NumberAnimation on outerRotation {
        from: 0; to: 360; duration: 15000; loops: Animation.Infinite; running: true
    }

    // 动态内环反向旋转
    property real innerRotation: 360
    NumberAnimation on innerRotation {
        from: 360; to: 0; duration: 10000; loops: Animation.Infinite; running: true
    }

    // 呼吸发光效果 (通过调整透明度实现，不再重绘 Canvas)
    property real glowOpacity: 0.5
    SequentialAnimation on glowOpacity {
        loops: Animation.Infinite
        NumberAnimation { from: 0.3; to: 0.8; duration: 2000; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.8; to: 0.3; duration: 2000; easing.type: Easing.InOutSine }
    }

    // 动态层使用独立的 Item 结合 QML 原生变换实现旋转，极大提升性能
    Item {
        id: dynamicLayer
        anchors.fill: parent
        opacity: root.glowOpacity // 呼吸效果直接作用于图层透明度

        // 外环
        Canvas {
            id: outerRingCanvas
            anchors.fill: parent
            renderTarget: Canvas.FramebufferObject
            rotation: root.outerRotation // 使用 QML 原生旋转，避免 Canvas 内部旋转重绘
            
            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                var cx = width / 2;
                var cy = height / 2;
                var radius = Math.min(width, height) / 2 * 0.75;

                ctx.beginPath();
                ctx.arc(cx, cy, radius + 15, 0, 1.5 * Math.PI);
                ctx.strokeStyle = "rgba(0, 255, 255, 1.0)";
                ctx.lineWidth = 2;
                ctx.setLineDash([5, 10]);
                ctx.stroke();

                ctx.beginPath();
                ctx.arc(cx, cy, radius + 22, 0.5 * Math.PI, 2 * Math.PI);
                ctx.strokeStyle = "rgba(0, 136, 255, 1.0)";
                ctx.lineWidth = 1;
                ctx.setLineDash([20, 5, 5, 5]);
                ctx.stroke();
            }
        }

        // 内环
        Canvas {
            id: innerRingCanvas
            anchors.fill: parent
            renderTarget: Canvas.FramebufferObject
            rotation: root.innerRotation // 使用 QML 原生旋转
            
            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                var cx = width / 2;
                var cy = height / 2;
                var radius = Math.min(width, height) / 2 * 0.75;

                ctx.beginPath();
                ctx.arc(cx, cy, radius * 0.5, 0, 2 * Math.PI);
                ctx.strokeStyle = "rgba(0, 255, 255, 0.8)";
                ctx.lineWidth = 2;
                ctx.setLineDash([2, 4]);
                ctx.stroke();
                
                ctx.beginPath();
                ctx.moveTo(cx, cy - radius * 0.5); ctx.lineTo(cx, cy - radius * 0.4);
                ctx.moveTo(cx, cy + radius * 0.5); ctx.lineTo(cx, cy + radius * 0.4);
                ctx.moveTo(cx - radius * 0.5, cy); ctx.lineTo(cx - radius * 0.4, cy);
                ctx.moveTo(cx + radius * 0.5, cy); ctx.lineTo(cx + radius * 0.4, cy);
                ctx.strokeStyle = "#00FFFF";
                ctx.lineWidth = 2;
                ctx.setLineDash([]);
                ctx.stroke();
            }
        }
    }

    onSlicesChanged: staticCanvas.requestPaint()
}
