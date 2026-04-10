import os
import sys
import json
import time
import wave
import argparse

try:
    import pyaudio
    from vosk import Model, KaldiRecognizer
    HAS_VOSK = True
except ImportError:
    HAS_VOSK = False

def run_voice_assistant(model_path="model"):
    if not HAS_VOSK:
        print("错误: 缺少依赖。请在树莓派上运行以下命令安装:")
        print("sudo apt-get install portaudio19-dev")
        print("pip install pyaudio vosk")
        return

    if not os.path.exists(model_path):
        print(f"错误: 找不到 Vosk 模型目录 '{model_path}'。")
        print("请从 https://alphacephei.com/vosk/models 下载中文轻量级模型 (例如 vosk-model-small-cn-0.22.zip)")
        print("并解压到当前目录下重命名为 'model' 文件夹。")
        return

    print("正在加载语音识别模型 (Vosk)...")
    model = Model(model_path)
    # 设置采样率为 16000
    recognizer = KaldiRecognizer(model, 16000)

    p = pyaudio.PyAudio()

    try:
        # 打开麦克风流
        stream = p.open(format=pyaudio.paInt16,
                        channels=1,
                        rate=16000,
                        input=True,
                        frames_per_buffer=8000)
        stream.start_stream()
    except Exception as e:
        print(f"无法打开麦克风设备: {e}")
        print("请检查是否插入了 USB 麦克风，并在 Linux 下使用 `arecord -l` 确认设备。")
        return

    print("\n[音频采集模块已启动]")
    print("请对着麦克风说话 (按 Ctrl+C 退出)...")

    try:
        while True:
            data = stream.read(4000, exception_on_overflow=False)
            if len(data) == 0:
                break
            
            # 识别到完整的一句话
            if recognizer.AcceptWaveform(data):
                result = json.loads(recognizer.Result())
                text = result.get("text", "").replace(" ", "")
                if text:
                    print(f"\n[用户语音输入] >> {text}")
                    # =======================================================
                    # 这里可以将识别到的 text 通过 UDP 发给 main.py
                    # 或者如果是集成在 main.py 内部，则直接推入 LLM 的任务队列
                    # =======================================================
            else:
                # 正在说话的过程，可以打印部分结果（可选）
                partial = json.loads(recognizer.PartialResult())
                partial_text = partial.get("partial", "").replace(" ", "")
                if partial_text:
                    sys.stdout.write(f"\r正在倾听: {partial_text}")
                    sys.stdout.flush()

    except KeyboardInterrupt:
        print("\n[退出] 语音监听已停止。")
    finally:
        stream.stop_stream()
        stream.close()
        p.terminate()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="本地离线语音识别测试 (Vosk)")
    parser.add_argument("--model", type=str, default="model", help="Vosk 模型文件夹的路径")
    args = parser.parse_args()
    
    run_voice_assistant(args.model)
