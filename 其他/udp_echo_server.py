import socket

# 服务器IP和端口
HOST = '0.0.0.0'  # 监听所有网络接口
PORT = 50000     # 使用一个自定义端口

# 创建UDP套接字
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
    s.bind((HOST, PORT))
    print(f"UDP Echo Server listening on {HOST}:{PORT}")
    
    while True:
        # 接收数据，data是数据，addr是客户端地址
        data, addr = s.recvfrom(1024)
        print(f"Received message from {addr}: {data.decode()}")
        
        # 将收到的数据原样发回
        s.sendto(data, addr)
