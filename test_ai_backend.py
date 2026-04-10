import socket
import json
import threading
import time

# 测试用的模拟前端接收端口 (相当于 Qt 的 8080 端口)
MOCK_QT_PORT = 8080
# Python 后端 AI 监听的端口
PYTHON_AI_PORT = 8082

def listen_for_reply():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    # 允许端口复用
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(('0.0.0.0', MOCK_QT_PORT))
    print(f"👂 [测试脚本] 正在监听端口 {MOCK_QT_PORT} 等待 AI 回复...")
    
    try:
        sock.settimeout(30.0) # 等待最多 30 秒
        data, addr = sock.recvfrom(4096)
        print(f"\n✅ [测试脚本] 收到来自 {addr} 的回复:")
        print(f"   {data.decode('utf-8')}\n")
    except socket.timeout:
        print("\n❌ [测试脚本] 接收超时，没有收到 AI 的回复。请检查 Python 后端是否正常运行。")
    finally:
        sock.close()

def test_ask_ai(question):
    print(f"\n🚀 [测试脚本] 开始向 AI 发送测试问题: '{question}'")
    
    # 启动一个独立线程监听回复
    listener = threading.Thread(target=listen_for_reply)
    listener.start()
    
    # 给监听器一点时间启动
    time.sleep(0.5)
    
    # 发送 UDP 请求到 8082
    sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sender.sendto(question.encode('utf-8'), ('127.0.0.1', PYTHON_AI_PORT))
    sender.close()
    print(f"📤 [测试脚本] 问题已发送到端口 {PYTHON_AI_PORT}，等待处理 (可能需要几秒到几十秒，取决于树莓派算力)...\n")
    
    listener.join()

if __name__ == '__main__':
    print("="*50)
    print("  大模型后端独立测试工具 (Raspberry Pi)")
    print("="*50)
    print("【前提条件】")
    print("1. 已安装 Ollama (在树莓派终端运行 ollama serve)")
    print("2. 已拉取 qwen2.5 模型 (建议在树莓派使用 qwen2.5:0.5b)")
    print("3. 已在另一个终端运行了 python main.py (启动了核心后端)")
    print("="*50)
    
    q = input("\n请输入你想问大模型的问题 (直接回车使用默认问题): ")
    if not q.strip():
        q = "当前水质的PH值是7.5，属于正常范围吗？"
        
    test_ask_ai(q)
