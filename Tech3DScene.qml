import QtQuick 2.15
import QtQuick3D

View3D {
    id: view
    anchors.fill: parent

    environment: SceneEnvironment {
        clearColor: "transparent"
        backgroundMode: SceneEnvironment.Transparent
        antialiasingMode: SceneEnvironment.MSAA
        antialiasingQuality: SceneEnvironment.High
        probeExposure: 1.5
    }

    // 摄像机设置 (等距视角)
    PerspectiveCamera {
        id: camera
        position: Qt.vector3d(0, 800, 1000)
        eulerRotation.x: -35
    }

    // 环境光与主光源 (恢复亮度和冷色调，照亮全息模型)
    DirectionalLight {
        eulerRotation.x: -45
        eulerRotation.y: -45
        color: Qt.rgba(0.8, 0.9, 1.0, 1.0)
        ambientColor: Qt.rgba(0.1, 0.3, 0.5, 1.0)
        brightness: 2.0
        castsShadow: false // 全息风格不需要强烈阴影
    }
    
    // 补光灯
    DirectionalLight {
        eulerRotation.x: -45
        eulerRotation.y: 135
        color: Qt.rgba(0.0, 0.8, 1.0, 1.0)
        brightness: 1.0
    }

    // 整个场景节点 (微缩模型底座)
    Node {
        id: sceneRoot
        
        SequentialAnimation on eulerRotation.y {
            loops: Animation.Infinite
            NumberAnimation { from: -15; to: 15; duration: 25000; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 15; to: -15; duration: 25000; easing.type: Easing.InOutQuad }
        }

        // --- 0. 微缩模型底座 (浅蓝透明全息网格感) ---
        Model {
            position: Qt.vector3d(0, -10, 0)
            scale: Qt.vector3d(15, 0.1, 10)
            source: "#Cube"
            materials: PrincipledMaterial {
                baseColor: "#003355"
                opacity: 0.6
                metalness: 0.5
                emissiveFactor: Qt.vector3d(0.0, 0.2, 0.4)
            }
        }
        
        // 底座发光边缘框
        Model {
            position: Qt.vector3d(0, -5, 0)
            scale: Qt.vector3d(15.2, 0.15, 10.2)
            source: "#Cube"
            materials: PrincipledMaterial {
                baseColor: "transparent"
                emissiveFactor: Qt.vector3d(0.0, 1.5, 2.0)
                opacity: 0.8
            }
        }

        // --- 1. 大坝主体建筑 (全息蓝晶质感) ---
        Node {
            position: Qt.vector3d(0, 0, -200)
            
            // 左侧高塔
            Model {
                position: Qt.vector3d(-400, 150, 0)
                scale: Qt.vector3d(2, 3, 2)
                source: "#Cube"
                materials: PrincipledMaterial { 
                    baseColor: "#006699"; 
                    opacity: 0.85; 
                    emissiveFactor: Qt.vector3d(0.0, 0.3, 0.6) 
                }
            }
            // 左侧高塔发光线
            Model {
                position: Qt.vector3d(-400, 290, 105)
                scale: Qt.vector3d(2, 0.1, 0.1)
                source: "#Cube"
                materials: PrincipledMaterial { emissiveFactor: Qt.vector3d(0, 2, 2) }
            }

            // 右侧高塔
            Model {
                position: Qt.vector3d(400, 150, 0)
                scale: Qt.vector3d(2, 3, 2)
                source: "#Cube"
                materials: PrincipledMaterial { 
                    baseColor: "#006699"; 
                    opacity: 0.85; 
                    emissiveFactor: Qt.vector3d(0.0, 0.3, 0.6) 
                }
            }
            // 右侧高塔发光线
            Model {
                position: Qt.vector3d(400, 290, 105)
                scale: Qt.vector3d(2, 0.1, 0.1)
                source: "#Cube"
                materials: PrincipledMaterial { emissiveFactor: Qt.vector3d(0, 2, 2) }
            }
            
            // 中间大坝挡水墙
            Model {
                position: Qt.vector3d(0, 100, 0)
                scale: Qt.vector3d(6, 2, 1.5)
                source: "#Cube"
                materials: PrincipledMaterial { 
                    baseColor: "#004477"; 
                    opacity: 0.85;
                    emissiveFactor: Qt.vector3d(0.0, 0.2, 0.5)
                }
            }
            
            // 坝顶道路
            Model {
                position: Qt.vector3d(0, 205, 0)
                scale: Qt.vector3d(6, 0.1, 1.6)
                source: "#Cube"
                materials: PrincipledMaterial { baseColor: "#00ffff"; emissiveFactor: Qt.vector3d(0.0, 0.8, 1.0); opacity: 0.5 }
            }

            // 坝体表面的科幻发光线条
            Model {
                position: Qt.vector3d(0, 100, 76)
                scale: Qt.vector3d(5.8, 0.05, 0.05)
                source: "#Cube"
                materials: PrincipledMaterial { baseColor: "transparent"; emissiveFactor: Qt.vector3d(0.0, 2.5, 2.5) }
            }
            Model {
                position: Qt.vector3d(0, 150, 76)
                scale: Qt.vector3d(5.8, 0.05, 0.05)
                source: "#Cube"
                materials: PrincipledMaterial { baseColor: "transparent"; emissiveFactor: Qt.vector3d(0.0, 2.5, 2.5) }
            }

            // 泄洪口 1, 2, 3
            Repeater3D {
                model: [-150, 0, 150]
                Node {
                    position: Qt.vector3d(modelData, 50, 80)
                    Model {
                        scale: Qt.vector3d(0.8, 1.0, 0.5)
                        source: "#Cube"
                        materials: PrincipledMaterial { baseColor: "#002244"; opacity: 0.9 }
                    }
                    // 模拟倾泻而下的水流 (科技感数据流)
                    Model {
                        position: Qt.vector3d(0, -30, 100)
                        scale: Qt.vector3d(0.6, 0.05, 2.5)
                        eulerRotation.x: 30
                        source: "#Cube"
                        materials: PrincipledMaterial {
                            baseColor: "#00ffff"
                            emissiveFactor: Qt.vector3d(0.0, 2.0, 3.0)
                            opacity: 0.8
                        }
                    }
                }
            }
        }

        // --- 2. 厂房区 (大坝前方) ---
        Node {
            position: Qt.vector3d(250, 0, 100)
            
            // 厂房主楼
            Model {
                position: Qt.vector3d(0, 60, 0)
                scale: Qt.vector3d(2.5, 1.2, 1.5)
                source: "#Cube"
                materials: PrincipledMaterial { 
                    baseColor: "#005588"; 
                    opacity: 0.85;
                    emissiveFactor: Qt.vector3d(0.0, 0.2, 0.5)
                }
            }
            // 厂房屋顶
            Model {
                position: Qt.vector3d(0, 125, 0)
                scale: Qt.vector3d(2.6, 0.1, 1.6)
                source: "#Cube"
                materials: PrincipledMaterial { baseColor: "#0088cc"; opacity: 0.6 }
            }
            // 厂房屋顶边缘发光
            Model {
                position: Qt.vector3d(0, 125, 80)
                scale: Qt.vector3d(2.6, 0.12, 0.1)
                source: "#Cube"
                materials: PrincipledMaterial { emissiveFactor: Qt.vector3d(0, 1.5, 2.0) }
            }

            // 厂房周围的储水罐 1
            Model {
                position: Qt.vector3d(-180, 50, 0)
                scale: Qt.vector3d(1.0, 1.0, 1.0)
                source: "#Cylinder"
                materials: PrincipledMaterial { 
                    baseColor: "#006699"; 
                    opacity: 0.85;
                    emissiveFactor: Qt.vector3d(0.0, 0.3, 0.6)
                }
            }
            // 储水罐发光环
            Model {
                position: Qt.vector3d(-180, 80, 0)
                scale: Qt.vector3d(1.05, 0.05, 1.05)
                source: "#Cylinder"
                materials: PrincipledMaterial { emissiveFactor: Qt.vector3d(0, 2, 2) }
            }

            // 储水罐 2
            Model {
                position: Qt.vector3d(-180, 50, 120)
                scale: Qt.vector3d(1.0, 1.0, 1.0)
                source: "#Cylinder"
                materials: PrincipledMaterial { 
                    baseColor: "#006699"; 
                    opacity: 0.85;
                    emissiveFactor: Qt.vector3d(0.0, 0.3, 0.6)
                }
            }
            // 储水罐2发光环
            Model {
                position: Qt.vector3d(-180, 80, 120)
                scale: Qt.vector3d(1.05, 0.05, 1.05)
                source: "#Cylinder"
                materials: PrincipledMaterial { emissiveFactor: Qt.vector3d(0, 2, 2) }
            }

            // 连接管道
            Model {
                position: Qt.vector3d(-180, 20, 60)
                scale: Qt.vector3d(0.1, 1.5, 0.1)
                eulerRotation.x: 90
                source: "#Cylinder"
                materials: PrincipledMaterial { baseColor: "#00ffff"; emissiveFactor: Qt.vector3d(0, 0.5, 1); opacity: 0.6 }
            }
            // 管道内流动的发光效果
            Model {
                position: Qt.vector3d(-180, 20, 60)
                scale: Qt.vector3d(0.12, 0.5, 0.12)
                eulerRotation.x: 90
                source: "#Cylinder"
                materials: PrincipledMaterial { emissiveFactor: Qt.vector3d(0, 2.0, 3.0) }
                SequentialAnimation on y {
                    loops: Animation.Infinite
                    NumberAnimation { from: 15; to: 25; duration: 1000 }
                    NumberAnimation { from: 25; to: 15; duration: 1000 }
                }
            }
        }

        // --- 3. 水面区 ---
        Node {
            position: Qt.vector3d(-150, 0, 150)
            
            // 下游水池
            Model {
                position: Qt.vector3d(0, 5, 0)
                scale: Qt.vector3d(8, 0.1, 6)
                source: "#Cube"
                materials: PrincipledMaterial {
                    baseColor: "#003366"
                    opacity: 0.7
                    emissiveFactor: Qt.vector3d(0.0, 0.1, 0.3)
                }
            }
            
            // 水池表面发光网格或边缘
            Model {
                position: Qt.vector3d(0, 6, 0)
                scale: Qt.vector3d(7.8, 0.05, 5.8)
                source: "#Cube"
                materials: PrincipledMaterial {
                    baseColor: "transparent"
                    emissiveFactor: Qt.vector3d(0, 1.0, 2.0)
                    opacity: 0.4
                }
            }

            // 水池围墙
            Model {
                position: Qt.vector3d(0, 10, 300)
                scale: Qt.vector3d(8, 0.2, 0.1)
                source: "#Cube"
                materials: PrincipledMaterial { baseColor: "#0088cc"; opacity: 0.8; emissiveFactor: Qt.vector3d(0, 0.2, 0.5) }
            }
            Model {
                position: Qt.vector3d(-400, 10, 0)
                scale: Qt.vector3d(0.1, 0.2, 6)
                source: "#Cube"
                materials: PrincipledMaterial { baseColor: "#0088cc"; opacity: 0.8; emissiveFactor: Qt.vector3d(0, 0.2, 0.5) }
            }
        }

        // --- 4. 动态元素：无人机 ---
        Node {
            position: Qt.vector3d(100, 300, 0)
            visible: systemData.droneRunning
            
            SequentialAnimation on x {
                running: systemData.droneRunning; loops: Animation.Infinite
                NumberAnimation { to: -300; duration: 5000; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 100; duration: 5000; easing.type: Easing.InOutQuad }
            }
            SequentialAnimation on z {
                running: systemData.droneRunning; loops: Animation.Infinite
                NumberAnimation { to: 200; duration: 3000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0; duration: 3000; easing.type: Easing.InOutSine }
            }
            
            // 机身
            Model {
                scale: Qt.vector3d(0.4, 0.1, 0.4)
                source: "#Cylinder"
                materials: PrincipledMaterial { baseColor: "#00ffff"; emissiveFactor: Qt.vector3d(0, 1, 2) }
            }
            // 发光点
            Model {
                position: Qt.vector3d(0, 5, 0)
                scale: Qt.vector3d(0.1, 0.1, 0.1)
                source: "#Sphere"
                materials: PrincipledMaterial { baseColor: "#ffffff"; emissiveFactor: Qt.vector3d(0, 5, 5) }
            }
            // 扫描光锥
            Model {
                position: Qt.vector3d(0, -100, 0)
                scale: Qt.vector3d(0.6, 2.0, 0.6)
                source: "#Cone"
                materials: PrincipledMaterial {
                    baseColor: "#00ffff"
                    emissiveFactor: Qt.vector3d(0, 1, 1)
                    opacity: 0.3
                }
                SequentialAnimation on eulerRotation.z {
                    loops: Animation.Infinite
                    NumberAnimation { from: -20; to: 20; duration: 800 }
                    NumberAnimation { from: 20; to: -20; duration: 800 }
                }
            }
        }

        // --- 5. 动态元素：无人船 ---
        Node {
            position: Qt.vector3d(-250, 15, 100)
            visible: systemData.shipRunning
            
            SequentialAnimation on z {
                running: systemData.shipRunning; loops: Animation.Infinite
                NumberAnimation { to: 250; duration: 8000; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 100; duration: 8000; easing.type: Easing.InOutQuad }
            }
            
            // 船体
            Model {
                scale: Qt.vector3d(0.4, 0.2, 0.6)
                source: "#Cube"
                materials: PrincipledMaterial { baseColor: "#006699"; opacity: 0.9; emissiveFactor: Qt.vector3d(0, 0.2, 0.5) }
            }
            // 船体边缘发光
            Model {
                position: Qt.vector3d(0, 10, 0)
                scale: Qt.vector3d(0.42, 0.05, 0.62)
                source: "#Cube"
                materials: PrincipledMaterial { emissiveFactor: Qt.vector3d(0, 2, 3) }
            }
            // 船舱
            Model {
                position: Qt.vector3d(0, 15, -10)
                scale: Qt.vector3d(0.2, 0.15, 0.2)
                source: "#Cube"
                materials: PrincipledMaterial { baseColor: "#00ffff"; emissiveFactor: Qt.vector3d(0, 1, 1) }
            }
            // 雷达波纹
            Model {
                position: Qt.vector3d(0, -5, 0)
                source: "#Cylinder"
                materials: PrincipledMaterial {
                    baseColor: "transparent"
                    emissiveFactor: Qt.vector3d(0, 2.0, 3.0)
                    opacity: 0.6
                }
                PropertyAnimation on scale { from: Qt.vector3d(0.5, 0.01, 0.5); to: Qt.vector3d(3, 0.01, 3); duration: 1500; loops: Animation.Infinite }
                NumberAnimation on opacity { from: 0.8; to: 0.0; duration: 1500; loops: Animation.Infinite }
            }
        }
    }
}
