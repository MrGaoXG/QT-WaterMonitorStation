import QtQuick 2.15

Item {
    id: root
    width: 200; height: 200
    
    // 生成随机环境噪点目标
    property var blips: []
    Timer {
        interval: 800; running: true; repeat: true
        onTriggered: {
            var newBlips = [];
            for (var i = 0; i < root.blips.length; i++) {
                if (Math.random() > 0.3) {
                    var b = root.blips[i];
                    b.life -= 0.1;
                    if (b.life > 0) newBlips.push(b);
                }
            }
            if (Math.random() > 0.4) {
                var angle = root.scanAngle + Math.random() * 0.5;
                var r = Math.random() * (Math.min(width, height) / 2 * 0.9);
                newBlips.push({ angle: angle, r: r, life: 1.0 });
            }
            root.blips = newBlips;
            blipCanvas.requestPaint(); // 仅重绘噪点
        }
    }

    // 呼吸边框透明度
    property real borderOpacity: 0.8
    SequentialAnimation on borderOpacity {
        loops: Animation.Infinite
        NumberAnimation { from: 0.4; to: 0.9; duration: 1500 }
        NumberAnimation { from: 0.9; to: 0.4; duration: 1500 }
    }
    
    // 全局扫描角度
    property real scanAngle: 0
    NumberAnimation on scanAngle {
        from: 0; to: 2 * Math.PI; duration: 2500; loops: Animation.Infinite; running: true
    }

    // 1. 静态雷达网格层（包含发光特效），仅绘制一次
    Canvas {
        id: gridCanvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        renderStrategy: Canvas.Threaded
        opacity: 0.2 + root.borderOpacity * 0.8 // 利用 QML 的 opacity 而不是重绘
        
        onPaint: {
            var ctx = getContext("2d");
            var cx = width / 2;
            var cy = height / 2;
            var radius = Math.min(width, height) / 2 * 0.9;
            
            ctx.clearRect(0, 0, width, height);
            
            ctx.strokeStyle = "rgba(0, 255, 255, 0.5)";
            ctx.lineWidth = 1;
            ctx.shadowColor = "#00FFFF";
            ctx.shadowBlur = 5;
            
            // 同心圆 (带有虚线效果)
            for (var i = 1; i <= 4; i++) {
                ctx.beginPath();
                ctx.arc(cx, cy, radius * (i/4), 0, 2 * Math.PI);
                if (i === 4) {
                    ctx.lineWidth = 2;
                    ctx.setLineDash([]);
                } else {
                    ctx.lineWidth = 1;
                    ctx.setLineDash([3, 5]);
                }
                ctx.stroke();
            }
            ctx.setLineDash([]); 
            
            // 十字交叉线及刻度
            ctx.beginPath();
            ctx.moveTo(cx, cy - radius - 5); ctx.lineTo(cx, cy + radius + 5);
            ctx.moveTo(cx - radius - 5, cy); ctx.lineTo(cx + radius + 5, cy);
            
            // 对角线
            var diagR = radius * 0.9;
            ctx.moveTo(cx - diagR * 0.707, cy - diagR * 0.707); ctx.lineTo(cx + diagR * 0.707, cy + diagR * 0.707);
            ctx.moveTo(cx - diagR * 0.707, cy + diagR * 0.707); ctx.lineTo(cx + diagR * 0.707, cy - diagR * 0.707);
            
            ctx.stroke();
        }
    }

    // 2. 动态噪点层（低频刷新）
    Canvas {
        id: blipCanvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        renderStrategy: Canvas.Threaded
        
        onPaint: {
            var ctx = getContext("2d");
            var cx = width / 2;
            var cy = height / 2;
            ctx.clearRect(0, 0, width, height);
            
            ctx.fillStyle = "#00FFFF";
            for (var k = 0; k < root.blips.length; k++) {
                var blip = root.blips[k];
                var bx = cx + Math.cos(blip.angle) * blip.r;
                var by = cy + Math.sin(blip.angle) * blip.r;
                
                ctx.globalAlpha = blip.life * 0.8;
                ctx.beginPath();
                ctx.arc(bx, by, 2, 0, 2 * Math.PI);
                ctx.fill();
            }
            ctx.globalAlpha = 1.0;
        }
    }

    // 3. 动态扫描扇形层（高频刷新）
    Canvas {
        id: scanCanvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        renderStrategy: Canvas.Threaded
        
        // 利用 QML 引擎的旋转机制，而不是在 JS 中频繁调用数学计算重绘
        rotation: root.scanAngle * 180 / Math.PI 
        
        onPaint: {
            var ctx = getContext("2d");
            var cx = width / 2;
            var cy = height / 2;
            var radius = Math.min(width, height) / 2 * 0.9;
            
            ctx.clearRect(0, 0, width, height);
            
            // 注意：因为父级 Canvas 会跟着旋转，这里的绘制基于 0 度开始即可
            var startAngle = 0;
            var tailLength = 1.5; 
            var endAngle = startAngle + tailLength; 
            
            // 修复 Qt Canvas 2D API 兼容性问题：
            // 某些 Qt 版本不支持 createConicGradient，使用近似的 radial 或线性渐变，或者直接用带透明度的纯色填充模拟
            ctx.beginPath();
            ctx.moveTo(cx, cy);
            ctx.arc(cx, cy, radius, startAngle, endAngle);
            ctx.closePath();
            
            ctx.fillStyle = "rgba(0, 255, 255, 0.2)";
            ctx.fill();
            
            // 高亮扫描主线 (绘制在 endAngle 处)
            ctx.beginPath();
            ctx.moveTo(cx, cy);
            ctx.lineTo(cx + Math.cos(endAngle) * radius, cy + Math.sin(endAngle) * radius);
            ctx.strokeStyle = "#FFFFFF"; 
            ctx.lineWidth = 2;
            ctx.shadowColor = "#00FFFF";
            ctx.shadowBlur = 10;
            ctx.stroke();
            
            // 中心发光点
            ctx.beginPath();
            ctx.arc(cx, cy, 3, 0, 2 * Math.PI);
            ctx.fillStyle = "#FFFFFF";
            ctx.fill();
        }
        
        // 只有大小改变时才需要重绘
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()
    }
}
