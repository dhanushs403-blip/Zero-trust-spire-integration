import socket
import ssl
import sys
import threading
import time
import os

def run_server():
    try:
        context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        context.verify_mode = ssl.CERT_REQUIRED
        context.load_cert_chain(certfile="svid.0.pem", keyfile="svid.0.key")
        context.load_verify_locations(cafile="bundle.0.pem")

        bindsocket = socket.socket()
        bindsocket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        bindsocket.bind(('localhost', 9999))
        bindsocket.listen(5)
        print("[Server] Secure mTLS Server listening on localhost:9999...")

        newsocket, fromaddr = bindsocket.accept()
        conn = context.wrap_socket(newsocket, server_side=True)
        print(f"[Server] Accepted secure connection from {fromaddr}")
        
        # Verify mTLS: Print Client's Certificate
        peer_cert = conn.getpeercert()
        print(f"\n[Server] ✅ VERIFIED CLIENT IDENTITY:")
        print(f"         Subject: {peer_cert['subject']}")
        print(f"         Issuer:  {peer_cert['issuer']}")
        
        data = conn.recv(1024)
        print(f"[Server] Received message: {data.decode()}")
        conn.send(b"Secure Hello from SPIRE Server!")
        conn.close()
        bindsocket.close()
    except Exception as e:
        print(f"[Server] Error: {e}")

def run_client():
    try:
        # Give server time to start
        time.sleep(2)
        
        context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH)
        context.load_cert_chain(certfile="svid.0.pem", keyfile="svid.0.key")
        context.load_verify_locations(cafile="bundle.0.pem")
        context.check_hostname = False # SPIFFE IDs are URIs, not DNS names

        print("[Client] Connecting to server...")
        conn = context.wrap_socket(socket.socket(socket.AF_INET), server_hostname="localhost")
        conn.connect(('localhost', 9999))
        
        # Verify mTLS: Print Server's Certificate
        peer_cert = conn.getpeercert()
        print(f"\n[Client] ✅ VERIFIED SERVER IDENTITY:")
        print(f"         Subject: {peer_cert['subject']}")
        print(f"         Issuer:  {peer_cert['issuer']}")
        
        print("[Client] Connected! Sending message...")
        conn.send(b"Hello from SPIRE Client!")
        data = conn.recv(1024)
        print(f"[Client] Server Replied: {data.decode()}")
        conn.close()
    except Exception as e:
        print(f"[Client] Error: {e}")

if __name__ == "__main__":
    # Check if certs exist
    if not (os.path.exists("svid.0.pem") and os.path.exists("svid.0.key") and os.path.exists("bundle.0.pem")):
        print("Error: SVID files (svid.0.pem, svid.0.key, bundle.0.pem) not found!")
        sys.exit(1)

    if len(sys.argv) > 1 and sys.argv[1] == "server":
        run_server()
    elif len(sys.argv) > 1 and sys.argv[1] == "client":
        run_client()
    else:
        # Run both in threads for a self-contained demo
        t = threading.Thread(target=run_server)
        t.start()
        run_client()
        t.join()
