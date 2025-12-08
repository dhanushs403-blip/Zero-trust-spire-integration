import socket
import ssl
import sys
import threading
import time
import os
import subprocess

def check_tpm_attestation():
    """Check if SPIRE Agent is using TPM attestation"""
    try:
        # Query the agent's attestation info
        result = subprocess.run(
            ["/opt/spire/bin/spire-agent", "api", "fetch", "x509", "-socketPath", "/tmp/spire-agent/public/api.sock"],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        # Check if the output contains TPM-related information
        if "tpm" in result.stdout.lower() or "tpm" in result.stderr.lower():
            return True
            
        # Alternative: Check agent's parent ID via server query
        # This would require server access, so we'll rely on the fetch output
        return False
        
    except Exception as e:
        print(f"[TPM] Warning: Could not verify TPM attestation status: {e}")
        return False

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
        # Fetch X.509 SVID and write to disk (current directory)
        current_dir = os.getcwd()
        result = subprocess.run(
            ["/opt/spire/bin/spire-agent", "api", "fetch", "x509", "-write", current_dir],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode != 0:
            print(f"\n❌ Error fetching SVID from SPIRE Agent")
            print(f"Return code: {result.returncode}")
            
            # Check for PCR mismatch errors in stderr
            stderr_lower = result.stderr.lower()
            if "pcr" in stderr_lower or "mismatch" in stderr_lower or "permission denied" in stderr_lower:
                print("\n" + "="*60)
                print("   TPM PCR MISMATCH DETECTED")
                print("="*60)
                print("\nThe SPIRE Agent denied the SVID request due to a PCR mismatch.")
                print("This indicates that the system's TPM measurements have changed")
                print("since the workload was registered.")
                print("\nError details:")
                print(result.stderr)
                print("\n" + "="*60)
                print("TROUBLESHOOTING STEPS:")
                print("="*60)
                print("\n1. Check current TPM PCR values:")
                print("   tpm2_pcrread sha256")
                print("\n2. View workload registration:")
                print("   sudo /opt/spire/bin/spire-server entry show")
                print("\n3. Validate PCR match:")
                print("   sudo ./validate_pcr_match.sh --spiffe-id <your-spiffe-id>")
                print("\n4. If system changes are legitimate, update registration:")
                print("   a. Read current PCR value for the registered index")
                print("   b. Delete old registration:")
                print("      sudo /opt/spire/bin/spire-server entry delete -spiffeID <id>")
                print("   c. Register with new PCR value:")
                print("      sudo ./register_workload_tpm.sh --spiffe-id <id> \\")
                print("           --pcr-index <index> --pcr-hash <new_hash>")
                print("\n5. Common causes of PCR changes:")
                print("   - Firmware or BIOS updates")
                print("   - Bootloader changes")
                print("   - Kernel or initramfs updates")
                print("   - Secure Boot configuration changes")
                print("   - TPM has been cleared or reset")
                print("\n" + "="*60)
            else:
                print(f"\nError output:\n{result.stderr}")
            
            return False
            
        print(result.stdout)
        
        # Check for TPM attestation
        tpm_active = check_tpm_attestation()
        if tpm_active:
            print("\n[TPM] ✅ TPM Attestation is ACTIVE")
            print("[TPM] SVIDs are backed by hardware security")
        else:
            print("\n[TPM] ℹ️  TPM Attestation status: Not detected")
            print("[TPM] Using standard attestation method")
        
        return True
        
    except subprocess.TimeoutExpired:
        print("Error: Timeout while fetching SVID")
        return False
    except Exception as e:
        print(f"Error during SVID fetch: {e}")
        return False

def extract_spiffe_id(cert):
    """Extract SPIFFE ID from certificate's Subject Alternative Name"""
    try:
        if 'subjectAltName' in cert:
            for alt_name_type, alt_name_value in cert['subjectAltName']:
                if alt_name_type == 'URI' and alt_name_value.startswith('spiffe://'):
                    return alt_name_value
        return None
    except Exception as e:
        print(f"Warning: Could not extract SPIFFE ID: {e}")
        return None

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
                client_spiffe_id = extract_spiffe_id(peer_cert)
                
                print(f"\n[Server] ✅ VERIFIED CLIENT IDENTITY:")
                print(f"         Subject: {peer_cert['subject']}")
                print(f"         Issuer:  {peer_cert['issuer']}")
                if client_spiffe_id:
                    print(f"         SPIFFE ID: {client_spiffe_id}")
                
                # Log server's own identity
                server_cert_file = "svid.0.pem"
                if os.path.exists(server_cert_file):
                    with open(server_cert_file, 'rb') as f:
                        from cryptography import x509
                        from cryptography.hazmat.backends import default_backend
                        server_cert_data = x509.load_pem_x509_certificate(f.read(), default_backend())
                        server_spiffe_id = None
                        try:
                            san_ext = server_cert_data.extensions.get_extension_for_oid(
                                x509.oid.ExtensionOID.SUBJECT_ALTERNATIVE_NAME
                            )
                            for name in san_ext.value:
                                if isinstance(name, x509.UniformResourceIdentifier):
                                    if name.value.startswith('spiffe://'):
                                        server_spiffe_id = name.value
                                        break
                        except:
                            pass
                        
                        if server_spiffe_id:
                            print(f"[Server] Server SPIFFE ID: {server_spiffe_id}")
                
                print(f"[mTLS] ✅ Mutual TLS handshake successful")
                if client_spiffe_id:
                    print(f"[mTLS] Client identity: {client_spiffe_id}")
                
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
        server_spiffe_id = extract_spiffe_id(peer_cert)
        
        print(f"\n[Client] ✅ VERIFIED SERVER IDENTITY:")
        print(f"         Subject: {peer_cert['subject']}")
        print(f"         Issuer:  {peer_cert['issuer']}")
        if server_spiffe_id:
            print(f"         SPIFFE ID: {server_spiffe_id}")
        
        # Log client's own identity
        client_cert_file = "svid.0.pem"
        if os.path.exists(client_cert_file):
            with open(client_cert_file, 'rb') as f:
                from cryptography import x509
                from cryptography.hazmat.backends import default_backend
                client_cert_data = x509.load_pem_x509_certificate(f.read(), default_backend())
                client_spiffe_id = None
                try:
                    san_ext = client_cert_data.extensions.get_extension_for_oid(
                        x509.oid.ExtensionOID.SUBJECT_ALTERNATIVE_NAME
                    )
                    for name in san_ext.value:
                        if isinstance(name, x509.UniformResourceIdentifier):
                            if name.value.startswith('spiffe://'):
                                client_spiffe_id = name.value
                                break
                except:
                    pass
                
                if client_spiffe_id:
                    print(f"[Client] Client SPIFFE ID: {client_spiffe_id}")
        
        print(f"[mTLS] ✅ Mutual TLS handshake successful")
        if server_spiffe_id:
            print(f"[mTLS] Server identity: {server_spiffe_id}")
        
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
    print("SPIRE TPM-Attested mTLS Demo")
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
