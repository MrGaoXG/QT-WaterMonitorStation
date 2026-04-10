# 实现TTS文本转语音通过功放模块输出


为了实现**“将 AI 的文字回答，通过功放模块用喇叭播放出来”**，也就是 **TTS（Text-to-Speech，文本转语音）**功能，我们需要同样坚持“边缘侧离线计算”的原则。

考虑到树莓派的算力和内存已经被 `llama.cpp` 占据大半，TTS 引擎必须极度省资源，不能有明显的延迟。

---

### **一、 技术选型与硬件方案**

#### **1. 硬件连接 (喇叭/功放)**
树莓派输出音频有三种常见方式，针对你的“功放模块”：
- **方案 A (最简单)：树莓派板载 3.5mm 音频接口**
  直接用 3.5mm 音频线将树莓派连接到你的功放模块（Audio Amplifier）的输入端，功放再接喇叭。
- **方案 B (音质更好)：USB 声卡**
  买一个十几块钱的 USB 免驱声卡插在树莓派上，然后将功放模块接在 USB 声卡的绿色输出孔上。
- **方案 C：蓝牙音箱**
  树莓派自带蓝牙，直接配对连接一个带功放的蓝牙小音箱。

#### **2. 软件选型：pyttsx3 (封装了 espeak)**
我为你选择了 **`pyttsx3`** 这个库。
- **优势**：它完全离线工作，在 Linux（树莓派）上直接调用底层的 `espeak` 引擎。**几乎 0 内存占用，毫秒级响应**。它非常适合用来播报系统警告（比如“无人机电量低，请返航”）。
- **缺点**：合成的声音比较有“机械感”（类似早期机器人的声音），没有联网的百度/微软 TTS 那么拟人。但对于工业/比赛场景，这种“赛博朋克”的机械音反而是加分项，显得非常硬核和专业。

---

### **二、 具体实现步骤**

我已经为你写好了独立的 TTS 测试脚本：[test_voice_tts.py](file:///c:/Qt/project/WaterMonitorStation/test_voice_tts.py)。下面是配置和测试流程：

#### **步骤 1：在树莓派上安装底层音频引擎与中文语音包**
树莓派需要安装 `espeak` 和高质量的中文发音人包（`mbrola`），在树莓派终端执行：
```bash
sudo apt-get update
# 安装 espeak 引擎以及 python3 绑定
sudo apt-get install espeak espeak-ng python3-espeak -y
# 安装 mbrola 中文高质量发音人 (比默认的 espeak 声音好听一点)
sudo apt-get install mbrola mbrola-cn1 -y
```

#### **步骤 2：安装 Python 依赖库**
```bash
pip install pyttsx3
```

#### **步骤 3：配置树莓派的音频输出通道 (如果接 3.5mm 耳机孔)**
有时候树莓派默认从 HDMI 输出声音，我们需要强制它从 3.5mm 耳机孔输出：
在终端输入 `sudo raspi-config`
-> 选择 `1 System Options` -> 选择 `S2 Audio` -> 选择 `Headphones` (3.5mm jack) -> 退出保存。

#### **步骤 4：运行测试脚本**
将喇叭接好并通电，在终端运行我为你生成的测试代码：
```bash
python test_voice_tts.py
```
（你可以听到喇叭播报：“你好，我是空地海智能监测站的 AI 助手。无人机当前电量为百分之十八，请注意及时返航充电。”）
如果你想测试其他句子，可以加上参数：
```bash
python test_voice_tts.py --text "发现水质异常，PH值过低"
```

---

### **三、 如何将它完美集成到 `main.py` 的架构中**

回忆一下刚才我们分析的 `main.py` 里的 `AIDataAnalyst` 模块：

```python
    def _run_llamacpp_query(self, query_text):
        # ... 前面是 llama.cpp 的推理逻辑 ...
        
        # 得到回答文本
        ans = response['choices'][0]['message']['content'].strip()
        
        # 1. 通过 UDP 发给 Qt 界面显示文字
        self._send_ai_reply(ans)
        
        # 2. 【新增】在这里调用 TTS 引擎将 ans 朗读出来！
        # threading.Thread(target=self._play_tts_audio, args=(ans,), daemon=True).start()
```

**集成思路非常清晰：**
1. 在 `AIDataAnalyst` 类初始化时，也初始化 `pyttsx3.init()`。
2. 当 `llama.cpp` 生成完一段回答 `ans` 后，除了把文本发给 Qt，同时新开一个小线程（防止阻塞 UDP 通信），调用 `engine.say(ans)` 和 `engine.runAndWait()` 让喇叭把这句话喊出来。

**这样，整个“全双工离线语音交互链路”就彻底打通了：**
用户对麦克风说话 (Vosk STT) ➔ 文本进入 llama.cpp 结合传感器数据推理 ➔ 得到回答文本发给 Qt 并触发喇叭朗读 (pyttsx3 TTS)。

你可以先拿你的树莓派和喇叭跑一下 [test_voice_tts.py](file:///c:/Qt/project/WaterMonitorStation/test_voice_tts.py) 听听声音效果。如果满意，我们就可以开始修改 `main.py` 把麦克风（STT）和喇叭（TTS）全部揉进去了！



          
**是的，完全可以指定声线！**

`pyttsx3` 是通过调用操作系统底层的语音引擎来发声的（在 Windows 上是 SAPI5，在 macOS 上是 NSSpeechSynthesizer，在 Linux/树莓派 上是 espeak）。你系统里安装了哪些发音人（Voices），它就能切换成哪种声音。

我已经为你更新了 [test_voice_tts.py](file:///c:/Qt/project/WaterMonitorStation/test_voice_tts.py) 脚本，增加了**查看和切换声线**的功能。

### **如何查看和切换声线：**

#### **第一步：查看系统有哪些声音可用**
在终端运行以下命令：
```bash
python test_voice_tts.py --list
```
这会打印出类似这样的列表：
```text
[0] ID: HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens\TTS_MS_ZH-CN_HUIHUI_11.0
    Name: Microsoft Huihui Desktop - Chinese (Simplified)
    Languages: []
------------------------------
[1] ID: HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens\TTS_MS_EN-US_ZIRA_11.0
    Name: Microsoft Zira Desktop - English (United States)
    Languages: []
------------------------------
```
> **注意**：如果在树莓派上，你会看到很多以 `espeak` 或者 `mbrola` 开头的发音人，比如 `zh`（普通中文）、`zh-yue`（粤语口音）等。

#### **第二步：指定某个声线来朗读**
记下你想要的中文声音的序号（比如上面 `Huihui` 的序号是 `0`），然后通过 `--voice` 参数指定它：
```bash
python test_voice_tts.py --voice 0 --text "现在使用的是指定的零号声线进行播报。"
```

### **给你的建议（关于树莓派的声线）**

在树莓派默认安装的 `espeak` 库中，中文声音可能会显得比较“生硬”。如果你希望在比赛中展示出更好的音质效果，可以安装 **mbrola** 语音库（它是一种拼接合成技术，比原生的 espeak 好听一点）。

**在树莓派上的操作：**
1. 安装更好的中文语音包：
   ```bash
   sudo apt-get install mbrola mbrola-cn1
   ```
2. 运行 `python test_voice_tts.py --list`，找到里面名字带有 `cn1` 或者 `mbrola-cn1` 的序号。
3. 记下这个序号，以后在 `main.py` 里初始化 `pyttsx3` 的时候，就可以用 `engine.setProperty('voice', voices[序号].id)` 直接固定这个“高阶声线”了！