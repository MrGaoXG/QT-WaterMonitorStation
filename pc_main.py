import socket
import time
import sys
import threading
import json
import os

try:
    import serial
except ImportError:
    print("❌ 缺少 serial 库，请运行: pip install pyserial")
    sys.exit(1)

# 强制将 Windows 控制台的标准输出编码设置为 UTF-8，防止表情符号报错
import io
import ctypes

def disable_quickedit():
    """
    禁用 Windows 控制台的 QuickEdit 模式，防止鼠标点击控制台窗口时程序挂起（卡死）
    """
    if os.name == 'nt':
        try:
            kernel32 = ctypes.windll.kernel32
            hStdIn = kernel32.GetStdHandle(-10)
            mode = ctypes.c_uint32()
            kernel32.GetConsoleMode(hStdIn, ctypes.byref(mode))
            mode.value &= ~0x0040  # 取消 ENABLE_QUICK_EDIT_MODE
            kernel32.SetConsoleMode(hStdIn, mode)
        except Exception:
            pass

disable_quickedit()

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', line_buffering=True)
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', line_buffering=True)

try:
    import ollama
except ImportError:
    print("❌ 缺少 ollama 库，请运行: pip install ollama")
    sys.exit(1)

try:
    import pyttsx3
except ImportError:
    print("❌ 缺少 pyttsx3 库，请运行: pip install pyttsx3")
    sys.exit(1)

try:
    import pyaudio
    from vosk import Model, KaldiRecognizer
    HAS_VOSK = True
except ImportError:
    HAS_VOSK = False
    print("⚠️ 缺少 vosk 或 pyaudio 库，麦克风语音唤醒功能将被禁用。")
    print("👉 请运行: pip install vosk pyaudio")

# ==========================================
# 配置参数
# ==========================================
OLLAMA_MODEL = "qwen2.5:latest"  # 替换为你本地实际的 Ollama 模型名称，如 qwen:0.5b, llama3 等
UDP_LISTEN_PORT = 8082         # 接收 Qt 端发送的问题
UDP_SEND_PORT = 8080           # 将 AI 回答发回 Qt 端
SERIAL_PORT = "COM8"           # Windows 下的串口名称
BAUD_RATE = 9600

is_tts_playing = False

# 全局变量：存储最新的传感器数据
latest_sensor_data = {}
last_alert_time = 0
ALERT_COOLDOWN = 60  # 异常报警冷却时间（秒）

def play_tts(text):
    """
    使用 Windows 自带的离线 TTS 引擎 (pyttsx3)，实现 0 延迟语音播报
    """
    global is_tts_playing
    is_tts_playing = True
    
    def _synthesize():
        try:
            # 解决 Windows 下多线程调用 pyttsx3(SAPI5) 导致 COM 未初始化或卡死的问题
            import pythoncom
            pythoncom.CoInitialize()
            
            print("🔊 [TTS] 正在通过本机扬声器播报 (0延迟)...")
            engine = pyttsx3.init()
            engine.setProperty('rate', 180) # 设置语速，可按需修改
            engine.say(text)
            engine.runAndWait()
            print("🔊 [TTS] 播报完毕。")
        except Exception as e:
            print(f"❌ [TTS] 播报失败: {e}")
        finally:
            global is_tts_playing
            is_tts_playing = False
            try:
                import pythoncom
                pythoncom.CoUninitialize()
            except Exception:
                pass

    # 在新线程中运行 TTS，避免阻塞主流程（前提是必须处理 pythoncom）
    threading.Thread(target=_synthesize, daemon=True).start()

def check_anomalies(data):
    """
    检查传感器数据是否存在异常，如有异常则触发 AI 报警
    """
    global last_alert_time
    
    ph_val = data.get("ph") or data.get("PH")
    
    # 兼容 Qt 期望的嵌套格式 (drone/ship) 以及扁平格式
    bat_val = data.get("bat") or data.get("battery") or data.get("BAT")
    if bat_val is None:
        for key in ["drone", "UVA_telemetry", "ship", "USV_telemetry"]:
            if key in data and isinstance(data[key], dict):
                nested_bat = data[key].get("bat") or data[key].get("battery")
                if nested_bat is not None:
                    bat_val = nested_bat
                    break
                    
    anomalies = []
    if ph_val is not None:
        try:
            ph = float(ph_val)
            if ph < 6.0 or ph > 9.0:
                anomalies.append(f"水质PH值异常({ph})")
        except:
            pass
            
    if bat_val is not None:
        try:
            bat = float(bat_val)
            if bat < 20.0:
                anomalies.append(f"设备电量过低({bat}%)")
        except:
            pass
            
    if anomalies:
        current_time = time.time()
        # 如果不在冷却期内，则触发 AI 告警
        if current_time - last_alert_time > ALERT_COOLDOWN:
            last_alert_time = current_time
            anomaly_str = "，".join(anomalies)
            print(f"\n⚠️ [系统预警] 发现异常数据: {anomaly_str}，正在触发 AI 分析与播报...")
            
            # 构造紧急情况下的 Prompt
            alert_prompt = (
                f"系统刚刚检测到异常情况：{anomaly_str}！当前传感器数据：{json.dumps(data, ensure_ascii=False)}。"
                f"作为贴心的 AI 助手，请用充满人情味、关切且带一点点急迫的人类口吻提醒操作员（比如带点情绪词），简短分析原因并给出建议。就像看到同事遇到麻烦一样，语气要有温度。字数严格控制在50字以内。"
            )
            
            # 使用新线程触发 AI 报警，防止阻塞当前线程
            threading.Thread(target=process_ai_query, args=(alert_prompt, False), daemon=True).start()

def serial_listener_thread():
    """
    监听 Windows 串口数据，并将数据通过 UDP 转发给 Qt
    同时更新全局的最新数据供 AI 使用
    """
    global latest_sensor_data
    
    send_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    # 使用本机环回地址发送，防止 255.255.255.255 广播被 Qt 多次接收
    
    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=0.5)
        print(f"🔌 [串口] 成功打开 {SERIAL_PORT} (波特率 {BAUD_RATE})")
    except Exception as e:
        print(f"⚠️ [串口] 打开 {SERIAL_PORT} 失败: {e}")
        print("如果不需要串口数据可以忽略，或者在代码中修改 SERIAL_PORT。")
        return
        
    while True:
        try:
            if ser.in_waiting:
                data_bytes = ser.readline()
                if data_bytes:
                    try:
                        decoded_data = data_bytes.strip().decode('utf-8', errors='ignore')
                        # 尝试解析为 JSON，如果成功就更新全局状态
                        json_data = json.loads(decoded_data)
                        latest_sensor_data = json_data
                        
                        # 检查异常
                        check_anomalies(json_data)
                    except json.JSONDecodeError:
                        pass
                        
                    # 无论如何，都把串口收到的原始数据通过 UDP 发送给 Qt
                    send_sock.sendto(data_bytes, ('127.0.0.1', UDP_SEND_PORT))
        except Exception as e:
            pass
        time.sleep(0.01)

def send_to_qt(message, is_user=False):
    """
    将消息通过 UDP 发回给 Qt 界面（使用本机环回地址，防止广播引发的重复消息）
    """
    if is_user:
        reply_payload = f"[AI咨询] {message}"
    else:
        reply_payload = f"[AI诊断回复] {message}"
        
    try:
        resp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        # 发送到 127.0.0.1 避免 Windows 下 255.255.255.255 广播被多个网卡同时接收而导致 Qt 界面出现两条一样的话
        resp_sock.sendto(reply_payload.encode('utf-8'), ('127.0.0.1', UDP_SEND_PORT))
        resp_sock.close()
        print(f"✅ [UDP] 已成功将消息发送至 Qt 界面: {reply_payload}")
    except Exception as e:
        print(f"❌ [UDP] 发送失败: {e}")

def process_ai_query(query, from_stt=False):
    """
    调用本地 Ollama 获取回答，并触发发送和播报
    """
    print(f"\n" + "="*50)
    print(f"🤖 [AI 思考中] 收到问题: '{query}'")
    
    # 如果是从麦克风语音唤醒输入的，先把用户的问题发给 Qt 显示
    if from_stt:
        send_to_qt(query, is_user=True)
    
    start_time = time.time()
    try:
        response = ollama.chat(model=OLLAMA_MODEL, messages=[
            {'role': 'system', 'content': f'你叫“小高”，是一个温柔、贴心、高情商的水质监测站专属 AI 助手。'
                                          f'你的说话方式应该像人类同事一样自然、充满人情味，多用口语化的关心表达，绝对不要像冷冰冰的机器人。'
                                          f'当前系统最新传感器数据：{json.dumps(latest_sensor_data, ensure_ascii=False)}。'
                                          f'回答要简短精炼（控制在50字以内）、通俗易懂，使用中文。'},
            {'role': 'user', 'content': query}
        ])
        answer = response['message']['content'].strip()
        elapsed = time.time() - start_time
        print(f"✅ [AI 回答完毕] 耗时: {elapsed:.2f} 秒\n{answer}")
        
        # 1. 发送文字给 Qt
        send_to_qt(answer, False)
        
        # 2. 语音播报
        play_tts(answer)
        
    except Exception as e:
        err_str = str(e)
        print(f"❌ [AI 调用调失败]: {err_str}")
        if "not found" in err_str.lower():
            print(f"⚠️ 请确保在终端运行过: ollama pull {OLLAMA_MODEL}")
        send_to_qt("AI 引擎调用失败，请检查 Ollama 服务。", False)
    print("="*50 + "\n")

def udp_listener_thread():
    """
    监听 Qt 界面通过 UDP 发送过来的文本问题
    """
    server_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server_sock.bind(('0.0.0.0', UDP_LISTEN_PORT))
        print(f"👂 [UDP 监听] 已启动，正在端口 {UDP_LISTEN_PORT} 等待 Qt 发送问题...")
    except Exception as e:
        print(f"❌ [UDP 监听] 端口 {UDP_LISTEN_PORT} 绑定失败: {e}")
        return

    while True:
        try:
            data, addr = server_sock.recvfrom(2048)
            query = data.decode('utf-8', errors='ignore').strip()
            # 如果接收到的消息已经是 [AI咨询] 或者 [AI诊断回复]，直接忽略，防止死循环/重复处理
            if query and not query.startswith("[AI咨询]") and not query.startswith("[AI诊断回复]"):
                print(f"\n📨 [UDP] 收到来自 Qt ({addr}) 的提问！内容: {query}")
                
                # 因为 Qt 传过来的文本不再主动添加气泡，我们需要在这里把 Qt 传过来的问题发回去让它显示
                send_to_qt(query, is_user=True)
                
                # 启动新线程处理，防止阻塞后续接收
                threading.Thread(target=process_ai_query, args=(query, False), daemon=True).start()
        except Exception as e:
            print(f"⚠️ [UDP 监听] 异常: {e}")

def stt_listener_thread():
    """
    监听本机麦克风的语音输入
    """
    model_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "model")
    if not os.path.exists(model_path):
        print(f"⚠️ [STT] 未找到 Vosk 模型文件夹 ({model_path})，麦克风语音功能已禁用。")
        return

    try:
        print(f"⏳ [STT] 正在加载 Vosk 语音模型...")
        recognizer = KaldiRecognizer(Model(model_path), 16000)
        pa = pyaudio.PyAudio()
        stream = pa.open(
            format=pyaudio.paInt16,
            channels=1,
            rate=16000,
            input=True,
            frames_per_buffer=8000
        )
        print("✅ [STT] 本机麦克风已就绪，支持语音唤醒 (唤醒词: 小俊/小高/小糕)！")
    except Exception as e:
        print(f"❌ [STT] 麦克风初始化失败: {e}")
        return

    wake_words = ["小高", "小膏", "小糕", "小俊"]
    sleep_words = ["退下", "再见", "拜拜", "结束", "停止对话"]
    is_awake = False
    awake_timeout = 0

    while True:
        try:
            if is_tts_playing:
                # 正在播放 TTS 时，清空缓冲区，防止把喇叭的声音又录进去
                stream.read(4000, exception_on_overflow=False)
                if is_awake:
                    awake_timeout = time.time() + 60 # 重新计时，保持唤醒
                time.sleep(0.1)
                continue

            data = stream.read(4000, exception_on_overflow=False)
            if len(data) == 0:
                continue
            
            if is_awake and time.time() > awake_timeout:
                print("💤 [STT] 长时间无指令 (60秒)，自动退出唤醒状态，重新进入休眠。")
                is_awake = False

            if recognizer.AcceptWaveform(data):
                result = json.loads(recognizer.Result())
                text = result.get("text", "").replace(" ", "")
                if not text:
                    continue

                print(f"\n🗣️ [麦克风] 听到: {text}")

                if not is_awake:
                    for w in wake_words:
                        if w in text:
                            is_awake = True
                            awake_timeout = time.time() + 60 # 唤醒后 60 秒内持续对话
                            print(f"🌟 [STT] 已唤醒！进入连续对话模式 (60秒)...")
                            
                            cmd_text = text.split(w, 1)[1]
                            if len(cmd_text) >= 2:
                                threading.Thread(target=process_ai_query, args=(cmd_text, True), daemon=True).start()
                            else:
                                play_tts("我在，请直接说出您的问题。")
                            break
                else:
                    # 检查是否包含退下指令
                    should_sleep = False
                    for sw in sleep_words:
                        if sw in text:
                            should_sleep = True
                            break
                            
                    if should_sleep:
                        print("💤 [STT] 收到指令，主动退出唤醒状态。")
                        is_awake = False
                        play_tts("好的，我先退下了，有需要随时叫我。")
                    else:
                        # 继续对话，并重置超时时间
                        awake_timeout = time.time() + 60
                        threading.Thread(target=process_ai_query, args=(text, True), daemon=True).start()
        except Exception as e:
            pass

if __name__ == "__main__":
    print("="*60)
    print("  [PC端专属] 大模型调用与语音交互独立服务 (Ollama 版)")
    print("="*60)
    print(f"👉 目标模型: {OLLAMA_MODEL} (确保 ollama 正在运行此模型)")
    print(f"👉 UDP 接收: {UDP_LISTEN_PORT} (接收 Qt 提问)")
    print(f"👉 UDP 发送: {UDP_SEND_PORT} (回传 Qt 界面)")
    print("="*60)
    
    # 启动 UDP 监听线程
    threading.Thread(target=udp_listener_thread, daemon=True).start()
    
    # 启动串口监听线程 (负责接收 COM8 数据、预警并转发 Qt)
    threading.Thread(target=serial_listener_thread, daemon=True).start()
    
    # 启动麦克风监听线程
    if HAS_VOSK:
        threading.Thread(target=stt_listener_thread, daemon=True).start()
        
    try:
        # 保持主线程运行
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n🛑 服务已停止。")
        sys.exit(0)
