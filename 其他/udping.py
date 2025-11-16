import socket
import time
import argparse
import sys
from collections import namedtuple

# 定义一个具名元组来存储每次ping的结果
PingResult = namedtuple('PingResult', ['sent', 'received', 'rtt'])

def print_statistics(host, port, results):
    """
    打印Ping的统计信息。
    """
    if not results:
        return

    packets_sent = len(results)
    packets_received = sum(1 for r in results if r.received)
    packets_lost = packets_sent - packets_received
    loss_percentage = (packets_lost / packets_sent) * 100 if packets_sent > 0 else 0

    rtts = [r.rtt for r in results if r.received]
    min_rtt = min(rtts) if rtts else 0
    max_rtt = max(rtts) if rtts else 0
    avg_rtt = sum(rtts) / len(rtts) if rtts else 0

    print(f"\n--- {host}:{port} ping statistics ---")
    print(f"{packets_sent} packets transmitted, {packets_received} received, {loss_percentage:.1f}% packet loss")
    if rtts:
        print(f"round-trip min/avg/max = {min_rtt:.2f}/{avg_rtt:.2f}/{max_rtt:.2f} ms")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="UDP Ping tool similar to tcping.")
    parser.add_argument("host", help="The destination host.")
    parser.add_argument("port", type=int, help="The destination port.")
    parser.add_argument("-c", "--count", type=int, default=4, help="Number of packets to send (ignored if -t is used).")
    parser.add_argument("-t", action="store_true", help="Ping the specified host until stopped (Ctrl+C).")
    parser.add_argument("-w", "--timeout", type=float, default=1.0, help="Wait timeout in seconds for each reply.")
    
    # ===================================================================
    # == 这里是定义包大小参数的地方
    # ===================================================================
    parser.add_argument("-s", "--size", type=int, default=64, help="Size of the packet data in bytes.")
    
    args = parser.parse_args()
    
    all_results = []
    try:
        client_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        client_socket.settimeout(args.timeout)

        # ===================================================================
        # == 这里是使用指定的包大小来创建数据包的地方
        # ===================================================================
        payload = b'x' * args.size

        print(f"Pinging {args.host}:{args.port} with {args.size} bytes of data:")
        if args.t:
            print("Press Ctrl+C to stop.")

        i = 0
        while args.t or i < args.count:
            send_time = 0
            rtt = 0
            received = False

            try:
                send_time = time.time()
                client_socket.sendto(payload, (args.host, args.port))
                data, addr = client_socket.recvfrom(1024 + args.size) # 缓冲区要足够大
                recv_time = time.time()
                rtt = (recv_time - send_time) * 1000
                received = True
                print(f"Reply from {addr[0]}:{addr[1]}, RTT = {rtt:.2f}ms")
            except socket.timeout:
                print("Request timed out.")
            
            all_results.append(PingResult(sent=True, received=received, rtt=rtt))
            time.sleep(1)
            
            if not args.t:
                i += 1

    except socket.gaierror:
        print(f"\nError: Hostname '{args.host}' could not be resolved.")
    except PermissionError:
        print("\nPermission denied. You might need to run this script with sudo or as an administrator.")
    except KeyboardInterrupt:
        print("\nPing stopped by user.")
    finally:
        print_statistics(args.host, args.port, all_results)
        sys.exit(0)
