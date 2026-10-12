#!/usr/bin/env python3
"""List available Guardium images/ISOs on each cloud platform and let the user
pick one interactively. Prints the chosen image ID so the caller can pass it
as a Terraform variable.

Usage:
  python3 scripts/list-images.py aws    --region us-east-1
  python3 scripts/list-images.py gcp    --project my-project --region us-central1
  python3 scripts/list-images.py azure  --subscription <sub-id> --resource-group rg-guardium
  python3 scripts/list-images.py vsphere --server vcenter.example.com --datastore datastore1

The script filters images/ISOs whose name contains "guardium" (case-insensitive).
It prints a numbered list, prompts the user to select one, and outputs the
chosen image ID (or datastore path for vSphere) on stdout — suitable for:

  IMAGE=$(python3 scripts/list-images.py aws --region us-east-1)
  ./scripts/guardium-deploy collector --aws-ami-id "$IMAGE"

Pass --json to output the full list as JSON without prompting (CI/pipeline use).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any


# ─────────────────────────────────────────────────────────────────────────────
# AWS
# ─────────────────────────────────────────────────────────────────────────────

def list_aws(region: str, filter_str: str = "guardium") -> list[dict]:
    """List AMIs in the account that match the filter string."""
    try:
        import boto3
    except ImportError:
        _die("boto3 is required for AWS: pip install boto3")

    ec2 = boto3.client("ec2", region_name=region)
    response = ec2.describe_images(
        Owners=["self"],
        Filters=[
            {"Name": "state", "Values": ["available"]},
            {"Name": "name", "Values": [f"*{filter_str}*"]},
        ],
    )
    images = sorted(response.get("Images", []), key=lambda x: x.get("CreationDate", ""), reverse=True)
    return [
        {
            "id":          img["ImageId"],
            "name":        img.get("Name", ""),
            "description": img.get("Description", ""),
            "created":     img.get("CreationDate", ""),
            "platform":    img.get("PlatformDetails", "Linux/UNIX"),
        }
        for img in images
    ]


# ─────────────────────────────────────────────────────────────────────────────
# GCP
# ─────────────────────────────────────────────────────────────────────────────

def list_gcp(project_id: str, filter_str: str = "guardium") -> list[dict]:
    """List custom images in the GCP project that match the filter string."""
    try:
        from google.cloud import compute_v1
    except ImportError:
        _die("google-cloud-compute is required for GCP: pip install google-cloud-compute")

    client = compute_v1.ImagesClient()
    images = []
    for img in client.list(project=project_id):
        if filter_str.lower() in img.name.lower() and img.status == "READY":
            images.append({
                "id":          img.self_link,
                "name":        img.name,
                "description": img.description or "",
                "created":     img.creation_timestamp or "",
                "family":      img.family or "",
                "disk_size_gb":img.disk_size_gb,
            })
    return sorted(images, key=lambda x: x["created"], reverse=True)


# ─────────────────────────────────────────────────────────────────────────────
# Azure
# ─────────────────────────────────────────────────────────────────────────────

def list_azure(subscription_id: str, resource_group: str = "", filter_str: str = "guardium") -> list[dict]:
    """List managed images (and SIG versions) in the Azure subscription."""
    try:
        from azure.identity import DefaultAzureCredential
        from azure.mgmt.compute import ComputeManagementClient
    except ImportError:
        _die("azure-mgmt-compute and azure-identity are required: pip install azure-mgmt-compute azure-identity")

    credential = DefaultAzureCredential()
    compute = ComputeManagementClient(credential, subscription_id)

    results = []

    # Managed images
    if resource_group:
        images = compute.images.list_by_resource_group(resource_group)
    else:
        images = compute.images.list()

    for img in images:
        if filter_str.lower() in img.name.lower():
            results.append({
                "id":          img.id,
                "name":        img.name,
                "location":    img.location,
                "type":        "managed_image",
                "os_type":     str(img.storage_profile.os_disk.os_type) if img.storage_profile else "",
                "provisioning_state": img.provisioning_state,
            })

    # Shared Image Gallery versions
    for gallery in compute.galleries.list():
        rg = gallery.id.split("/resourceGroups/")[1].split("/")[0]
        for definition in compute.gallery_images.list_by_gallery(rg, gallery.name):
            if filter_str.lower() in definition.name.lower():
                for version in compute.gallery_image_versions.list_by_gallery_image(
                    rg, gallery.name, definition.name
                ):
                    results.append({
                        "id":    version.id,
                        "name":  f"{gallery.name}/{definition.name}/{version.name}",
                        "location": version.location,
                        "type":  "sig_version",
                        "provisioning_state": version.provisioning_state,
                    })

    return results


# ─────────────────────────────────────────────────────────────────────────────
# vSphere — list ISOs on a datastore
# ─────────────────────────────────────────────────────────────────────────────

def list_vsphere(server: str, datastore: str, username: str = "", password: str = "",
                 filter_str: str = "guardium", allow_unverified_ssl: bool = False) -> list[dict]:
    """List ISO files on a vSphere datastore that match the filter string.

    Uses pyVmomi (the official VMware Python SDK) to browse the datastore.
    Alternatively, if govc is installed, falls back to that.
    """
    username = username or os.environ.get("VSPHERE_USER", "")
    password = password or os.environ.get("VSPHERE_PASSWORD", "")
    if not username or not password:
        _die("Provide vSphere credentials via --vsphere-user/--vsphere-password or VSPHERE_USER/VSPHERE_PASSWORD env vars")

    # Try pyVmomi first
    try:
        return _list_vsphere_pyvmomi(server, datastore, username, password, filter_str, allow_unverified_ssl)
    except ImportError:
        pass

    # Fall back to govc if installed
    return _list_vsphere_govc(server, datastore, username, password, filter_str)


def _list_vsphere_pyvmomi(server, datastore, username, password, filter_str, allow_unverified_ssl):
    import ssl
    from pyVim.connect import SmartConnect, Disconnect
    from pyVmomi import vim

    ctx = ssl._create_unverified_context() if allow_unverified_ssl else ssl.create_default_context()
    si = SmartConnect(host=server, user=username, pwd=password, sslContext=ctx)
    try:
        content = si.RetrieveContent()
        # Find the datastore object
        ds_obj = None
        for dc in content.rootFolder.childEntity:
            for ds in dc.datastore:
                if ds.name == datastore:
                    ds_obj = ds
                    break
        if ds_obj is None:
            _die(f"Datastore '{datastore}' not found on {server}")

        browser = ds_obj.browser
        spec = vim.host.DatastoreBrowser.SearchSpec()
        spec.query = [vim.host.DatastoreBrowser.IsoImageQuery()]
        task = browser.SearchDatastoreSubFolders_Task(f"[{datastore}]", spec)
        # Wait for task
        while task.info.state in ("queued", "running"):
            import time; time.sleep(1)
        results = []
        for folder_result in (task.info.result or []):
            folder = folder_result.folderPath.replace(f"[{datastore}] ", "")
            for file_info in folder_result.file:
                fname = file_info.path
                full_path = f"{folder}{fname}" if folder else fname
                if filter_str.lower() in full_path.lower() and fname.lower().endswith(".iso"):
                    results.append({
                        "id":           full_path,        # datastore path → use as vsphere_iso_datastore_path
                        "name":         fname,
                        "folder":       folder,
                        "size_mb":      round(file_info.fileSize / 1024 / 1024, 1),
                        "modification": str(file_info.modification),
                    })
        return sorted(results, key=lambda x: x["modification"], reverse=True)
    finally:
        Disconnect(si)


def _list_vsphere_govc(server, datastore, username, password, filter_str):
    import subprocess, json as _json
    env = {
        **os.environ,
        "GOVC_URL":      f"https://{username}:{password}@{server}",
        "GOVC_INSECURE": "1",
        "GOVC_DATASTORE": datastore,
    }
    out = subprocess.check_output(
        ["govc", "datastore.ls", "-json", "-R", "-type", "f"],
        env=env, text=True
    )
    data = _json.loads(out)
    results = []
    for entry in data.get("File", []):
        path = entry.get("Path", "")
        if filter_str.lower() in path.lower() and path.lower().endswith(".iso"):
            results.append({
                "id":    path,
                "name":  path.split("/")[-1],
                "size_mb": round(entry.get("FileSize", 0) / 1024 / 1024, 1),
            })
    return results


# ─────────────────────────────────────────────────────────────────────────────
# Interactive picker
# ─────────────────────────────────────────────────────────────────────────────

def pick_image(images: list[dict], provider: str) -> str:
    """Print a numbered table, prompt user to select one, return its id."""
    if not images:
        _die(f"No Guardium images found on {provider}. Check your filter, credentials, and that images are imported.")

    print(f"\nAvailable Guardium images on {provider.upper()}:")
    print("─" * 80)

    col_headers = {
        "aws":     ["#", "AMI ID", "Name", "Created", "Platform"],
        "gcp":     ["#", "Image Name", "Family", "Disk GB", "Created"],
        "azure":   ["#", "Name", "Type", "Location", "State"],
        "vsphere": ["#", "Datastore Path", "Name", "Size MB", "Modified"],
    }
    headers = col_headers.get(provider, ["#", "ID", "Name", "Info"])
    col_keys = {
        "aws":     ["", "id", "name", "created", "platform"],
        "gcp":     ["", "name", "family", "disk_size_gb", "created"],
        "azure":   ["", "name", "type", "location", "provisioning_state"],
        "vsphere": ["", "id", "name", "size_mb", "modification"],
    }
    keys = col_keys.get(provider, ["", "id", "name"])

    # Print header
    print("  ".join(f"{h:<30}" if i > 0 else f"{h:<4}" for i, h in enumerate(headers)))
    print("─" * 80)
    for i, img in enumerate(images, 1):
        row = [str(i)]
        for k in keys[1:]:
            row.append(str(img.get(k, ""))[:30])
        print("  ".join(f"{v:<30}" if j > 0 else f"{v:<4}" for j, v in enumerate(row)))
    print("─" * 80)

    if not sys.stdin.isatty():
        # Non-interactive: return the first (most recent) image
        print(f"\n[non-interactive] Auto-selected: {images[0]['id']}", file=sys.stderr)
        return images[0]["id"]

    while True:
        choice = input(f"\nSelect image number [1-{len(images)}] (or 'q' to quit): ").strip()
        if choice.lower() == "q":
            sys.exit(0)
        if choice.isdigit() and 1 <= int(choice) <= len(images):
            selected = images[int(choice) - 1]
            print(f"\n✓ Selected: {selected['id']}", file=sys.stderr)
            return selected["id"]
        print(f"  Invalid choice '{choice}'. Enter a number between 1 and {len(images)}.")


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="List and interactively select a Guardium image/ISO on AWS, GCP, Azure, or vSphere",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # AWS — list AMIs tagged/named with 'guardium', pick one, use in deploy
  IMAGE=$(python3 scripts/list-images.py aws --region us-east-1)
  ./scripts/guardium-deploy collector   # then paste $IMAGE when prompted

  # GCP
  IMAGE=$(python3 scripts/list-images.py gcp --project my-gcp-project --region us-central1)

  # Azure
  IMAGE=$(python3 scripts/list-images.py azure --subscription <sub-id> --resource-group rg-guardium)

  # vSphere — list ISOs on a datastore
  ISO=$(python3 scripts/list-images.py vsphere --server vcenter.example.com --datastore datastore1)
  # Then use $ISO as vsphere_iso_datastore_path
""",
    )
    parser.add_argument("--filter",  default="guardium", help="Name filter string (default: guardium)")
    parser.add_argument("--json",    action="store_true", help="Output full list as JSON; no interactive prompt")
    sub = parser.add_subparsers(dest="provider", required=True)

    # AWS
    aws_p = sub.add_parser("aws", help="List Guardium AMIs in AWS")
    aws_p.add_argument("--region", default=os.environ.get("AWS_DEFAULT_REGION","us-east-1"))

    # GCP
    gcp_p = sub.add_parser("gcp", help="List Guardium custom images in GCP")
    gcp_p.add_argument("--project", required=True, help="GCP project ID")
    gcp_p.add_argument("--region",  default="")

    # Azure
    az_p = sub.add_parser("azure", help="List Guardium managed images / SIG versions in Azure")
    az_p.add_argument("--subscription",   default=os.environ.get("AZURE_SUBSCRIPTION_ID",""))
    az_p.add_argument("--resource-group", default="", dest="resource_group")

    # vSphere
    vs_p = sub.add_parser("vsphere", help="List Guardium ISOs on a vSphere Datastore")
    vs_p.add_argument("--server",    required=True, help="vCenter FQDN or IP")
    vs_p.add_argument("--datastore", required=True, help="Datastore name")
    vs_p.add_argument("--vsphere-user",     default="", dest="vsphere_user")
    vs_p.add_argument("--vsphere-password", default="", dest="vsphere_password")
    vs_p.add_argument("--allow-unverified-ssl", action="store_true", dest="allow_unverified_ssl")

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    images: list[dict] = []

    if args.provider == "aws":
        images = list_aws(region=args.region, filter_str=args.filter)
    elif args.provider == "gcp":
        images = list_gcp(project_id=args.project, filter_str=args.filter)
    elif args.provider == "azure":
        if not args.subscription:
            _die("Provide --subscription or set AZURE_SUBSCRIPTION_ID")
        images = list_azure(
            subscription_id=args.subscription,
            resource_group=args.resource_group,
            filter_str=args.filter,
        )
    elif args.provider == "vsphere":
        images = list_vsphere(
            server=args.server,
            datastore=args.datastore,
            username=args.vsphere_user,
            password=args.vsphere_password,
            filter_str=args.filter,
            allow_unverified_ssl=args.allow_unverified_ssl,
        )

    if args.json:
        print(json.dumps(images, indent=2))
        return

    chosen_id = pick_image(images, args.provider)
    # Print ONLY the image ID to stdout so callers can capture it
    print(chosen_id)


if __name__ == "__main__":
    main()
