# A plain TCP proxy, 127.0.0.1:<listen> -> 127.0.0.1:<target>, used by
# check.sh to imitate a network that stops answering: SIGSTOP freezes
# every connection through it without closing any, SIGCONT resumes.
import socket
import sys
import threading

listen_port, target_port = int(sys.argv[1]), int(sys.argv[2])


def pipe(a, b):
    try:
        while True:
            data = a.recv(65536)
            if not data:
                break
            b.sendall(data)
    except OSError:
        pass
    finally:
        try:
            b.shutdown(socket.SHUT_WR)
        except OSError:
            pass


server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", listen_port))
server.listen(64)
while True:
    client, _ = server.accept()
    upstream = socket.create_connection(("127.0.0.1", target_port))
    threading.Thread(target=pipe, args=(client, upstream), daemon=True).start()
    threading.Thread(target=pipe, args=(upstream, client), daemon=True).start()
