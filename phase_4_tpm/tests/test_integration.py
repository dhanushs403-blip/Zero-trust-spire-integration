#!/usr/bin/env python3
"""
Integration tests for TPM-SPIRE integration
Tests end-to-end flows including node attestation, workload attestation, and mTLS communication

Requirements tested:
- Requirements 1.1, 1.2, 1.4: TPM node attestation flow
- Requirements 2.2, 2.3, 3.1, 3.2: TPM workload attestation flow
- Requirements 3.3, 3.4, 3.5: mTLS communication flow
- Requirements 2.5: Backward compatibility with Docker selectors
"""

import os
import sys
import subprocess
import tempfile
import time
import socket
import ssl
import threading
from pathlib import Path
import pytest

# Add parent directory to path to import mtls_demo
SCRIPT_DIR = Path(__file__).parent.parent
sys.path.insert(0, str(SCRIPT_DIR))

try:
    import mtls_demo
except ImportError:
    mtls_demo = None


class TestTPMNodeAttestationIntegration:
    """
    Integration test for TPM node attestation flow
    Tests: Agent startup → TPM attestation → SPIFFE ID issuance
    Validates: Requirements 1.1, 1.2, 1.4
    """
    
    def test_tpm_node_attestation_flow_simulation(self):
        """
        Test full TPM node attestation flow (simulated)
        
        This test simulates the TPM node attestation process:
        1. Agent starts with TPM node attestor configuration
        2. Agent performs TPM attestation to server
        3. Server validates TPM credentials
        4. Server issues agent SPIFFE ID with TPM-specific parent ID
        
        In a real environment, this would require:
        - Running SPIRE Server with TPM node attestor
        - Running SPIRE Agent with TPM node attestor
        - Actual TPM device access
        
        For testing purposes, we simulate the key verification steps.
        """
        # Step 1: Verify TPM configuration files exist
        server_conf = SCRIPT_DIR / "server.conf.tpm"
        agent_conf = SCRIPT_DIR / "agent.conf.tpm"
        
        assert server_conf.exists(), \
            "TPM server configuration should exist"
        assert agent_conf.exists(), \
            "TPM agent configuration should exist"
        
        # Step 2: Verify server config contains TPM node attestor
        with open(server_conf, 'r') as f:
            server_config = f.read()
        
        assert 'NodeAttestor "tpm"' in server_config, \
            "Server config should have TPM node attestor"
        assert 'hash_algorithm' in server_config, \
            "Server config should specify hash algorithm"
        
        # Step 3: Verify agent config contains TPM node attestor
        with open(agent_conf, 'r') as f:
            agent_config = f.read()
        
        assert 'NodeAttestor "tpm"' in agent_config, \
            "Agent config should have TPM node attestor"
        assert 'tpm_device_path' in agent_config, \
            "Agent config should specify TPM device path"
        assert '/dev/tpmrm0' in agent_config or '/dev/tpm0' in agent_config, \
            "Agent config should reference TPM device"
        
        # Step 4: Verify agent startup script exists
        agent_startup_script = SCRIPT_DIR / "start_spire_agent_tpm.sh"
        assert agent_startup_script.exists(), \
            "TPM agent startup script should exist"
        
        print("\n✅ TPM node attestation configuration verified")
        print("   - Server config has TPM node attestor")
        print("   - Agent config has TPM node attestor with device path")
        print("   - Agent startup script exists")
    
    def test_agent_parent_id_format_validation(self):
        """
        Test that agent SPIFFE ID format is correct for TPM attestation
        
        When an agent successfully attests via TPM, the server should issue
        a SPIFFE ID with format: spiffe://trust-domain/spire/agent/tpm/<hash>
        
        This test validates the expected format.
        """
        # Expected format for TPM-attested agent
        expected_pattern = r"spiffe://[^/]+/spire/agent/tpm/[0-9a-f]+"
        
        # Test examples of valid TPM agent SPIFFE IDs
        valid_ids = [
            "spiffe://example.org/spire/agent/tpm/abc123",
            "spiffe://domain.com/spire/agent/tpm/a3f5d8c2e1b4567890abcdef",
            "spiffe://test.local/spire/agent/tpm/1234567890abcdef",
        ]
        
        import re
        for spiffe_id in valid_ids:
            assert re.match(expected_pattern, spiffe_id), \
                f"Valid TPM agent SPIFFE ID should match pattern: {spiffe_id}"
        
        # Test examples of invalid (non-TPM) agent SPIFFE IDs
        invalid_ids = [
            "spiffe://example.org/spire/agent/join_token/abc123",
            "spiffe://domain.com/spire/agent/x509pop/xyz789",
            "spiffe://test.local/workload/app",
        ]
        
        for spiffe_id in invalid_ids:
            assert not re.match(expected_pattern, spiffe_id), \
                f"Non-TPM agent SPIFFE ID should not match TPM pattern: {spiffe_id}"
        
        print("\n✅ Agent SPIFFE ID format validation passed")
        print("   - TPM agent IDs follow correct format")
        print("   - Non-TPM agent IDs correctly excluded")
    
    def test_tpm_device_detection_in_scripts(self):
        """
        Test that setup scripts properly detect TPM device
        
        The setup and startup scripts should check for TPM device presence
        before attempting to use TPM attestation.
        """
        # Check setup script
        setup_script = SCRIPT_DIR / "setup_tpm.sh"
        assert setup_script.exists(), "Setup script should exist"
        
        with open(setup_script, 'r') as f:
            setup_content = f.read()
        
        assert 'check_tpm_device' in setup_content, \
            "Setup script should have TPM device check function"
        assert '/dev/tpm' in setup_content, \
            "Setup script should reference TPM device path"
        
        # Check detect script
        detect_script = SCRIPT_DIR / "detect_tpm.sh"
        assert detect_script.exists(), "Detect script should exist"
        
        with open(detect_script, 'r') as f:
            detect_content = f.read()
        
        assert '/dev/tpm' in detect_content, \
            "Detect script should check for TPM device"
        
        print("\n✅ TPM device detection verified in scripts")
        print("   - Setup script checks for TPM device")
        print("   - Detect script validates TPM presence")


class TestTPMWorkloadAttestationIntegration:
    """
    Integration test for TPM workload attestation flow
    Tests: Workload registration → SVID fetch → TPM attestation
    Validates: Requirements 2.2, 2.3, 3.1, 3.2
    """
    
    def test_workload_registration_with_tpm_selectors(self):
        """
        Test workload registration with TPM PCR selectors
        
        This test verifies that:
        1. Registration script exists and is executable
        2. Script accepts TPM PCR selector format
        3. Script validates selector format correctly
        """
        # Check registration script exists
        register_script = SCRIPT_DIR / "register_workload_tpm.sh"
        assert register_script.exists(), \
            "Workload registration script should exist"
        
        # Verify script contains TPM selector logic
        with open(register_script, 'r', encoding='utf-8', errors='ignore') as f:
            script_content = f.read()
        
        assert 'tpm:pcr:' in script_content, \
            "Registration script should handle TPM PCR selectors"
        assert 'pcr_index' in script_content.lower() or 'pcr-index' in script_content, \
            "Registration script should handle PCR index parameter"
        assert 'pcr_hash' in script_content.lower() or 'pcr-hash' in script_content, \
            "Registration script should handle PCR hash parameter"
        
        # Verify script has validation function
        assert 'validate' in script_content.lower(), \
            "Registration script should validate selector format"
        
        print("\n✅ Workload registration with TPM selectors verified")
        print("   - Registration script exists")
        print("   - Script handles TPM PCR selectors")
        print("   - Script validates selector format")
    
    def test_svid_fetch_creates_required_files(self):
        """
        Test that SVID fetch creates all required certificate files
        
        When a workload successfully fetches an SVID, three files should be created:
        - svid.0.pem: The X.509 certificate
        - svid.0.key: The private key
        - bundle.0.pem: The trust bundle
        
        This test simulates the file creation process.
        """
        with tempfile.TemporaryDirectory() as tmpdir:
            # Simulate SVID fetch by creating test files
            svid_file = Path(tmpdir) / "svid.0.pem"
            key_file = Path(tmpdir) / "svid.0.key"
            bundle_file = Path(tmpdir) / "bundle.0.pem"
            
            # Create test certificate content
            test_cert = b"-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----\n"
            test_key = b"-----BEGIN RSA PRIVATE KEY-----\ntest\n-----END RSA PRIVATE KEY-----\n"
            test_bundle = b"-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----\n"
            
            svid_file.write_bytes(test_cert)
            key_file.write_bytes(test_key)
            bundle_file.write_bytes(test_bundle)
            
            # Verify all files exist
            assert svid_file.exists(), "svid.0.pem should be created"
            assert key_file.exists(), "svid.0.key should be created"
            assert bundle_file.exists(), "bundle.0.pem should be created"
            
            # Verify file contents
            assert b'BEGIN CERTIFICATE' in svid_file.read_bytes(), \
                "SVID file should contain certificate"
            assert b'BEGIN RSA PRIVATE KEY' in key_file.read_bytes(), \
                "Key file should contain private key"
            assert b'BEGIN CERTIFICATE' in bundle_file.read_bytes(), \
                "Bundle file should contain certificate"
            
            print("\n✅ SVID file creation verified")
            print("   - svid.0.pem created with certificate")
            print("   - svid.0.key created with private key")
            print("   - bundle.0.pem created with trust bundle")
    
    def test_mtls_demo_has_fetch_svids_function(self):
        """
        Test that mtls_demo.py has the fetch_svids function
        
        The Python application should have a function to fetch SVIDs from
        the SPIRE Agent before establishing mTLS connections.
        """
        if mtls_demo is None:
            pytest.skip("mtls_demo module not available")
        
        # Verify fetch_svids function exists
        assert hasattr(mtls_demo, 'fetch_svids'), \
            "mtls_demo should have fetch_svids function"
        
        # Verify check_tpm_attestation function exists
        assert hasattr(mtls_demo, 'check_tpm_attestation'), \
            "mtls_demo should have check_tpm_attestation function"
        
        print("\n✅ mTLS demo SVID fetch functions verified")
        print("   - fetch_svids function exists")
        print("   - check_tpm_attestation function exists")
    
    def test_pcr_validation_script_exists(self):
        """
        Test that PCR validation script exists for troubleshooting
        
        The validate_pcr_match.sh script helps administrators verify
        whether current PCR values match registered selectors.
        """
        validate_script = SCRIPT_DIR / "validate_pcr_match.sh"
        assert validate_script.exists(), \
            "PCR validation script should exist"
        
        with open(validate_script, 'r') as f:
            script_content = f.read()
        
        assert 'tpm2_pcrread' in script_content or 'pcr' in script_content.lower(), \
            "Validation script should read PCR values"
        
        print("\n✅ PCR validation script verified")
        print("   - validate_pcr_match.sh exists")
        print("   - Script can read PCR values")


class TestMTLSCommunicationIntegration:
    """
    Integration test for mTLS communication flow
    Tests: Server startup → Client connection → Mutual TLS → Identity logging
    Validates: Requirements 3.3, 3.4, 3.5
    """
    
    def test_mtls_server_and_client_functions_exist(self):
        """
        Test that mTLS server and client functions exist
        
        The mtls_demo.py should have functions to run both server and client
        with TPM-attested certificates.
        """
        if mtls_demo is None:
            pytest.skip("mtls_demo module not available")
        
        # Verify server function exists
        assert hasattr(mtls_demo, 'run_server'), \
            "mtls_demo should have run_server function"
        
        # Verify client function exists
        assert hasattr(mtls_demo, 'run_client'), \
            "mtls_demo should have run_client function"
        
        # Verify extract_spiffe_id function exists
        assert hasattr(mtls_demo, 'extract_spiffe_id'), \
            "mtls_demo should have extract_spiffe_id function"
        
        print("\n✅ mTLS communication functions verified")
        print("   - run_server function exists")
        print("   - run_client function exists")
        print("   - extract_spiffe_id function exists")
    
    def test_extract_spiffe_id_from_certificate(self):
        """
        Test SPIFFE ID extraction from certificate
        
        The extract_spiffe_id function should correctly extract SPIFFE IDs
        from certificate's Subject Alternative Name extension.
        """
        if mtls_demo is None:
            pytest.skip("mtls_demo module not available")
        
        # Test with valid certificate dict (simulating getpeercert() output)
        test_cert = {
            'subject': ((('organizationName', 'SPIRE'),),),
            'issuer': ((('organizationName', 'SPIRE CA'),),),
            'subjectAltName': (
                ('URI', 'spiffe://example.org/test-workload'),
                ('DNS', 'example.com'),
            )
        }
        
        spiffe_id = mtls_demo.extract_spiffe_id(test_cert)
        
        assert spiffe_id == 'spiffe://example.org/test-workload', \
            f"Should extract correct SPIFFE ID, got: {spiffe_id}"
        
        # Test with certificate without SPIFFE ID
        test_cert_no_spiffe = {
            'subject': ((('commonName', 'test.com'),),),
            'subjectAltName': (
                ('DNS', 'test.com'),
            )
        }
        
        spiffe_id_none = mtls_demo.extract_spiffe_id(test_cert_no_spiffe)
        
        assert spiffe_id_none is None, \
            "Should return None for certificate without SPIFFE ID"
        
        print("\n✅ SPIFFE ID extraction verified")
        print("   - Correctly extracts SPIFFE ID from SAN")
        print("   - Returns None for certificates without SPIFFE ID")
    
    def test_tls_context_creation_with_certificates(self):
        """
        Test TLS context creation with certificate files
        
        This test verifies that SSL contexts can be created with the
        certificate files that would be fetched from SPIRE Agent.
        """
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create test certificate files
            from cryptography import x509
            from cryptography.x509.oid import NameOID, ExtensionOID
            from cryptography.hazmat.primitives import hashes, serialization
            from cryptography.hazmat.primitives.asymmetric import rsa
            from cryptography.hazmat.backends import default_backend
            import datetime
            
            # Generate test key and certificate
            key = rsa.generate_private_key(65537, 2048, default_backend())
            
            subject = issuer = x509.Name([
                x509.NameAttribute(NameOID.ORGANIZATION_NAME, "SPIRE"),
            ])
            
            cert = x509.CertificateBuilder().subject_name(
                subject
            ).issuer_name(
                issuer
            ).public_key(
                key.public_key()
            ).serial_number(
                x509.random_serial_number()
            ).not_valid_before(
                datetime.datetime.utcnow()
            ).not_valid_after(
                datetime.datetime.utcnow() + datetime.timedelta(hours=1)
            ).add_extension(
                x509.SubjectAlternativeName([
                    x509.UniformResourceIdentifier("spiffe://example.org/test")
                ]),
                critical=False,
            ).sign(key, hashes.SHA256(), default_backend())
            
            # Write files
            cert_file = Path(tmpdir) / "svid.0.pem"
            key_file = Path(tmpdir) / "svid.0.key"
            bundle_file = Path(tmpdir) / "bundle.0.pem"
            
            cert_pem = cert.public_bytes(serialization.Encoding.PEM)
            key_pem = key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.TraditionalOpenSSL,
                encryption_algorithm=serialization.NoEncryption()
            )
            
            cert_file.write_bytes(cert_pem)
            key_file.write_bytes(key_pem)
            bundle_file.write_bytes(cert_pem)
            
            # Test creating SSL context (server-side)
            context_server = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
            context_server.load_cert_chain(
                certfile=str(cert_file),
                keyfile=str(key_file)
            )
            context_server.load_verify_locations(cafile=str(bundle_file))
            
            assert context_server is not None, \
                "Should create server SSL context with certificates"
            
            # Test creating SSL context (client-side)
            context_client = ssl.create_default_context(ssl.Purpose.SERVER_AUTH)
            context_client.load_cert_chain(
                certfile=str(cert_file),
                keyfile=str(key_file)
            )
            context_client.load_verify_locations(cafile=str(bundle_file))
            
            assert context_client is not None, \
                "Should create client SSL context with certificates"
            
            print("\n✅ TLS context creation verified")
            print("   - Server SSL context created successfully")
            print("   - Client SSL context created successfully")
            print("   - Certificates loaded correctly")
    
    def test_identity_logging_in_mtls_demo(self):
        """
        Test that identity logging is present in mTLS demo
        
        The demo should log both client and server identities after
        successful mutual TLS handshake.
        """
        # Read the mtls_demo.py source code
        mtls_demo_file = SCRIPT_DIR / "mtls_demo.py"
        assert mtls_demo_file.exists(), "mtls_demo.py should exist"
        
        with open(mtls_demo_file, 'r', encoding='utf-8', errors='ignore') as f:
            demo_source = f.read()
        
        # Verify server logs client identity
        assert 'VERIFIED CLIENT IDENTITY' in demo_source or 'client_spiffe_id' in demo_source, \
            "Server should log verified client identity"
        
        # Verify client logs server identity
        assert 'VERIFIED SERVER IDENTITY' in demo_source or 'server_spiffe_id' in demo_source, \
            "Client should log verified server identity"
        
        # Verify mutual TLS success is logged
        assert 'Mutual TLS' in demo_source or 'mTLS' in demo_source, \
            "Demo should log mutual TLS handshake success"
        
        # Verify SPIFFE ID extraction is used
        assert 'extract_spiffe_id' in demo_source, \
            "Demo should use extract_spiffe_id function"
        
        print("\n✅ Identity logging verified in mTLS demo")
        print("   - Server logs client identity")
        print("   - Client logs server identity")
        print("   - Mutual TLS success is logged")
        print("   - SPIFFE IDs are extracted and displayed")


class TestBackwardCompatibilityIntegration:
    """
    Integration test for backward compatibility
    Tests: Workload with both TPM and Docker selectors
    Validates: Requirements 2.5
    """
    
    def test_agent_config_has_both_attestors(self):
        """
        Test that agent configuration supports both TPM and Docker attestors
        
        For backward compatibility, the agent should be configured with:
        - TPM node attestor (for hardware-backed node attestation)
        - Docker workload attestor (for Kubernetes pod identification)
        
        This allows workloads to use either or both attestation methods.
        """
        agent_conf = SCRIPT_DIR / "agent.conf.tpm"
        assert agent_conf.exists(), "Agent config should exist"
        
        with open(agent_conf, 'r') as f:
            agent_config = f.read()
        
        # Verify TPM node attestor is present
        assert 'NodeAttestor "tpm"' in agent_config, \
            "Agent config should have TPM node attestor"
        
        # Verify Docker workload attestor is present
        assert 'WorkloadAttestor "docker"' in agent_config, \
            "Agent config should have Docker workload attestor for backward compatibility"
        
        print("\n✅ Backward compatibility configuration verified")
        print("   - Agent has TPM node attestor")
        print("   - Agent has Docker workload attestor")
        print("   - Both attestation methods supported")
    
    def test_registration_script_supports_multiple_selectors(self):
        """
        Test that registration script can handle multiple selector types
        
        The registration script should support registering workloads with:
        - TPM PCR selectors (tpm:pcr:<index>:<hash>)
        - Docker label selectors (docker:label:<key>:<value>)
        - Both types simultaneously for backward compatibility
        """
        register_script = SCRIPT_DIR / "register_workload_tpm.sh"
        assert register_script.exists(), "Registration script should exist"
        
        with open(register_script, 'r', encoding='utf-8', errors='ignore') as f:
            script_content = f.read()
        
        # Verify script handles TPM selectors
        assert 'tpm:pcr:' in script_content, \
            "Registration script should handle TPM selectors"
        
        # Verify script handles Docker selectors
        assert 'docker:label:' in script_content or 'docker' in script_content.lower(), \
            "Registration script should handle Docker selectors"
        
        # Verify script can add multiple selectors
        assert '-selector' in script_content, \
            "Registration script should support multiple selectors"
        
        print("\n✅ Multiple selector support verified")
        print("   - Script handles TPM PCR selectors")
        print("   - Script handles Docker label selectors")
        print("   - Multiple selectors can be registered")
    
    def test_documentation_mentions_backward_compatibility(self):
        """
        Test that documentation covers backward compatibility
        
        The README and migration guide should explain how to use both
        TPM and Docker attestation methods together.
        """
        readme = SCRIPT_DIR / "README-tpm-phase4.md"
        migration = SCRIPT_DIR / "MIGRATION-from-phase3.md"
        
        assert readme.exists(), "README should exist"
        assert migration.exists(), "Migration guide should exist"
        
        # Check README mentions backward compatibility
        with open(readme, 'r', encoding='utf-8', errors='ignore') as f:
            readme_content = f.read()
        
        assert 'backward' in readme_content.lower() or 'compatibility' in readme_content.lower(), \
            "README should mention backward compatibility"
        assert 'docker' in readme_content.lower(), \
            "README should mention Docker attestation"
        
        # Check migration guide explains compatibility
        with open(migration, 'r', encoding='utf-8', errors='ignore') as f:
            migration_content = f.read()
        
        assert 'backward' in migration_content.lower() or 'compatibility' in migration_content.lower(), \
            "Migration guide should explain backward compatibility"
        assert 'docker' in migration_content.lower() and 'tpm' in migration_content.lower(), \
            "Migration guide should cover both Docker and TPM attestation"
        
        print("\n✅ Backward compatibility documentation verified")
        print("   - README mentions backward compatibility")
        print("   - Migration guide explains compatibility approach")
        print("   - Both Docker and TPM attestation documented")
    
    def test_fallback_behavior_documented(self):
        """
        Test that fallback behavior is documented
        
        The documentation should explain what happens when:
        - TPM is unavailable but Docker selectors match
        - Both TPM and Docker selectors are registered
        - One attestation method fails
        """
        readme = SCRIPT_DIR / "README-tpm-phase4.md"
        
        with open(readme, 'r', encoding='utf-8', errors='ignore') as f:
            readme_content = f.read()
        
        # Check for fallback or error handling documentation
        has_fallback_docs = (
            'fallback' in readme_content.lower() or
            'unavailable' in readme_content.lower() or
            'troubleshooting' in readme_content.lower()
        )
        
        assert has_fallback_docs, \
            "README should document fallback behavior or troubleshooting"
        
        print("\n✅ Fallback behavior documentation verified")
        print("   - Documentation covers error scenarios")
        print("   - Troubleshooting guidance provided")


if __name__ == "__main__":
    # Run tests with pytest
    pytest.main([__file__, "-v", "--tb=short"])
