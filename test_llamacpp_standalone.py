import socket
import json
import time
import os
import sys

# 尝试导入 llama_cpp
try:
    from llama_cpp import Llama
except ImportError:
    print("❌ 错误: 找不到 llama-cpp-python 库！")
    print("请先在树莓派上运行: CMAKE_ARGS=\"-DGGML_CPU_ARM_ARCH=armv8\" pip3 install llama-cpp-python")
    sys.exit(1)

# 配置参数
UDP_LISTEN_IP = "127.0.0.1"
UDP_LISTEN_PORT = 8082
UDP_TARGET_IP = "127.0.0.1"
UDP_TARGET_PORT = 8080

# 模型文件路径配置
MODEL_PATH = "models/qwen2.5-0.5b-instruct-q4_k_m.gguf"

def main():
    print("=" * 60)
    print("  [单体测试] 基于 llama.cpp 的大模型调用与 UDP 回传测试脚本")
    print("=" * 60)

    # 1. 检查模型文件是否存在
    if not os.path.exists(MODEL_PATH):
        print(f"❌ 错误: 找不到模型文件 {MODEL_PATH}")
        print("请在终端执行以下命令下载模型：")
        print("mkdir -p models && cd models")
        print("wget https://modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/master/qwen2.5-0.5b-instruct-q4_k_m.gguf")
        sys.exit(1)

    # 2. 将大模型加载到内存 (只在启动时执行一次，后续推理零开销)
    print(f"\n⏳ [1/4] 正在将模型加载到内存中 (这可能需要几秒钟)...")
    print(f"📁 模型路径: {MODEL_PATH}")
    try:
        # n_threads=4 针对树莓派的 4 核心优化
        # n_ctx=2048 设置上下文长度
        llm = Llama(
            model_path=MODEL_PATH, 
            n_threads=4, 
            n_ctx=2048, 
            verbose=False # 关闭繁琐的 C++ 底层日志打印
        )
        print("✅ 模型加载成功！")
    except Exception as e:
        print(f"❌ 模型加载失败: {e}")
        sys.exit(1)

    # 3. 创建 UDP Socket
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind((UDP_LISTEN_IP, UDP_LISTEN_PORT))
        print(f"\n📡 [2/4] 服务启动成功，正在持续监听 UDP {UDP_LISTEN_IP}:{UDP_LISTEN_PORT} 端口...")
        print("👉 请在 Qt 地面站页面发送咨询指令进行测试。\n")
    except Exception as e:
        print(f"❌ 无法绑定端口 {UDP_LISTEN_PORT}: {e}")
        sys.exit(1)

    # 4. 进入死循环监听 QT 发来的消息
    while True:
        try:
            # 接收数据
            data, addr = sock.recvfrom(1024)
            query_text = data.decode('utf-8').strip()
            
            print("-" * 50)
            print(f"🤖 [收到请求] 来自 {addr}，内容: '{query_text}'")
            print(f"⏳ [3/4] 正在调用本地模型进行推理 (基于 llama.cpp)...")
            
            start_time = time.time()
            
            # 模拟当前的无人机/设备电量状态数据 (你可以根据需要修改这些值)
            mock_device_status = {
                "无人机 (UAV)": {"电量": "18%", "状态": "低电量警告", "当前任务": "水质采样"},
                "无人船 (USV)": {"电量": "85%", "状态": "正常", "当前任务": "巡航"},
                "环境参数": {"pH值": 7.2, "温度": "24.5℃"}
            }
            
            # 构建强大的 System Prompt 赋予 AI 角色并注入实时数据
            system_prompt = f"""
            你是一个专业、严谨的水文监测站和无人设备控制中心的 AI 助手。
            
            【当前系统实时设备状态数据如下】：
            {json.dumps(mock_device_status, ensure_ascii=False, indent=2)}
            
            【你的任务】：
            1. 结合上述实时状态数据，准确回答用户的询问。
            2. 如果用户问到“无人机电量”或相关状态，请直接读取数据回答。
            3. 如果发现电量低于 20%，必须在回答中主动发出明确的【低电量警告】，并建议立即返航充电。
            4. 保持回答简明扼要，像一个专业的 AI 指挥官。
            """
            
            # 使用 llama.cpp 生成回复
            response = llm.create_chat_completion(
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": query_text}
                ],
                max_tokens=256,   # 限制最大生成长度，加快速度
                temperature=0.3   # 降低随机性，让回答更准确基于数据
            )
            
            # 解析回复内容
            ans = response['choices'][0]['message']['content'].strip()
            cost_time = time.time() - start_time
            
            print(f"✅ [推理成功] 耗时: {cost_time:.2f} 秒")
            print(f"💬 [AI回答]:\n{ans}\n")

            # 5. 打包为 QT 识别的格式并发送
            print(f"📡 [4/4] 准备将回答打包为 UDP 格式并发送至本机 {UDP_TARGET_PORT} 端口...")
            # 加上前缀以绕过 JSON 解析
            qt_msg = f"[AI诊断回复] {ans}"
            bytes_sent = sock.sendto(qt_msg.encode('utf-8'), (UDP_TARGET_IP, UDP_TARGET_PORT))
            print(f"✅ [发送成功] 已成功向 {UDP_TARGET_IP}:{UDP_TARGET_PORT} 发送了 {bytes_sent} 字节的数据。")
            print("-" * 50)
            print("⏳ 继续监听下一个问题...\n")
            
        except KeyboardInterrupt:
            print("\n⏹️ 用户按下了 Ctrl+C，服务停止。")
            break
        except Exception as e:
            print(f"❌ 处理过程中发生错误: {e}")

    sock.close()

if __name__ == "__main__":
    main()
