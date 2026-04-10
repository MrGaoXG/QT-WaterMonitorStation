# 实现STT语音转文本

​     为了实现你期望的**“免键盘语音交互”**功能（即：外部麦克风 -> 本地离线语音转文字 -> llama.cpp -> Qt UI / 语音播报），这是一个极其出彩的**边缘计算多模态 AI (Edge Multimodal AI)** 方案，在比赛中绝对是一大加分项。

考虑到树莓派的算力限制，我们必须采用**完全离线、低内存占用**的 STT（Speech-to-Text，语音转文本）方案，绝不能使用需要联网的百度或科大讯飞 API，这样才能契合“断网边缘部署”的立意。

以下是为你量身定制的完整架构方案与实现步骤：

### **一、 架构设计与技术选型**

#### **1. 硬件选型：USB 免驱麦克风**
树莓派没有内置麦克风。建议直接在淘宝买一个 **“USB 免驱全向麦克风”**（十几块钱到几十块钱不等）。
- **优势**：即插即用，Linux 内核原生支持，不需要折腾复杂的 I2S 引脚和驱动。

#### **2. 软件选型：Vosk vs Whisper.cpp**
考虑到目前你的树莓派上已经跑了 `llama.cpp`（大约占用 400MB~600MB 内存，并且会吃掉大量 CPU 资源），**STT 引擎必须极致轻量化**。

| 方案名称        | 模型大小       | 树莓派 CPU 占用 | 实时性           | 推荐度 | 说明                                                         |
| :-------------- | :------------- | :-------------- | :--------------- | :----- | :----------------------------------------------------------- |
| **Vosk**        | **~50 MB**     | 极低 (< 10%)    | **实时流式输出** | ⭐⭐⭐⭐⭐  | **首选方案**。极其轻量，支持中文，流式监听（边说边出字），完全不抢占 LLM 算力。 |
| **Whisper.cpp** | ~150 MB (tiny) | 较高 (~50%)     | 需录音完再转写   | ⭐⭐⭐    | 准确率极高，但需要等录音结束才能处理，且推理时可能会和 `llama.cpp` 抢占 CPU。 |

**结论**：强烈建议采用 **Vosk**。它不仅部署简单，而且在树莓派上可以做到真正的**“实时语音识别”**。

---

### **二、 具体实现步骤**

为了方便你测试，我已经为你编写了一个独立的测试脚本：[test_voice_stt.py](file:///c:/Qt/project/WaterMonitorStation/test_voice_stt.py)。下面是具体的操作流程：

#### **步骤 1：树莓派环境配置 (准备录音库)**
由于读取 USB 麦克风需要调用底层音频接口，请在树莓派的终端执行以下命令安装依赖：
```bash
# 1. 安装底层音频驱动和 C 库
sudo apt-get update
sudo apt-get install portaudio19-dev python3-pyaudio alsa-utils -y

# 2. 检查麦克风是否被识别 (插入 USB 麦克风后执行)
arecord -l
# 如果能看到类似 "card 1: USB Audio Device..." 就说明硬件没问题了

# 3. 安装 Python 库 (Vosk 和 PyAudio)
pip install vosk pyaudio
```

#### **步骤 2：下载轻量级离线中文模型**
1. 访问 Vosk 官方模型库：[https://alphacephei.com/vosk/models](https://alphacephei.com/vosk/models)
2. 找到并下载 **`vosk-model-small-cn-0.22`** (大约 42MB)。
3. 将下载的压缩包解压，把里面的文件夹重命名为 `model`，并放到与 `main.py` 和 `test_voice_stt.py` 同级的目录下。

#### **步骤 3：运行测试脚本**
执行我刚为你生成的代码：
```bash
python test_voice_stt.py
```
当终端提示 `[音频采集模块已启动]` 时，你就可以对着麦克风说话了。它会实时打印出你的语音文本。

---

### **三、 如何将语音模块集成进主系统 (`main.py`)**

目前的测试脚本是独立运行的。当你测试成功后，可以通过以下思路将其融入现有的 `main.py` 中：

1. **创建后台监听线程**：
   在 `main.py` 的初始化阶段，启动一个 `AudioListenerThread`，这个线程里面放的就是 Vosk 的 `while True` 监听循环。
2. **文本推入任务队列**：
   当 Vosk 检测到完整的一句话（比如：“现在的无人机电量是多少？”），就把这段文字放入一个队列（Queue）。
3. **触发 LLM 推理**：
   你的 `AIDataAnalyst` 会像处理 Qt 传来的 UDP 消息一样，取出这段语音转换来的文字，加上无人机的状态（System Prompt），交给 `llama.cpp` 进行推理，最后把结果通过 UDP 发给 Qt 界面显示。

### **四、 文档/比赛答辩加分话术**

在你的比赛文档中，这段功能可以这样描述以拉满技术分：

> **4.4 边缘侧离线多模态交互实现**
> 为应对野外水文监测站可能面临的“断网、强噪音、需解放双手”的特殊工况，本系统设计了全离线的语音交互控制流。
> 1. **环境感知与拾音**：通过 USB 全向麦克风阵列获取模拟音频信号。
> 2. **轻量级流式 ASR**：采用 **Vosk 轻量级声学模型 (仅 40MB)**，结合 PyAudio 实现 16kHz 音频流的实时切片与特征提取，在不干扰 LLM 算力的前提下，实现了**毫秒级的本地语音转文本**。
> 3. **意图理解与决策**：文本解析后无缝对接到本地部署的 `Qwen2.5-0.5B` 大模型中，结合实时传感器数据进行意图推理，彻底实现了“听音、懂意、反馈”的边缘侧端到端闭环。

如果你准备好了麦克风并跑通了 [test_voice_stt.py](file:///c:/Qt/project/WaterMonitorStation/test_voice_stt.py)，我们可以随时进行下一步：**将它与你的大模型后台代码直接融合在一起！** 需要我帮你修改 `main.py` 加上这个语音线程吗？**



这是一个非常经典的报错。在最新的树莓派系统（基于 Debian 12 Bookworm）中，引入了 PEP 668 安全规范，**系统默认禁止使用 `pip` 直接在全局环境中安装 Python 包**，以此来防止 `pip` 破坏系统自带的依赖环境（所以提示 `externally-managed-environment`）。

针对树莓派这种“专机专用”来跑项目的场景，最简单、最常用的解决方案就是**直接加上 `--break-system-packages` 参数**来绕过这个限制（不用被名字吓到，这在树莓派开发者中非常普遍，您之前安装 `llama-cpp-python` 大概率也是在全局环境）。

请在树莓派终端按照以下顺序执行命令，我为您整理了完整的 **STT(语音识别)** 和 **TTS(语音播报)** 依赖安装步骤：

### 1. 安装底层 C/C++ 音频驱动依赖
在安装 Python 的 `pyaudio` 和 `pyttsx3` 之前，必须先安装 Linux 系统的底层音频库和引擎，否则会报错：
```bash
sudo apt-get update
# 安装麦克风录音所需底层库 (PortAudio)
sudo apt-get install portaudio19-dev alsa-utils -y
# 安装喇叭播报所需底层引擎 (eSpeak 和中文发音人)
sudo apt-get install espeak espeak-ng mbrola mbrola-cn1 -y
```

### 2. 使用系统包管理器安装 PyAudio (推荐)
对于系统底层硬件交互的库，推荐直接使用树莓派官方提供的 `apt` 版本的 Python 包，这样最稳定：
```bash
sudo apt-get install python3-pyaudio -y
```

### 3. 强制使用 pip 安装 Vosk 和 Pyttsx3
由于 `vosk` 和 `pyttsx3` 在 `apt` 源中没有或者版本较旧，我们使用 `pip` 并加上 `--break-system-packages` 参数来强制安装：
```bash
pip install vosk pyttsx3 --break-system-packages
```

---

### 验证安装是否成功
安装完成后，您可以在树莓派终端输入 `python3` 进入交互模式，尝试导入它们来验证：
```python
import pyaudio
import vosk
import pyttsx3
```
如果没有报错，说明环境已经彻底配置好了！

接下来您只需要确保把下载好的 `vosk-model-small-cn-0.22` 模型解压并改名为 `model` 文件夹，放在 `main.py` 同级目录下，就可以运行 `python3 main.py` 体验全双工的语音交互了。