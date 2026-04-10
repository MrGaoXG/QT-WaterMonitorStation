# 如何利用ollama.cpp在树莓派上部署大模型并运行?


啊，我完全理解你的困惑了！这是一个非常常见的误区：**你不需要手动去下载任何 `.cpp` (C++ 源代码) 文件！**

`llama.cpp` 虽然名字里带有 `.cpp`，但我们在 Python 里使用时，是通过一个叫 `llama-cpp-python` 的 Python 库来调用它的。

当你运行 `pip install llama-cpp-python` 这条命令时，Python 的包管理器会自动在后台把 C++ 的源码下载下来，并且自动调用树莓派的编译器把它编译成你的 Python 可以直接 `import` 的库。**一切都是自动完成的！**

我已经为你写好了一个专用的独立测试脚本 [test_llamacpp_standalone.py](file:///c:/Qt/project/WaterMonitorStation/test_llamacpp_standalone.py)，你现在需要做的，就是**按照顺序在树莓派的终端里复制并执行下面这 4 段命令**：

### 第一步：释放内存并安装编译环境
（树莓派内存小，先把 Ollama 关掉腾出内存，并安装编译器）
```bash
sudo systemctl stop ollama
sudo apt update
sudo apt install -y build-essential cmake python3-dev
```

### 第二步：让 Python 自动下载并编译 llama.cpp
（这一步是核心，加上了 `CMAKE_ARGS` 是为了开启树莓派的 ARM CPU 硬件加速。**注意：编译过程可能需要 5 到 15 分钟，请耐心等待直到出现 Successfully installed**）
```bash
CMAKE_ARGS="-DGGML_CPU_ARM_ARCH=armv8" pip3 install llama-cpp-python
```

### 第三步：下载 GGUF 格式的模型文件
（我们在项目目录下建个 `models` 文件夹，然后用 wget 从国内镜像站极速下载模型权重，大概 350MB）
```bash
mkdir -p ~/Raspberry_Pi_airground/models
cd ~/Raspberry_Pi_airground/models
wget https://modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/master/qwen2.5-0.5b-instruct-q4_k_m.gguf
```

### 第四步：运行我刚刚为你写好的新脚本
把你 Windows 电脑上刚刚生成的 `test_llamacpp_standalone.py` 文件传到树莓派的 `~/Raspberry_Pi_airground/` 目录下，然后运行它：
```bash
cd ~/Raspberry_Pi_airground/
python3 test_llamacpp_standalone.py
```

---
**为什么这种方式会比 Ollama 快得多？**
1. **0 网络开销**：Ollama 是在后台跑一个服务器，你的 Python 脚本要通过 HTTP 协议把问题发过去，再等它传回来。而新脚本是**直接把模型读到了 Python 自己的内存里**（见新脚本的第 39 行），在同一个进程里计算，瞬间出结果。
2. **CPU 满血输出**：我们在新脚本里指定了 `n_threads=4`，让树莓派的 4 个核心全部参与计算，并且去掉了 Ollama 那些多余的后台服务负担。

你现在可以立刻在树莓派上执行前三步！执行过程中如果遇到任何报错（比如网络断开或编译报错），随时把终端的红字发给我看！