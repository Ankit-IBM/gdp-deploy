"""S-TAP installation dispatcher: SSH (Linux), WinRM (Windows), GIM.

If the user declines automated installation, the module prints exact
manual one-liner commands they can copy-paste to install S-TAP themselves.
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from typing import Optional

LOG = logging.getLogger(__name__)

STAP_PORT       = 8075
GIM_PORT        = 8082
APPLIANCE_SSH_PORT = 16022

# ── Manual one-liner helpers ──────────────────────────────────────────────────

def print_manual_oneliner(
    *,
    method: str,
    db_host: str,
    guardium_collector_ip: str,
    guardium_version: str = "12.2",
    db_ssh_user: str = "root",
    db_type: str = "all",
    gim_server_url: str = "",
    gim_username: str = "admin",
    stap_rpm_path: str = "/tmp/guard-stap.rpm",
    stap_msi_path: str = r"C:\Windows\Temp\guard-stap.msi",
) -> None:
    """Print the exact manual command(s) for the chosen method."""
    SEP = "=" * 72

    if method == "ssh":
        print(f"""
{SEP}
  MANUAL S-TAP INSTALL — SSH (Linux/Unix)
  Target DB server : {db_host}
  Guardium version : {guardium_version}
  Collector IP     : {guardium_collector_ip}
{SEP}

# Step 1 – Copy the S-TAP RPM from the Guardium Collector appliance
scp -o StrictHostKeyChecking=no -P {APPLIANCE_SSH_PORT} \\
    cli@{guardium_collector_ip}:/var/IBM/Guardium/stap/guard-stap-{guardium_version}-linux-x86-64.rpm \\
    {stap_rpm_path}

# Step 2 – Install on the DB server (run as root)
ssh {db_ssh_user}@{db_host} \\
  "rpm -Uvh {stap_rpm_path} && \\
   printf 'TAP_IP={guardium_collector_ip}\\nGUARD_PORT={STAP_PORT}\\nDB_TYPE={db_type}\\nINSPECTION_ENGINE_COUNT=1\\nSTAP_ENABLED=1\\n' > /etc/sysconfig/guard.conf && \\
   systemctl enable guard-stap && systemctl restart guard-stap"

# Step 3 – Verify the S-TAP is connected
ssh {db_ssh_user}@{db_host} "systemctl status guard-stap"
{SEP}
""")

    elif method == "winrm":
        print(f"""
{SEP}
  MANUAL S-TAP INSTALL — Windows (msiexec)
  Target DB server : {db_host}
  Guardium version : {guardium_version}
  Collector IP     : {guardium_collector_ip}
{SEP}

# Run from PowerShell on the DB server (as Administrator)

# Step 1 – Copy the MSI to the target (run from your jump box):
Copy-Item -Path "{stap_msi_path}" -Destination "\\\\{db_host}\\C$\\Windows\\Temp\\guard-stap.msi"

# Step 2 – Install silently via msiexec (run on {db_host}):
msiexec /i "C:\\Windows\\Temp\\guard-stap.msi" /quiet /norestart `
  GUARD_IP="{guardium_collector_ip}" GUARD_PORT="{STAP_PORT}" DB_TYPE="{db_type}"

# Step 3 – Start the service and verify
Start-Service "IBM Guardium S-TAP"
Get-Service "IBM Guardium S-TAP"
{SEP}
""")

    elif method == "gim":
        print(f"""
{SEP}
  MANUAL S-TAP INSTALL — GIM (Guardium Installation Manager)
  Target DB server : {db_host}
  GIM server       : {gim_server_url}
  Collector IP     : {guardium_collector_ip}
{SEP}

# Option A – Push via GIM REST API (one curl call)
curl -sk -u "{gim_username}:<password>" \\
  -X POST "{gim_server_url}/gim/rest/v1/installations" \\
  -H "Content-Type: application/json" \\
  -d '{{
        "targetHost":      "{db_host}",
        "collectorIP":     "{guardium_collector_ip}",
        "osType":          "linux",
        "dbType":          "{db_type}",
        "guardiumVersion": "{guardium_version}",
        "installationType":"STAP",
        "autoStart":       true
      }}'

# Option B – Push via GIM CLI (run on the GIM server)
gim_cli --server {gim_server_url} install-stap \\
  --host {db_host} \\
  --collector {guardium_collector_ip} \\
  --db-type {db_type} \\
  --version {guardium_version}

# Option C – Pull (self-registration on the DB server)
#   Download the GIM agent bootstrap package from the GIM server UI:
#   https://<gim-server>:{GIM_PORT}/GIMConsole  → Downloads → GIM Agent
#   Then on the DB server:
rpm -Uvh gim-agent-{guardium_version}.rpm
/opt/IBM/Guardium/GIM/bin/gim_register --gim-server {gim_server_url} \\
  --collector {guardium_collector_ip} --db-type {db_type}
{SEP}
""")


def _prompt_auto_or_manual(
    method: str,
    db_host: str,
    guardium_collector_ip: str,
    **kwargs,
) -> bool:
    """Ask the user if they want automated install.

    Returns True  → proceed with automation.
    Returns False → print one-liner and exit.
    """
    if not sys.stdin.isatty():
        return True   # non-interactive: always automate

    print(f"\nReady to install S-TAP on {db_host} via {method.upper()}.")
    answer = input("Proceed with automated installation? [Y/n]: ").strip().lower()
    if answer in ("n", "no"):
        print_manual_oneliner(
            method=method,
            db_host=db_host,
            guardium_collector_ip=guardium_collector_ip,
            **kwargs,
        )
        return False
    return True


# ── SSH / Linux ───────────────────────────────────────────────────────────────

def install_stap_ssh(
    *,
    db_host: str,
    db_ssh_user: str = "root",
    db_ssh_password: Optional[str] = None,
    db_ssh_key_path: Optional[str] = None,
    guardium_collector_ip: str,
    guardium_version: str = "12.2",
    stap_rpm_local_path: Optional[str] = None,
    stap_rpm_remote_path: str = "/tmp/guard-stap.rpm",
    db_type: str = "all",
    dry_run: bool = False,
    interactive: bool = True,
) -> bool:
    """Install S-TAP on a Linux/Unix DB server via SSH.

    Asks the user to confirm automation. On 'no', prints the manual one-liner
    and returns False without touching the target host.
    """
    if interactive:
        go = _prompt_auto_or_manual(
            "ssh", db_host, guardium_collector_ip,
            db_ssh_user=db_ssh_user, guardium_version=guardium_version,
            db_type=db_type, stap_rpm_path=stap_rpm_remote_path,
        )
        if not go:
            return False

    try:
        import paramiko
    except ImportError:
        raise RuntimeError("paramiko is required: pip install paramiko")

    LOG.info("Installing S-TAP on %s via SSH (collector: %s)", db_host, guardium_collector_ip)

    if dry_run:
        LOG.info("[DRY-RUN] Would SSH to %s, install S-TAP RPM, set guard.conf, restart service", db_host)
        return True

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    kwargs: dict = {"hostname": db_host, "username": db_ssh_user, "timeout": 30}
    if db_ssh_key_path:
        kwargs["key_filename"] = db_ssh_key_path
    elif db_ssh_password:
        kwargs["password"] = db_ssh_password
    else:
        raise ValueError("Provide db_ssh_password or db_ssh_key_path")

    ssh.connect(**kwargs)
    try:
        if stap_rpm_local_path:
            sftp = ssh.open_sftp()
            LOG.info("Uploading RPM → %s:%s", db_host, stap_rpm_remote_path)
            sftp.put(stap_rpm_local_path, stap_rpm_remote_path)
            sftp.close()
        else:
            rpm_on_appliance = (
                f"/var/IBM/Guardium/stap/guard-stap-{guardium_version}-linux-x86-64.rpm"
            )
            _ssh_run(
                ssh,
                f"scp -o StrictHostKeyChecking=no -P {APPLIANCE_SSH_PORT} "
                f"cli@{guardium_collector_ip}:{rpm_on_appliance} {stap_rpm_remote_path}",
            )

        _ssh_run(ssh, f"rpm -Uvh {stap_rpm_remote_path}")
        guard_conf = (
            f"TAP_IP={guardium_collector_ip}\n"
            f"GUARD_PORT={STAP_PORT}\n"
            f"DB_TYPE={db_type}\n"
            "INSPECTION_ENGINE_COUNT=1\nSTAP_ENABLED=1\n"
        )
        _ssh_run(ssh, f"printf '{guard_conf}' > /etc/sysconfig/guard.conf")
        _ssh_run(
            ssh,
            "systemctl enable guard-stap && systemctl restart guard-stap "
            "|| service guard-stap restart",
        )
        LOG.info("S-TAP installed on %s", db_host)
        return True
    finally:
        ssh.close()


def _ssh_run(ssh, cmd: str) -> str:
    _, stdout, stderr = ssh.exec_command(cmd, timeout=120)
    rc = stdout.channel.recv_exit_status()
    out = stdout.read().decode("utf-8", errors="replace").strip()
    err = stderr.read().decode("utf-8", errors="replace").strip()
    if rc != 0:
        raise RuntimeError(f"SSH command failed (exit {rc}): {cmd}\n{err}")
    if out:
        LOG.debug("SSH: %s", out)
    return out


# ── WinRM / Windows ───────────────────────────────────────────────────────────

def install_stap_winrm(
    *,
    db_host: str,
    winrm_user: str,
    winrm_password: str,
    guardium_collector_ip: str,
    guardium_version: str = "12.2",
    stap_msi_local_path: Optional[str] = None,
    winrm_port: int = 5985,
    winrm_transport: str = "ntlm",
    db_type: str = "mssql",
    dry_run: bool = False,
    interactive: bool = True,
) -> bool:
    """Install S-TAP on a Windows DB server via WinRM.

    On user 'no', prints manual msiexec one-liner.
    """
    remote_msi = r"C:\Windows\Temp\guard-stap.msi"

    if interactive:
        go = _prompt_auto_or_manual(
            "winrm", db_host, guardium_collector_ip,
            guardium_version=guardium_version,
            db_type=db_type,
            stap_msi_path=remote_msi,
        )
        if not go:
            return False

    try:
        import winrm
    except ImportError:
        raise RuntimeError("pywinrm is required: pip install pywinrm")

    LOG.info("Installing S-TAP on %s via WinRM (collector: %s)", db_host, guardium_collector_ip)

    if dry_run:
        LOG.info("[DRY-RUN] Would WinRM to %s, deploy MSI, start IBM Guardium S-TAP service", db_host)
        return True

    session = winrm.Session(
        f"http://{db_host}:{winrm_port}/wsman",
        auth=(winrm_user, winrm_password),
        transport=winrm_transport,
    )

    if stap_msi_local_path:
        _winrm_copy(session, stap_msi_local_path, remote_msi)

    result = session.run_cmd(
        f'msiexec /i "{remote_msi}" /quiet /norestart '
        f'GUARD_IP="{guardium_collector_ip}" GUARD_PORT="{STAP_PORT}" DB_TYPE="{db_type}"'
    )
    if result.status_code != 0:
        raise RuntimeError(
            f"msiexec failed (exit {result.status_code}): "
            f"{result.std_err.decode('utf-8', errors='replace')}"
        )
    session.run_cmd('net start "IBM Guardium S-TAP"')
    LOG.info("S-TAP installed on Windows host %s", db_host)
    return True


def _winrm_copy(session, local_path: str, remote_path: str) -> None:
    import base64
    with open(local_path, "rb") as f:
        data = f.read()
    encoded = base64.b64encode(data).decode("ascii")
    chunk_size = 8192
    session.run_ps(f'Remove-Item -Force "{remote_path}" -ErrorAction SilentlyContinue')
    for i in range(0, len(encoded), chunk_size):
        session.run_ps(
            f'Add-Content -Path "{remote_path}.b64" -Value "{encoded[i:i+chunk_size]}" -NoNewline -Encoding ASCII'
        )
    session.run_ps(
        f'[Convert]::FromBase64String([IO.File]::ReadAllText("{remote_path}.b64")) '
        f'| Set-Content -Path "{remote_path}" -Encoding Byte; '
        f'Remove-Item "{remote_path}.b64"'
    )


# ── GIM (Guardium Installation Manager) ───────────────────────────────────────

def install_stap_gim(
    *,
    gim_server_url: str,
    gim_username: str,
    gim_password: str,
    db_host: str,
    guardium_collector_ip: str,
    os_type: str = "linux",
    db_type: str = "all",
    guardium_version: str = "12.2",
    verify_tls: bool = False,
    dry_run: bool = False,
    interactive: bool = True,
) -> dict:
    """Push a GIM-managed S-TAP installation to a DB server.

    GIM (Guardium Installation Manager) is the IBM-recommended approach for
    enterprise-scale S-TAP deployment. It handles install, upgrade, removal,
    and centralized health monitoring of all S-TAP agents.

    On user 'no', prints three alternative manual methods (curl / gim_cli /
    self-registration pull) and returns an empty dict.
    """
    if interactive:
        go = _prompt_auto_or_manual(
            "gim", db_host, guardium_collector_ip,
            gim_server_url=gim_server_url,
            gim_username=gim_username,
            guardium_version=guardium_version,
            db_type=db_type,
        )
        if not go:
            return {}

    from .client import GuardiumClient, GuardiumApiError

    if dry_run:
        LOG.info(
            "[DRY-RUN] GIM: would install S-TAP on %s (os=%s db=%s collector=%s)",
            db_host, os_type, db_type, guardium_collector_ip,
        )
        return {"status": "dry_run", "host": db_host}

    client = GuardiumClient(
        base_url=gim_server_url,
        username=gim_username,
        password=gim_password,
        verify_tls=verify_tls,
    )
    payload = {
        "targetHost": db_host,
        "collectorIP": guardium_collector_ip,
        "osType": os_type,
        "dbType": db_type,
        "guardiumVersion": guardium_version,
        "installationType": "STAP",
        "autoStart": True,
    }
    LOG.info("GIM: pushing S-TAP installation to %s via %s", db_host, gim_server_url)
    response = client.request("POST", "/gim/rest/v1/installations", payload)
    LOG.info("GIM job created: %s", response)
    return response or {}


def get_gim_job_status(
    *,
    gim_server_url: str,
    gim_username: str,
    gim_password: str,
    job_id: str,
    verify_tls: bool = False,
) -> dict:
    from .client import GuardiumClient
    client = GuardiumClient(
        base_url=gim_server_url, username=gim_username,
        password=gim_password, verify_tls=verify_tls,
    )
    return client.request("GET", f"/gim/rest/v1/installations/{job_id}") or {}


# ── CLI ───────────────────────────────────────────────────────────────────────

def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(
        description="S-TAP installation dispatcher (SSH / WinRM / GIM)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "If you decline automated install at the prompt, the script prints\n"
            "the exact manual one-liner command you can run yourself."
        ),
    )
    sub = parser.add_subparsers(dest="method", required=True)

    # ── ssh ──────────────────────────────────────────────────────────────────
    sp = sub.add_parser("ssh", help="Install via SSH (Linux/Unix DB server)")
    sp.add_argument("--host",         required=True)
    sp.add_argument("--guardium-ip",  required=True)
    sp.add_argument("--user",         default="root")
    sp.add_argument("--password",     default=None)
    sp.add_argument("--key",          default=None, help="SSH private key path")
    sp.add_argument("--rpm",          default=None, help="Local S-TAP RPM path")
    sp.add_argument("--db-type",      default="all")
    sp.add_argument("--version",      default="12.2")
    sp.add_argument("--dry-run",      action="store_true")
    sp.add_argument("--no-prompt",    action="store_true", help="Skip confirmation prompt (always automate)")

    # ── winrm ────────────────────────────────────────────────────────────────
    wp = sub.add_parser("winrm", help="Install via WinRM (Windows DB server)")
    wp.add_argument("--host",         required=True)
    wp.add_argument("--guardium-ip",  required=True)
    wp.add_argument("--user",         required=True)
    wp.add_argument("--password",     required=True)
    wp.add_argument("--msi",          default=None, help="Local S-TAP MSI path")
    wp.add_argument("--db-type",      default="mssql")
    wp.add_argument("--version",      default="12.2")
    wp.add_argument("--winrm-port",   type=int, default=5985)
    wp.add_argument("--dry-run",      action="store_true")
    wp.add_argument("--no-prompt",    action="store_true")

    # ── gim ───────────────────────────────────────────────────────────────────
    gp = sub.add_parser("gim", help="Install via GIM (Guardium Installation Manager)")
    gp.add_argument("--host",         required=True, help="Target DB server IP/hostname")
    gp.add_argument("--guardium-ip",  required=True, help="Collector IP for S-TAP")
    gp.add_argument("--gim-url",      required=True, help="GIM server URL (https://ip:8082)")
    gp.add_argument("--gim-user",     required=True)
    gp.add_argument("--gim-password", required=True)
    gp.add_argument("--os-type",      default="linux", choices=["linux","windows","aix","solaris","hpux"])
    gp.add_argument("--db-type",      default="all")
    gp.add_argument("--version",      default="12.2")
    gp.add_argument("--no-verify-tls",action="store_true")
    gp.add_argument("--dry-run",      action="store_true")
    gp.add_argument("--no-prompt",    action="store_true")

    # ── manual ────────────────────────────────────────────────────────────────
    mp = sub.add_parser("manual", help="Print manual one-liner commands only (no automation)")
    mp.add_argument("--method",       required=True, choices=["ssh","winrm","gim"])
    mp.add_argument("--host",         required=True)
    mp.add_argument("--guardium-ip",  required=True)
    mp.add_argument("--db-type",      default="all")
    mp.add_argument("--version",      default="12.2")
    mp.add_argument("--gim-url",      default="https://10.50.20.31:8082")
    mp.add_argument("--gim-user",     default="admin")

    args = parser.parse_args()

    if args.method == "ssh":
        install_stap_ssh(
            db_host=args.host,
            db_ssh_user=args.user,
            db_ssh_password=args.password,
            db_ssh_key_path=args.key,
            guardium_collector_ip=args.guardium_ip,
            guardium_version=args.version,
            stap_rpm_local_path=args.rpm,
            db_type=args.db_type,
            dry_run=args.dry_run,
            interactive=not args.no_prompt,
        )

    elif args.method == "winrm":
        install_stap_winrm(
            db_host=args.host,
            winrm_user=args.user,
            winrm_password=args.password,
            guardium_collector_ip=args.guardium_ip,
            guardium_version=args.version,
            stap_msi_local_path=args.msi,
            db_type=args.db_type,
            winrm_port=args.winrm_port,
            dry_run=args.dry_run,
            interactive=not args.no_prompt,
        )

    elif args.method == "gim":
        result = install_stap_gim(
            gim_server_url=args.gim_url,
            gim_username=args.gim_user,
            gim_password=args.gim_password,
            db_host=args.host,
            guardium_collector_ip=args.guardium_ip,
            os_type=args.os_type,
            db_type=args.db_type,
            guardium_version=args.version,
            verify_tls=not args.no_verify_tls,
            dry_run=args.dry_run,
            interactive=not args.no_prompt,
        )
        if result:
            print(result)

    elif args.method == "manual":
        print_manual_oneliner(
            method=args.method,
            db_host=args.host,
            guardium_collector_ip=args.guardium_ip,
            guardium_version=args.version,
            db_type=args.db_type,
            gim_server_url=args.gim_url,
            gim_username=args.gim_user,
        )


if __name__ == "__main__":
    main()
