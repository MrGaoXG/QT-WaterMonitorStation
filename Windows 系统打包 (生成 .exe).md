这是为您整理的《水质监测地面站项目技术打包与部署手册》，涵盖了 Windows 和 Linux (树莓派) 的打包流程，以及一份完美的开机自启动方案。

### 一、 Windows 系统打包 (生成 .exe)
在 Windows 上，我们使用 Qt 自带的 windeployqt 工具来自动补齐依赖库。

1. 编译 Release 版本 ：
   在 Qt Creator 左下角点击“小电脑”图标，选择 Release 模式，然后点击“锤子”图标编译。
2. 提取主程序 ：
   进入编译输出目录（通常名为 build-WaterMonitorStation-...-Release ），找到 release/WaterMonitorStation.exe 。
3. 准备打包文件夹 ：
   在任意位置新建文件夹（如 Deploy_Win ），将 WaterMonitorStation.exe 复制进去。
4. 执行自动补齐 ：
   - 打开 Qt 6.x (MinGW/MSVC) 命令提示符 （在 Windows 开始菜单中搜索）。
   - 输入以下命令：
     ```
     cd /d "您的打包文件夹路径"
     windeployqt --qmldir 
     "C:\Qt\project\WaterMonitorStat
     ion" WaterMonitorStation.exe
     ```
5. 手动补齐资源 ：
   如果程序使用了外部图片或字体文件（如 background.png , DS-DIGI-1.ttf ），请确保它们也在 .exe 同级目录下。
### 二、 Linux / 树莓派打包 (生成二进制)
Linux 下最简单的方式是直接在目标机器上编译，然后提取二进制文件。

1. 源码编译 ：
   ```
   cd ~/WaterMonitorStation/
   QT-WaterMonitorStation
   qmake6 WaterMonitorStation.pro
   make -j4
   ```
2. 获取执行文件 ：
   编译成功后，当前目录下的 WaterMonitorStation 即为可执行文件。
3. 依赖补齐 ：
   在树莓派上，由于我们已经安装了全局 Qt 库，直接拷贝这个文件到其他同配置的树莓派即可运行。如果需要彻底独立打包，可以使用 linuxdeployqt （针对 X11 环境）。
### 三、 树莓派开机自启动方案 (显示与 SSH 互不冲突)
为了实现“开机即显示监控”且“不占用 SSH”，我们采用 用户级桌面自启动 (Autostart) 配合 后台执行 的方式。
 1. 创建启动脚本
在项目目录下创建 run_station.sh ：

```
nano ~/WaterMonitorStation/
QT-WaterMonitorStation/run_station.
sh
```
写入以下内容（ 关键：指定 DISPLAY 并进入后台 ）：

```
#!/bin/bash
# 等待桌面环境和网络完全准备就绪
sleep 10

# 声明显示目标为本地 0 号物理屏幕
export DISPLAY=:0

# 进入项目目录
cd /home/mrgao/WaterMonitorStation/
QT-WaterMonitorStation

# 赋予串口权限 (防止因权限问题无法接收数
据)
sudo chmod 666 /dev/ttyUSB0 || true
sudo chmod 666 /dev/ttyAMA0 || true

# 启动程序并完全脱离终端控制，日志丢弃
nohup ./WaterMonitorStation > /dev/
null 2>&1 &

echo "地面站已在本地屏幕后台启动。"
``` 2. 赋予脚本执行权限
```
chmod +x ~/WaterMonitorStation/
QT-WaterMonitorStation/run_station.
sh
``` 3. 配置桌面自动加载
树莓派桌面启动后会自动执行 ~/.config/autostart 目录下的 .desktop 文件。

```
mkdir -p ~/.config/autostart
nano ~/.config/autostart/
water_monitor.desktop
```
写入以下内容：

```
[Desktop Entry]
Type=Application
Name=WaterMonitor
Comment=Start Water Monitor Station 
on local screen
# 执行刚才创建的脚本
Exec=/home/mrgao/
WaterMonitorStation/
QT-WaterMonitorStation/run_station.
sh
Terminal=false
# 仅在图形界面加载后运行
X-GNOME-Autostart-enabled=true
```
### 四、 远程管理技巧 (SSH 友好型)
采用上述方案后，您的显示与 SSH 将完全互不干扰：

- 开机后 ：树莓派本地 7 寸屏会自动全屏运行监控系统。
- SSH 连接 ：您可以随时通过 MobaXterm 等工具 SSH 登录，不会看到程序运行。
- SSH 查看程序是否在跑 ：
```
```
  ps -ef | grep WaterMonitorStation
```

  ```
- SSH 强制关闭程序 (例如需要更新代码) ：
  ```
  pkill WaterMonitorStation
  ```
- SSH 手动触发本地显示更新 ：
  ```
  DISPLAY=:0 ./WaterMonitorStation /dev/null 2>&1 &
  > ```
  > 总结 ：通过 DISPLAY=:0 结合 nohup ... & ，程序将直接渲染到 HDMI 物理屏幕，且在 SSH 中执行命令后会立即返回命令行，不会产生阻塞。