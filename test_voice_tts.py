import sys
import argparse
import asyncio
import edge_tts
import os
import subprocess

def run_tts_test(text, list_voices=False, voice_index=0):
    """
    使用高质量的 Edge-TTS 引擎测试语音合成
    """
    print("\n" + "="*50)
    print("📢 正在初始化高质量语音合成引擎 (Edge-TTS)...")
    print("="*50)
    
    # 我们使用晓晓（非常自然的女声）作为默认发音人
    voice_name = "zh-CN-XiaoxiaoNeural"
    
    print(f"\n[准备播放音频] 文本内容: {text}")
    print(f"[发音人] {voice_name}")
    print("请注意听连接到树莓派 3.5mm 音频孔或 USB 声卡的喇叭/功放...\n")
    
    output_mp3 = "temp_tts_output.mp3"
    output_wav = "temp_tts_output.wav"
    
    async def _synthesize_and_play():
        try:
            # 1. 合成语音并保存为 MP3 文件
            communicate = edge_tts.Communicate(text, voice_name)
            await communicate.save(output_mp3)
            
            # 2. 使用 ffmpeg 将 MP3 彻底转换为标准双声道 44100Hz 的 WAV 文件
            # 这是为了迎合你那块极度挑剔的 USB 声卡
            print("� 正在转码为标准双声道 WAV...")
            subprocess.run(
                ['ffmpeg', '-y', '-i', output_mp3, '-ac', '2', '-ar', '44100', output_wav],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=True
            )
            
            # 3. 使用最原始的 aplay 直接把 wav 砸给 USB 声卡的智能插件 (plughw:3,0)
            print("🔊 正在通过系统底层推送音频流...")
            subprocess.run(
                ['aplay', '-D', 'plughw:3,0', '-q', output_wav],
                check=False
            )
            
            print("\n[播放完毕] 🎉")
            
        except Exception as e:
            print(f"\n❌ 发生错误: {e}")
            print("👉 请确保在终端运行过: sudo apt-get install ffmpeg alsa-utils -y")
        finally:
            # 4. 清理所有临时文件
            for f in [output_mp3, output_wav]:
                if os.path.exists(f):
                    try:
                        os.remove(f)
                    except:
                        pass

    # 运行异步任务
    asyncio.run(_synthesize_and_play())
    print("="*50 + "\n")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="本地离线文本转语音 (TTS) 测试")
    parser.add_argument("--text", type=str, default="你好，我是空地海智能监测站的 AI 助手。无人机当前电量为百分之十八，请注意及时返航充电。", help="要朗读的文本内容")
    parser.add_argument("--list", action="store_true", help="列出当前系统所有可用的发音人声线")
    parser.add_argument("--voice", type=int, default=None, help="通过索引号指定发音人声线 (配合 --list 查看)")
    args = parser.parse_args()
    
    run_tts_test(args.text, list_voices=args.list, voice_index=args.voice)
