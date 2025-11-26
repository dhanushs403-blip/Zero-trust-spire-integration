import socket
import ssl
import sys
import threading
import time
import os
import subprocess

def fetch_svids():
    """Fetch SVIDs from SPIRE Agent before running the demo"""
    print("[SPIRE] Fetching SVIDs from SPIRE Agent...")
    
    # Check if spire-agent is available
    if not os.path.exists("/opt/spire/bin/spire-agent"):
        print("Error: spire-agent binary not found at /opt/spire/bin/spire-agent")
        return False
    
    # Check if socket exists
    if not os.path.exists("/tmp/spire-agent/public/api.sock"):
        print("Error: SPIRE Agent socket not found at /tmp/spire-agent/public/api.sock")
        return False
    
    try:
        # Fetch X.509 SVID and write to disk
        result = subprocess.run(
            ["/opt/spire/bin/spire-agent", "api", "fetch", "x509", "-write", "/app"],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode != 0:
            print(f"Error fetching SVID: {result.stderr}")
            return False
            
        print(result.stdout)
        return True
        
    except subprocess.TimeoutExpired:
        print("Error: Timeout while fetching SVID")
        return False
    except Exception as e:
        print(f"Error during SVID fetch: {e}")
        return False

def run_server():
    try:
        context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        context.verify_mode = ssl.CERT_REQUIRED
        context.load_cert_chain(certfile="svid.0.pem", keyfile="svid.0.key")
        context.load_verify_locations(cafile="bundle.0.pem")

        bindsocket = socket.socket()
        bindsocket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        bindsocket.bind(('0.0.0.0', 9999))
        bindsocket.listen(5)
        print("[Server] Secure mTLS Server listening on 0.0.0.0:9999...")

        while True:
            try:
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
            except Exception as e:
                print(f"[Server] Connection error: {e}")

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
    # First, fetch SVIDs from SPIRE Agent
    print("=" * 50)
    print("SPIRE Docker mTLS Demo")
    print("=" * 50)
    
    if not fetch_svids():
        print("\n❌ Failed to fetch SVIDs from SPIRE Agent")
        print("Make sure:")
        print("  1. SPIRE Agent is running and healthy")
        print("  2. This workload is registered with correct selectors")
        print("  3. Agent socket is mounted at /tmp/spire-agent/public/api.sock")
        sys.exit(1)
    
    print("\n✅ Successfully fetched SVIDs!\n")
    
    # Verify files exist
    if not (os.path.exists("svid.0.pem") and os.path.exists("svid.0.key") and os.path.exists("bundle.0.pem")):
        print("Error: SVID files were fetched but not found on disk!")
        sys.exit(1)

    print("=" * 50)
    print("Starting mTLS Demo...")
    print("=" * 50)
    print()
    
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
    
    print("\n" + "=" * 50)
    print("✅ Demo completed successfully!")
    print("=" * 50)
