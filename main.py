#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
空地海地面站智能数显系统 - 主程序
负责协调各个模块,实现定时采集、上传和可视化显示功能
"""

import time
import signal
import sys
import logging
import webbrowser
import threading
import os
import subprocess
import socket
import serial
import json
import os
import asyncio
import edge_tts
import queue

# --- 新增：语音模块依赖检查 ---
HAS_PYTTSX3 = True  # 为了保持原有逻辑的兼容性标志，实际已切换为 edge-tts

try:
    import pyaudio
    from vosk import Model, KaldiRecognizer
    HAS_VOSK = True
except ImportError:
    HAS_VOSK = False
# ------------------------------

try:
    from llama_cpp import Llama
    HAS_LLAMA_CPP = True
except ImportError:
    HAS_LLAMA_CPP = False
    print("⚠️  未找到 llama-cpp-python 库，本地 AI 分析功能将不可用")
    print("请运行: pip3 install llama-cpp-python")

# 导入自定义模块
import config
from sensor_reader import SensorReader
from http_uploader import HTTPUploader
from data_logger import DataLogger

# 导入Dashboard
try:
    from dashboard.app import Dashboard
    HAS_DASHBOARD = True
except ImportError as e:
    HAS_DASHBOARD = False
    print(f"⚠️  Dashboard模块导入失败: {str(e)}")
    print("⚠️  可视化功能将不可用，但数据采集和上传仍可正常工作")

# 导入显示模块
try:
    import pygame
    HAS_PYGAME = True
except ImportError:
    HAS_PYGAME = False

try:
    from PyQt5.QtWidgets import QApplication
    HAS_PYQT = True
except ImportError:
    HAS_PYQT = False

# 添加Tkinter导入检测 - 确保这部分存在
try:
    import tkinter
    HAS_TKINTER = True
except ImportError:
    HAS_TKINTER = False

class SerialUDPBridge:
    """串口与UDP双向桥接服务"""
    def __init__(self, serial_port='/dev/ttyS0', baud_rate=9600, udp_send_port=8080, udp_recv_port=8081):
        self.serial_port = serial_port
        self.baud_rate = baud_rate
        self.udp_send_port = udp_send_port
        self.udp_recv_port = udp_recv_port
        self.running = False
        self.ser = None
        
        # 初始化发送 UDP socket (用于广播收到的串口数据给 Qt)
        self.send_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.send_sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        
        # 初始化接收 UDP socket (用于接收 Qt 发送的起飞/降落/报警指令)
        self.recv_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            self.recv_sock.bind(('0.0.0.0', self.udp_recv_port))
            self.recv_sock.settimeout(0.5)
        except Exception as e:
            print(f"UDP接收端口 {self.udp_recv_port} 绑定失败: {e}")
            
        try:
            # 尝试打开硬件串口
            self.ser = serial.Serial(self.serial_port, self.baud_rate, timeout=0.5)
        except Exception as e:
            print(f"串口 {self.serial_port} 打开失败: {e}")
            
    def start(self):
        if not self.ser:
            return
            
        self.running = True
        
        # 启动读串口并广播的线程
        self.read_thread = threading.Thread(target=self._serial_to_udp_loop, daemon=True)
        self.read_thread.start()
        
        # 启动收UDP并写串口的线程
        self.write_thread = threading.Thread(target=self._udp_to_serial_loop, daemon=True)
        self.write_thread.start()
        
        print(f"✓ 串口<->UDP桥接已启动: 串口({self.serial_port}) <-> UDP广播({self.udp_send_port}) / 监听({self.udp_recv_port})")
        
    def _serial_to_udp_loop(self):
        """读取串口数据 -> 广播到UDP(8080)"""
        while self.running:
            try:
                if self.ser.in_waiting:
                    data = self.ser.readline()
                    if data:
                        # 打印从串口收到的数据作为调试信息
                        print(f"[串口->UDP] 收到串口数据: {data.strip().decode('utf-8', errors='ignore')}")
                        
                        # 改为 255.255.255.255 真正的广播地址，确保 Qt 和 Python 的 8080 端口都能收到
                        self.send_sock.sendto(data, ('255.255.255.255', self.udp_send_port))
            except Exception as e:
                pass
            time.sleep(0.01)
                
    def _udp_to_serial_loop(self):
        """接收UDP指令(8081) -> 写入串口"""
        while self.running:
            try:
                data, addr = self.recv_sock.recvfrom(1024)
                if data and self.ser:
                    # 打印从UDP收到的数据作为调试信息
                    print(f"[UDP->串口] 收到来自 {addr} 的UDP指令: {data.strip().decode('utf-8', errors='ignore')}")
                    
                    self.ser.write(data)
            except socket.timeout:
                pass
            except Exception as e:
                pass
                
    def stop(self):
        self.running = False
        if self.ser:
            self.ser.close()
        self.send_sock.close()
        self.recv_sock.close()

class AIDataAnalyst:
    """本地大模型数据分析与聊天引擎"""
    def __init__(self, udp_listen_port=8080, udp_send_port=8080):
        self.udp_listen_port = udp_listen_port
        self.udp_send_port = udp_send_port
        self.latest_data = {}  # 存储最新的传感器快照
        self.running = False
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        
        # --- 新增 llama.cpp 初始化 ---
        self.llm = None
        if HAS_LLAMA_CPP:
            model_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models", "qwen2.5-0.5b-instruct-q4_k_m.gguf")
            if os.path.exists(model_path):
                print(f"⏳ [边缘 AI] 正在加载 GGUF 量化模型: {model_path}...")
                try:
                    self.llm = Llama(
                        model_path=model_path,
                        n_threads=4,      # 针对 ARM 多核优化
                        n_ctx=2048,       # 上下文窗口限制
                        verbose=False     # 关闭 C++ 底层冗余日志
                    )
                    print("✅ [边缘 AI] 本地模型加载成功！内存映射(mmap)完成。")
                except Exception as e:
                    print(f"❌ [边缘 AI] 模型加载失败: {e}")
            else:
                print(f"⚠️ [边缘 AI] 模型文件未找到: {model_path}")
                print("请在终端执行: mkdir -p models && cd models && wget https://modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/master/qwen2.5-0.5b-instruct-q4_k_m.gguf")
                
        # --- 新增：初始化 TTS 引擎 ---
        self.tts_engine = None
        if HAS_PYTTSX3:
            # 改用 edge-tts
            self.tts_engine = True  # 仅作标志位
            print("✅ [TTS] Edge-TTS 语音合成引擎已就绪 (需要联网)。")
                
        # --- 新增：初始化 STT (语音监听) ---
        self.stt_stream = None
        self.stt_recognizer = None
        self.pyaudio_instance = None
        if HAS_VOSK:
            model_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "model")
            if os.path.exists(model_path):
                print(f"⏳ [STT] 正在加载 Vosk 语音模型: {model_path}...")
                try:
                    self.stt_recognizer = KaldiRecognizer(Model(model_path), 16000)
                    self.pyaudio_instance = pyaudio.PyAudio()
                    self.stt_stream = self.pyaudio_instance.open(
                        format=pyaudio.paInt16,
                        channels=1,
                        rate=16000,
                        input=True,
                        frames_per_buffer=8000
                    )
                    print("✅ [STT] 麦克风音频流已成功打开，全双工语音交互准备就绪。")
                except Exception as e:
                    print(f"⚠️ [STT] 麦克风打开失败: {e} (请检查硬件连接)")
                    self.stt_stream = None
            else:
                print(f"⚠️ [STT] 语音模型文件未找到: {model_path} (语音识别功能将被禁用)")

    def start(self):
        self.running = True
        # 启动监听线程，实时更新 AI 的“记忆”
        self.listen_thread = threading.Thread(target=self._data_listener, daemon=True)
        self.listen_thread.start()
        
        # 启动指令监听线程 (监听来自 Qt 的 AI 提问)
        self.cmd_thread = threading.Thread(target=self._command_listener, daemon=True)
        self.cmd_thread.start()
        
        # --- 新增：启动麦克风语音监听线程 ---
        if self.stt_stream and self.stt_recognizer:
            self.stt_thread = threading.Thread(target=self._stt_listener, daemon=True)
            self.stt_thread.start()
            
        print(f"✓ AI 数据分析引擎已启动: 监听端口({self.udp_listen_port})")

    def _stt_listener(self):
        """后台持续监听麦克风语音输入"""
        print("🎤 [STT] 开始持续监听语音输入...")
        while self.running:
            try:
                # 每次读取 4000 帧音频数据，不抛出溢出异常
                data = self.stt_stream.read(4000, exception_on_overflow=False)
                if len(data) == 0:
                    continue
                
                if self.stt_recognizer.AcceptWaveform(data):
                    result = json.loads(self.stt_recognizer.Result())
                    text = result.get("text", "").replace(" ", "")
                    if text:
                        print(f"\n🗣️ [语音输入] >> {text}")
                        # 直接复用原有的 process_ai_query 流程，把语音识别的文本喂给 LLM
                        self.process_ai_query(text)
            except Exception as e:
                # 简单忽略偶发的音频流读取异常，防止线程崩溃
                pass
        print("🎤 [STT] 语音监听线程已退出。")

    def _data_listener(self):
        """监听 8080 端口，获取 Qt 正在显示的数据广播"""
        # 注意：这里需要一个新的 socket 来监听广播数据
        data_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        data_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        data_sock.bind(('0.0.0.0', self.udp_listen_port))
        data_sock.settimeout(1.0)
        
        while self.running:
            try:
                data, addr = data_sock.recvfrom(4096)
                # 尝试解析收到的 JSON
                try:
                    raw_json = data.decode('utf-8', errors='ignore')
                    # 简单过滤，确保是传感器数据包
                    if "ph" in raw_json or "bat" in raw_json:
                        self.latest_data = json.loads(raw_json)
                except:
                    continue
            except socket.timeout:
                continue
            except Exception as e:
                print(f"AI数据监听异常: {e}")
        data_sock.close()

    def _command_listener(self):
        """监听来自 Qt 的 AI 提问指令 (假定使用特定前缀或单独端口，这里复用 8081 进行接收)"""
        # 为了不冲突，我们由 SensorSystem 统一分配
        pass

    def process_ai_query(self, query_text):
        """结合当前数据回答用户问题 (通过子线程执行防止阻塞)"""
        print(f"🤖 收到 AI 咨询: {query_text}")
        
        # 启动新线程处理大模型调用，避免阻塞主接收循环
        threading.Thread(target=self._run_llamacpp_query, args=(query_text,), daemon=True).start()

    def _run_llamacpp_query(self, query_text):
        """实际调用 llama.cpp 本地模型的方法"""
        if not self.llm:
            err_msg = "本地 AI 引擎未就绪 (模型未加载或依赖未安装)"
            print(f"❌ {err_msg}")
            self._send_ai_reply(err_msg)
            return
            
        system_context = f"""
        你是一个专业的水质监测站 AI 助手。
        当前系统实时数据快照: {json.dumps(self.latest_data, ensure_ascii=False)}
        
        任务指引:
        1. 结合上述实时数据回答用户问题。
        2. 如果数据中有明显异常（如PH值不在6-9之间，或无人机/船电量低于20%），请在回答中主动指出并给出警告。
        3. 语言风格: 专业、简洁、友好，使用中文回答。
        """
        
        try:
            print(f"⏳ [边缘 AI] 正在执行本地推理 (llama.cpp)...")
            start_time = time.time()
            
            response = self.llm.create_chat_completion(
                messages=[
                    {'role': 'system', 'content': system_context},
                    {'role': 'user', 'content': query_text},
                ],
                max_tokens=256,
                temperature=0.7
            )
            ans = response['choices'][0]['message']['content'].strip()
            cost_time = time.time() - start_time
            print(f"✅ [边缘 AI] 推理完成，耗时: {cost_time:.2f} 秒")
            
            # 由于是异步，这里直接通过 UDP 回传结果
            self._send_ai_reply(ans)
        except Exception as e:
            err_str = str(e)
            print(f"❌ [边缘 AI] 推理抛出异常: {err_str}")
            ans = f"AI 引擎调用失败: {err_str}"
            # 确保无论发生什么异常，都会尝试回传结果
            self._send_ai_reply(ans)

    def _send_ai_reply(self, answer):
        """将 AI 回复发回给 Qt (发送到 8080)，并通过 TTS 朗读"""
        print(f"📡 准备通过 UDP 回传结果至 8080...")
        print(f"📝 AI回答内容预览:\n{answer}\n{'-'*40}")
        try:
            resp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            resp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            # 恢复使用原有的中文前缀，兼容未重新编译的 Qt 旧版本
            reply = f"[AI诊断回复] {answer}"
            # 使用广播地址发送，防止被本 Python 脚本的 8080 监听端吞包
            bytes_sent = resp_sock.sendto(reply.encode('utf-8'), ('255.255.255.255', 8080))
            print(f"✅ 回传成功! (已发送 {bytes_sent} 字节)")
            resp_sock.close()
        except Exception as e:
            print(f"❌ 发送AI回复失败: {e}")
            
        # 启动单独的线程进行 TTS 朗读，防止阻塞主流程
        # [要求] 只需要播放AI回答的文本，不要把用户的问题也读出来
        if self.tts_engine:
            threading.Thread(target=self._play_tts_audio, args=(answer,), daemon=True).start()

    def _play_tts_audio(self, text):
        """通过 edge-tts 和 ffmpeg/aplay 朗读 AI 的回答"""
        if not self.tts_engine:
            return
            
        async def synthesize_and_play(text):
            voice_name = "zh-CN-XiaoxiaoNeural"
            output_mp3 = "main_tts_output.mp3"
            output_wav = "main_tts_output.wav"
            
            try:
                print(f"🔊 [TTS] 正在使用 Edge-TTS 合成语音...")
                # 1. 合成语音并保存为 MP3 文件
                communicate = edge_tts.Communicate(text, voice_name)
                await communicate.save(output_mp3)
                
                # 2. 使用 ffmpeg 转码为标准双声道 WAV
                subprocess.run(
                    ['ffmpeg', '-y', '-i', output_mp3, '-ac', '2', '-ar', '44100', output_wav],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=True
                )
                
                # 3. 使用 aplay 直接播放到 USB 声卡 (阻塞式播放，直到播放完毕)
                print("🔊 [TTS] 正在通过喇叭播报...")
                subprocess.run(
                    ['aplay', '-D', 'plughw:3,0', '-q', output_wav],
                    check=False
                )
                print("🔊 [TTS] 播报完毕。")
                
            except Exception as e:
                print(f"⚠️ [TTS] 语音合成或播放失败: {e}")
            finally:
                # 4. 清理临时文件
                for f in [output_mp3, output_wav]:
                    if os.path.exists(f):
                        try:
                            os.remove(f)
                        except:
                            pass

        try:
            asyncio.run(synthesize_and_play(text))
        except Exception as e:
            print(f"⚠️ [TTS] 播放线程异常: {e}")

    def stop(self):
        self.running = False
        self.sock.close()
        
        # 停止麦克风录音
        if self.stt_stream:
            self.stt_stream.stop_stream()
            self.stt_stream.close()
        if self.pyaudio_instance:
            self.pyaudio_instance.terminate()

class SensorSystem:
    """传感器数据采集系统"""
    
    def __init__(self):
        """初始化系统"""
        print("\n" + "=" * 60)
        print("  空地海地面站智能数显系统")
        print("=" * 60 + "\n")
        
        # 验证配置
        is_valid, errors = config.validate_config()
        if not is_valid:
            print("✗ 配置验证失败:\n")
            for error in errors:
                print(f"  {error}")
            print("\n请修改 config.py 后重试。\n")
            sys.exit(1)
        
        # 打印配置
        config.print_config()
        print()
        
        # 初始化日志记录器
        self.data_logger = DataLogger(config)
        self.logger = logging.getLogger(__name__)
        
        self.logger.info("系统正在初始化...")
        
        # 初始化 AI 分析引擎
        self.ai_analyst = AIDataAnalyst(udp_listen_port=8080)
        self.ai_analyst.start()
        
        # 初始化传感器读取器
        self.sensor_reader = SensorReader(
            sensor_types=config.SENSOR_TYPES,
            use_real_sensors=config.USE_REAL_SENSORS
        )
        
        # 初始化数据上传器
        self.uploader = None
        self._init_uploader()
        
        # 设置数据记录器引用
        if hasattr(self.uploader, 'set_data_logger'):
            self.uploader.set_data_logger(self.data_logger)
        
        # 初始化Dashboard
        self.dashboard = None
        if HAS_DASHBOARD and config.DISPLAY_MODE != 'none':
            self._init_dashboard()
        
        # 采集间隔
        self.interval = config.COLLECT_INTERVAL
        
        # 运行状态
        self.running = False
        
        # 统计信息
        self.stats = {
            'total_collections': 0,
            'successful_uploads': 0,
            'failed_uploads': 0,
            'start_time': None
        }
        
        self.logger.info("系统初始化完成!\n")
        
        # --- 新增：启动串口与UDP桥接服务 ---
        self.bridge = SerialUDPBridge(serial_port='/dev/ttyS0', baud_rate=9600)
        self.bridge.start()
        
        # 启动 AI 交互监听线程
        self.ai_interaction_thread = threading.Thread(target=self._ai_interaction_loop, daemon=True)
        self.ai_interaction_thread.start()

    def _ai_interaction_loop(self):
        """专门监听来自 Qt 的 AI 咨询请求 (使用 UDP 8082 端口)"""
        ai_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        ai_sock.bind(('0.0.0.0', 8082))
        ai_sock.settimeout(1.0)
        
        # 用于将 AI 回复发回给 Qt 的 socket (发送到 8080，让 Qt 的日志栏收到)
        resp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        
        while self.running:
            try:
                data, addr = ai_sock.recvfrom(2048)
                query = data.decode('utf-8', errors='ignore').strip()
                if query:
                    # 调用 AI 引擎分析 (现在是异步非阻塞的，内部会处理回调发送)
                    self.ai_analyst.process_ai_query(query)
            except socket.timeout:
                continue
            except Exception as e:
                print(f"AI交互异常: {e}")
        ai_sock.close()

    def _init_uploader(self):
        """初始化数据上传器"""
        upload_method = config.UPLOAD_METHOD.lower()
        
        if upload_method == 'http':
            self.logger.info("使用HTTP上传方式")
            self.uploader = HTTPUploader(config)
            
        elif upload_method == 'mqtt':
            self.logger.info("使用MQTT上传方式")
            # 延迟导入MQTTUploader，避免在不使用时导入
            try:
                from mqtt_uploader import MQTTUploader
                self.uploader = MQTTUploader(config)
            except ImportError:
                self.logger.error("MQTT上传器需要安装 paho-mqtt 库")
                self.logger.error("请运行: pip install paho-mqtt")
                sys.exit(1)
            
            # MQTT需要先连接
            self.logger.info("正在连接到MQTT服务器...")
            if not self.uploader.connect():
                self.logger.error("无法连接到MQTT服务器,请检查配置")
                sys.exit(1)
            self.logger.info("MQTT连接成功!")
            
        else:
            self.logger.error(f"不支持的上传方式: {upload_method}")
            sys.exit(1)
    
    def _init_dashboard(self):
        """初始化可视化仪表盘"""
        try:
            self.logger.info("正在启动可视化仪表盘...")
            self.dashboard = Dashboard(
                host='0.0.0.0', 
                port=config.DASHBOARD_PORT
            )
            
            # 在后台线程中启动Dashboard
            dashboard_thread = threading.Thread(
                target=self.dashboard.run,
                daemon=True
            )
            dashboard_thread.start()
            
            # 等待Dashboard启动
            time.sleep(2)
            
            # 根据配置选择显示方式
            display_mode = config.DISPLAY_MODE
            
            if display_mode == 'browser':
                self._open_kiosk_browser()
            elif display_mode == 'pygame' and HAS_PYGAME:
                self._start_pygame_display()
            elif display_mode == 'pyqt' and HAS_PYQT:
                self._start_pyqt_display()
            elif display_mode == 'tkinter' and HAS_TKINTER:
                self._start_tkinter_display()
            else:
                self.logger.info(f"显示模式: {display_mode}，请手动访问: http://localhost:{config.DASHBOARD_PORT}")
            
            self.logger.info("✓ 可视化仪表盘启动完成")
            
        except Exception as e:
            self.logger.error(f"仪表盘启动失败: {str(e)}")
            self.dashboard = None
    
    def _open_kiosk_browser(self):
        """打开Kiosk模式浏览器"""
        try:
            # 关闭可能已经存在的chromium实例
            subprocess.run(['pkill', 'chromium'], stderr=subprocess.DEVNULL)
            subprocess.run(['pkill', 'chrome'], stderr=subprocess.DEVNULL)
            time.sleep(1)
            
            # 检查浏览器是否可用
            browsers = ['chromium-browser', 'chromium', 'chrome']
            browser_cmd = None
            
            for browser in browsers:
                try:
                    subprocess.run(['which', browser], check=True, 
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    browser_cmd = browser
                    break
                except:
                    continue
            
            if not browser_cmd:
                self.logger.warning("未找到浏览器，无法自动打开仪表盘")
                self.logger.info(f"请手动访问: http://localhost:{config.DASHBOARD_PORT}")
                return
            
            # 启动浏览器，全屏无边框
            cmd = [
                browser_cmd,
                '--noerrdialogs',
                '--disable-infobars',
                '--kiosk',
                '--incognito',
                f'http://localhost:{config.DASHBOARD_PORT}'
            ]
            
            # 在后台运行浏览器
            subprocess.Popen(cmd, 
                           stdout=subprocess.DEVNULL, 
                           stderr=subprocess.DEVNULL,
                           start_new_session=True)
            
            self.logger.info(f"✓ 已启动 {browser_cmd} 全屏显示仪表盘")
            
            # 隐藏鼠标光标（需要unclutter）
            try:
                subprocess.Popen(['unclutter', '-idle', '0.5'], 
                               stdout=subprocess.DEVNULL, 
                               stderr=subprocess.DEVNULL,
                               start_new_session=True)
            except:
                pass  # unclutter不可用也没关系
            
        except Exception as e:
            self.logger.error(f"无法启动全屏浏览器: {str(e)}")
            self.logger.info(f"请手动访问: http://localhost:{config.DASHBOARD_PORT}")
    
    def _start_pygame_display(self):
        """启动Pygame显示窗口"""
        try:
            # 创建Pygame显示脚本
            pygame_script = """
import pygame
import requests
import json
import time
import threading

class PygameDisplay:
    def __init__(self, width=800, height=480):
        self.width = width
        self.height = height
        self.running = True
        self.data = {}
        
        # Pygame初始化
        pygame.init()
        pygame.display.set_caption("空地海地面站")
        
        # 创建窗口
        self.screen = pygame.display.set_mode((width, height), pygame.FULLSCREEN)
        self.clock = pygame.time.Clock()
        
        # 字体
        self.title_font = pygame.font.SysFont(None, 48)
        self.value_font = pygame.font.SysFont(None, 72)
        self.label_font = pygame.font.SysFont(None, 32)
        self.small_font = pygame.font.SysFont(None, 24)
        
        # 颜色
        self.colors = {
            'background': (10, 14, 42),
            'title': (0, 188, 212),
            'value': (255, 255, 255),
            'label': (170, 170, 170),
            'temp': (0, 188, 212),
            'humidity': (76, 175, 80),
            'pressure': (255, 152, 0),
            'light': (33, 150, 243),
            'border': (50, 50, 70)
        }
        
        # 启动数据获取线程
        self.data_thread = threading.Thread(target=self.fetch_data_loop, daemon=True)
        self.data_thread.start()
    
    def fetch_data(self):
        try:
            response = requests.get("http://localhost:%d/api/data" % %d, timeout=2)
            if response.status_code == 200:
                self.data = response.json()
                return True
        except:
            pass
        return False
    
    def fetch_data_loop(self):
        while self.running:
            self.fetch_data()
            time.sleep(2)
    
    def draw(self):
        # 清屏
        self.screen.fill(self.colors['background'])
        
        # 绘制标题
        title = self.title_font.render("空地海地面站智能数显系统", True, self.colors['title'])
        self.screen.blit(title, (self.width//2 - title.get_width()//2, 20))
        
        # 绘制数据
        self.draw_data()
        
        # 更新时间
        time_str = time.strftime("%Y-%m-%d %H:%M:%S")
        time_text = self.small_font.render(f"更新时间: {time_str}", True, self.colors['label'])
        self.screen.blit(time_text, (20, self.height - 40))
        
        # 刷新显示
        pygame.display.flip()
    
    def draw_data(self):
        usv = self.data.get('usv', {})
        scores = self.data.get('scores', {})
        
        # 四列布局
        col_width = self.width // 4
        col_height = self.height - 120
        
        # 温度
        self.draw_data_card(0, col_width, "温度", f"{usv.get('temp', '--'):.1f}", "°C", 
                          self.colors['temp'], 0, 100)
        
        # 湿度
        self.draw_data_card(col_width, col_width, "湿度", f"{usv.get('humidity', '--'):.1f}", "%", 
                          self.colors['humidity'], 0, 100)
        
        # 气压
        self.draw_data_card(col_width*2, col_width, "气压", f"{usv.get('pressure', '--'):.1f}", "hPa", 
                          self.colors['pressure'], 950, 1050)
        
        # 光照
        self.draw_data_card(col_width*3, col_width, "光照", f"{usv.get('light', '--'):.0f}", "lux", 
                          self.colors['light'], 0, 2000)
        
        # 底部评分
        y_bottom = self.height - 100
        water_score = scores.get('water_quality', 0)
        dam_score = scores.get('dam_safety', 0)
        
        # 水质评分
        water_text = self.small_font.render(f"水质评分: {water_score:.1f}%", True, self.colors['temp'])
        self.screen.blit(water_text, (col_width - water_text.get_width()//2, y_bottom))
        
        # 大坝安全评分
        dam_text = self.small_font.render(f"大坝安全: {dam_score:.1f}%", True, self.colors['humidity'])
        self.screen.blit(dam_text, (col_width*3 - dam_text.get_width()//2, y_bottom))
    
    def draw_data_card(self, x, width, label, value, unit, color, min_val, max_val):
        # 卡片背景
        card_rect = pygame.Rect(x + 10, 100, width - 20, self.height - 200)
        pygame.draw.rect(self.screen, (20, 24, 52), card_rect, border_radius=15)
        pygame.draw.rect(self.screen, self.colors['border'], card_rect, 2, border_radius=15)
        
        # 标签
        label_text = self.label_font.render(label, True, self.colors['label'])
        self.screen.blit(label_text, (x + width//2 - label_text.get_width()//2, 120))
        
        # 数值
        value_text = self.value_font.render(value, True, color)
        self.screen.blit(value_text, (x + width//2 - value_text.get_width()//2, 170))
        
        # 单位
        unit_text = self.label_font.render(unit, True, self.colors['label'])
        self.screen.blit(unit_text, (x + width//2 - unit_text.get_width()//2, 250))
        
        # 进度条背景
        bar_y = 300
        bar_width = width - 40
        bar_height = 20
        bar_x = x + 20
        
        pygame.draw.rect(self.screen, (50, 50, 70), 
                        (bar_x, bar_y, bar_width, bar_height), border_radius=10)
        
        # 进度条前景
        try:
            val = float(value) if value != '--' else 0
            percent = (val - min_val) / (max_val - min_val)
            percent = max(0, min(1, percent))
            fill_width = int(bar_width * percent)
            
            pygame.draw.rect(self.screen, color, 
                            (bar_x, bar_y, fill_width, bar_height), border_radius=10)
        except:
            pass
        
        # 刻度标签
        min_text = self.small_font.render(str(min_val), True, self.colors['label'])
        max_text = self.small_font.render(str(max_val), True, self.colors['label'])
        self.screen.blit(min_text, (bar_x, bar_y + 25))
        self.screen.blit(max_text, (bar_x + bar_width - max_text.get_width(), bar_y + 25))
    
    def run(self):
        print("Pygame显示启动，按ESC键退出")
        
        while self.running:
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    self.running = False
                elif event.type == pygame.KEYDOWN:
                    if event.key == pygame.K_ESCAPE:
                        self.running = False
            
            self.draw()
            self.clock.tick(30)
        
        pygame.quit()

if __name__ == "__main__":
    display = PygameDisplay(%d, %d)
    display.run()
""" % (config.DASHBOARD_PORT, config.DASHBOARD_PORT, config.DISPLAY_WIDTH, config.DISPLAY_HEIGHT)
            
            # 写入临时文件
            temp_file = "/tmp/pygame_display.py"
            with open(temp_file, "w") as f:
                f.write(pygame_script)
            
            # 在子进程中运行
            subprocess.Popen(
                [sys.executable, temp_file],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True
            )
            
            self.logger.info("✓ 已启动Pygame全屏显示")
            
        except Exception as e:
            self.logger.error(f"启动Pygame显示失败: {str(e)}")
            # 回退到浏览器模式
            self._open_kiosk_browser()
    def _start_tkinter_display(self):
        """启动Tkinter显示窗口"""
        try:
            # 检查display_tkinter.py文件是否存在
            display_script = os.path.join(os.path.dirname(__file__), "display_tkinter.py")
            
            if not os.path.exists(display_script):
                self.logger.error("display_tkinter.py 文件不存在")
                self.logger.info(f"当前目录: {os.path.dirname(__file__)}")
                # 回退到浏览器模式
                self._open_kiosk_browser()
                return
            
            self.logger.info(f"找到Tkinter显示脚本: {display_script}")
            
            # 在子进程中运行display_tkinter.py
            cmd = [
                sys.executable,
                display_script,
                f"--url=http://localhost:{config.DASHBOARD_PORT}",
                f"--width={config.DISPLAY_WIDTH}",
                f"--height={config.DISPLAY_HEIGHT}",
                f"--fullscreen={str(config.FULLSCREEN).lower()}"
            ]
            
            self.logger.info(f"启动命令: {' '.join(cmd)}")
            
            subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True
            )
            
            # 等待一下确保窗口启动
            time.sleep(2)
            
            self.logger.info(f"✓ 已启动Tkinter显示 ({config.DISPLAY_WIDTH}x{config.DISPLAY_HEIGHT})")
            
        except Exception as e:
            self.logger.error(f"启动Tkinter显示失败: {str(e)}")
            # 回退到浏览器模式
            self._open_kiosk_browser()
    def collect_and_upload(self):
        """采集一次数据并上传"""
        try:
            # 更新统计
            self.stats['total_collections'] += 1
            
            # 读取传感器数据
            self.logger.info(f"[{self.stats['total_collections']}] 开始采集传感器数据...")
            sensor_data = self.sensor_reader.read_all_sensors()
            
            # 上传数据到远程服务器
            self.logger.info("正在上传数据到服务器...")
            success = self.uploader.upload(sensor_data)
            
            # 更新Dashboard（如果启用）
            if self.dashboard:
                try:
                    self.dashboard.update_data(sensor_data)
                    if self.stats['total_collections'] % 10 == 0:  # 每10次记录一次
                        self.logger.info("✓ 数据已更新到本地仪表盘")
                except Exception as e:
                    self.logger.error(f"更新Dashboard失败: {str(e)}")
            
            # 记录传感器数据
            self.data_logger.log_sensor_data(sensor_data, upload_success=success)
            
            # 备份数据到本地
            self.data_logger.backup_data(sensor_data)
            
            # 更新统计
            if success:
                self.stats['successful_uploads'] += 1
                self.logger.info("✓ 本次采集与上传完成\n")
            else:
                self.stats['failed_uploads'] += 1
                self.logger.warning("✗ 数据上传失败\n")
            
            return success
            
        except KeyboardInterrupt:
            raise  # 向上传递中断信号
            
        except Exception as e:
            self.logger.error(f"采集或上传过程出错: {str(e)}")
            self.stats['failed_uploads'] += 1
            return False
    
    def print_stats(self):
        """打印统计信息"""
        self.logger.info("\n" + "=" * 60)
        self.logger.info("运行统计:")
        self.logger.info("=" * 60)
        self.logger.info(f"总采集次数: {self.stats['total_collections']}")
        self.logger.info(f"成功上传: {self.stats['successful_uploads']}")
        self.logger.info(f"上传失败: {self.stats['failed_uploads']}")
        
        if self.stats['total_collections'] > 0:
            success_rate = (self.stats['successful_uploads'] / self.stats['total_collections']) * 100
            self.logger.info(f"成功率: {success_rate:.1f}%")
        
        if self.stats['start_time']:
            runtime = time.time() - self.stats['start_time']
            hours = int(runtime // 3600)
            minutes = int((runtime % 3600) // 60)
            seconds = int(runtime % 60)
            self.logger.info(f"运行时长: {hours}小时 {minutes}分钟 {seconds}秒")
        
        self.logger.info("=" * 60 + "\n")
    
    def run(self):
        """运行主循环"""
        self.running = True
        self.stats['start_time'] = time.time()
        
        self.logger.info(f"开始定时采集,间隔: {self.interval} 秒")
        self.logger.info("按 Ctrl+C 停止程序\n")
        
        try:
            while self.running:
                # 采集并上传
                self.collect_and_upload()
                
                # 等待下一次采集
                if self.running:
                    self.logger.info(f"等待 {self.interval} 秒后进行下一次采集...")
                    time.sleep(self.interval)
                    
        except KeyboardInterrupt:
            self.logger.info("\n收到中断信号,正在停止...")
        
        finally:
            self.stop()
    
    def stop(self):
        """停止系统"""
        self.running = False
        
        # --- 新增：关闭 AI 引擎 ---
        if hasattr(self, 'ai_analyst'):
            self.ai_analyst.stop()
            
        # --- 新增：关闭桥接 ---
        if hasattr(self, 'bridge'):
            self.bridge.stop()
            
        # 打印统计信息
        self.print_stats()
        
        # 如果使用MQTT,断开连接
        if hasattr(self.uploader, 'disconnect'):
            self.uploader.disconnect()
        
        self.logger.info("系统已停止")
        self.logger.info("=" * 60 + "\n")


# ============================================
# 信号处理
# ============================================

sensor_system = None

def signal_handler(sig, frame):
    """处理系统信号"""
    global sensor_system
    print('\n收到终止信号...')
    if sensor_system:
        sensor_system.stop()
    sys.exit(0)


# ============================================
# 主函数
# ============================================

def main():
    """主函数"""
    global sensor_system
    
    # 注册信号处理器
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        # 创建并运行系统
        sensor_system = SensorSystem()
        sensor_system.run()
        
    except Exception as e:
        print(f"\n✗ 系统启动失败: {str(e)}")
        sys.exit(1)


if __name__ == "__main__":
    main()