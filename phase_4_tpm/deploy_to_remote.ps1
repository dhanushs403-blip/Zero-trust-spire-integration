param(
    [string]$RemoteUser,
    [string]$RemoteHost,
    [string]$RemotePath = "/home/$RemoteUser/dhanush/phase_4_tpm/"
)

if (-not $RemoteUser -or -not $RemoteHost) {
    Write-Host "Usage: .\deploy_to_remote.ps1 <RemoteUser> <RemoteHost> [RemotePath]"
    exit 1
}

$Files = @(
    "run_tpm_demo.sh",
    "setup_tpm.sh",
    "server.conf.tpm",
    "agent.conf.tpm",
    "verify_tpm.sh",
    "setup_k8s.sh",
    "complete_k8s_setup.sh",
    "fix_cni_manual.sh",
    "mtls_demo.py",
    "Dockerfile",
    "detect_tpm.sh",
    "register_workload_tpm.sh",
    "mtls-app.yaml"
)

Write-Host "Deploying files to $RemoteUser@$RemoteHost`:$RemotePath"

# Create remote directory
ssh $RemoteUser@$RemoteHost "mkdir -p $RemotePath"

foreach ($File in $Files) {
    if (Test-Path $File) {
        Write-Host "Copying $File..."
        scp $File "$RemoteUser@$RemoteHost`:$RemotePath"
    } else {
        Write-Warning "File not found: $File"
    }
}

# Set execute permissions
ssh $RemoteUser@$RemoteHost "chmod +x $RemotePath/*.sh"

Write-Host "Deployment complete."
