import socket
import time
import sys

# 尝试导入 ollama 库
try:
    import ollama
except ImportError:
    print("❌ 缺少 ollama 库，请先运行: pip install ollama")
    sys.exit(1)

def process_and_reply(model_name, query, target_ip='127.0.0.1', target_port=8080):
    print("\n" + "-"*50)
    # -----------------------------------------
    # 第一步：测试 Ollama 本地调用
    # -----------------------------------------
    print(f"[1/3] ⏳ 正在尝试调用本地大模型: {model_name}")
    print(f"      收到的问题: '{query}'")
    print("      (这可能需要几秒到几十秒，请耐心等待...)")
    
    start_time = time.time()
    try:
        response = ollama.chat(model=model_name, messages=[
            {'role': 'user', 'content': query}
        ])
        answer = response['message']['content']
        elapsed = time.time() - start_time
        print(f"\n✅ [调用成功] 耗时: {elapsed:.2f} 秒")
        print(f"🤖 [AI回答]:\n{answer}")
    except Exception as e:
        err_str = str(e)
        print(f"\n❌ [调用失败] 抛出异常: {err_str}")
        if "404" in err_str or "not found" in err_str.lower():
            print(f"\n⚠️  严重错误: 未找到模型 '{model_name}'")
            print(f"👉 解决办法: 请在终端运行命令 `ollama pull {model_name}` 下载该模型！")
            answer = f"AI 模型未找到！请在终端运行命令 `ollama pull {model_name}` 下载。"
        else:
            answer = f"AI 引擎调用失败: {err_str}"
        
    # -----------------------------------------
    # 第二步：测试 UDP 回传给 Qt 界面 (默认端口 8080)
    # -----------------------------------------
    print(f"\n[2/3] 📡 准备将回答打包为 UDP 格式并发送至 {target_ip}:{target_port}...")
    reply_payload = f"[AI诊断回复] {answer}"
    
    try:
        resp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        # 将结果发给指定的接收端
        bytes_sent = resp_sock.sendto(reply_payload.encode('utf-8'), (target_ip, target_port))
        resp_sock.close()
        print(f"✅ [发送成功] 已成功向 {target_ip}:{target_port} 发送了 {bytes_sent} 字节的数据。")
    except Exception as e:
        print(f"❌ [发送失败] UDP 异常: {e}")
        return
        
    # -----------------------------------------
    # 第三步：提示 Qt 端验证
    # -----------------------------------------
    print("\n[3/3] 🏁 本次交互流程结束！继续监听下一个问题...")
    print("-"*50)

def start_listening_server(model_name="qwen2.5:0.5b", listen_port=8082, target_port=8080):
    print("="*60)
    print("  [持续监听版] 大模型调用与 UDP 回传独立服务")
    print("="*60)
    print(f"👉 监听端口: {listen_port} (接收 Qt 的提问)")
    print(f"👉 目标模型: {model_name}")
    print(f"👉 回传端口: {target_port} (发送回答给 Qt)")
    print("="*60)
    print("\n提示: 如果服务启动，请确保后台的 `ollama serve` 正在运行。")
    print(f"👂 正在监听 UDP 端口 {listen_port} 等待 Qt 发送问题 (按 Ctrl+C 停止)...\n")
    
    server_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server_sock.bind(('0.0.0.0', listen_port))
    except Exception as e:
        print(f"❌ 端口 {listen_port} 绑定失败: {e}")
        return

    try:
        while True:
            data, addr = server_sock.recvfrom(2048)
            query = data.decode('utf-8', errors='ignore').strip()
            if query:
                print(f"\n📨 收到来自 {addr} 的提问请求！")
                # 收到问题后，调用处理逻辑（这里暂时保持单线程同步处理，因为是简单测试脚本，如果需要也可改为启动子线程）
                process_and_reply(model_name, query, target_ip=addr[0], target_port=target_port)
    except KeyboardInterrupt:
        print("\n\n🛑 收到中断信号，服务已停止。")
    finally:
        server_sock.close()

if __name__ == "__main__":
    # 你可以修改下面这个名字，比如换成 phi3:mini 或 qwen:0.5b
    target_model = "qwen2.5:0.5b" 
    
    start_listening_server(model_name=target_model)
