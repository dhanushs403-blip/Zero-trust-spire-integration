import socket
import ssl
import sys
import threading
import time
import os
import subprocess

# Configuration
SOCKET_PATH = "/tmp/spire-agent/public/api.sock"
AGENT_BINARY = "/opt/spire/bin/spire-agent"

def fetch_svids():
    print(f"[SPIRE] Fetching SVIDs using {AGENT_BINARY}...")
    try:
        # Explicitly write to /app directory
        cmd = [AGENT_BINARY, "api", "fetch", "x509", "-write", "/app", "-socketPath", SOCKET_PATH]
        subprocess.check_call(cmd)
        print("✅ Successfully ran fetch command.")
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to run spire-agent: {e}")
        return False
    except FileNotFoundError:
        print(f"❌ Could not find binary at {AGENT_BINARY}")
        return False

    # check if files exist
    required_files = ["svid.0.pem", "svid.0.key", "bundle.0.pem"]
    missing = [f for f in required_files if not os.path.exists(f)]
    
    if missing:
        print(f"❌ Error: The following files are missing after fetch: {missing}")
        print(f"📂 Current Directory (/app) contents: {os.listdir('/app')}")
        return False
    
    print("✅ SVID files found on disk.")
    return True

def run_server():
    try:
        context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        context.verify_mode = ssl.CERT_REQUIRED
        context.load_cert_chain(certfile="svid.0.pem", keyfile="svid.0.key")
        context.load_verify_locations(cafile="bundle.0.pem")

        bindsocket = socket.socket()
        bindsocket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        bindsocket.bind(('0.0.0.0', 9999)) # Bind to all interfaces in container
        bindsocket.listen(5)
        print("[Server] Secure mTLS Server listening on 9999...")

        newsocket, fromaddr = bindsocket.accept()
        conn = context.wrap_socket(newsocket, server_side=True)
        print(f"[Server] Accepted secure connection from {fromaddr}")
        
        peer_cert = conn.getpeercert()
        print(f"[Server] ✅ VERIFIED CLIENT IDENTITY: {peer_cert['subject']}")
        
        data = conn.recv(1024)
        print(f"[Server] Received: {data.decode()}")
        conn.send(b"Secure Hello from Docker Server!")
        conn.close()
        bindsocket.close()
    except Exception as e:
        print(f"[Server] Error: {e}")

def run_client():
    try:
        time.sleep(2)
        context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH)
        context.load_cert_chain(certfile="svid.0.pem", keyfile="svid.0.key")
        context.load_verify_locations(cafile="bundle.0.pem")
        context.check_hostname = False

        print("[Client] Connecting to server...")
        conn = context.wrap_socket(socket.socket(socket.AF_INET), server_hostname="localhost")
        conn.connect(('localhost', 9999))
        
        peer_cert = conn.getpeercert()
        print(f"[Client] ✅ VERIFIED SERVER IDENTITY: {peer_cert['subject']}")
        
        conn.send(b"Hello from Docker Client!")
        data = conn.recv(1024)
        print(f"[Client] Server Replied: {data.decode()}")
        conn.close()
    except Exception as e:
        print(f"[Client] Error: {e}")

if __name__ == "__main__":
    if not fetch_svids():
        sys.exit(1)

    # Run both in threads
    t = threading.Thread(target=run_server)
    t.start()
    run_client()
    t.join()