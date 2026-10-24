"""Listen on a UDP port and print every datagram (source, size, first bytes). Usage: udp_sniff.py <port> <seconds>"""
import socket, sys, time
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(("0.0.0.0", int(sys.argv[1]))); s.settimeout(1)
end = time.time() + float(sys.argv[2]); n = 0
while time.time() < end:
    try:
        d, a = s.recvfrom(65535); n += 1
        if n <= 10: print("pkt", a, len(d), d[:16].hex(), flush=True)
    except socket.timeout:
        pass
print("total packets", n)
