#!/usr/bin/env python3
"""Guided, stage-by-stage Guardium first-login and network setup helper.

This wraps automation/console/keysend.py. It does NOT run unattended end-to-end:
each stage sends a small, verifiable batch of keystrokes and then screenshots the
console so you can visually confirm the actual on-screen prompt/result before
running the next stage. This avoids blindly trusting invented CLI syntax.

Usage examples:
  # Stage 1: log in with the default first-boot credentials
  python3 automation/console/guardium_first_login.py <domain> login

  # Stage 2: once you see the "Enter current password" prompt in the screenshot,
  # complete the forced password change to the new password
  python3 automation/console/guardium_first_login.py <domain> change-password --new 'Ankit@#1'

  # Stage 3: once you see a "cli>" prompt (not "MySQL is not ready"), run the
  # network configuration commands confirmed working on this appliance
  # (verify each screenshot!)
  python3 automation/console/guardium_first_login.py <domain> set-network \
      --ip 192.168.2.67 --prefix 24 --gateway 192.168.2.99 \
      --dns1 192.168.2.1 --dns2 8.8.8.8

  # Stage 4: apply the network change (confirms with "yes")
  python3 automation/console/guardium_first_login.py <domain> restart-network

  # Any time: just look at the console
  python3 automation/console/guardium_first_login.py <domain> look
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
KEYSEND = HERE / "keysend.py"
LOG_DIR = HERE.parent.parent / "logs"


def run_keysend(*args: str) -> None:
    subprocess.run([sys.executable, str(KEYSEND), *args], check=True)


def type_line(domain: str, text: str) -> None:
    run_keysend(domain, "type", text)
    run_keysend(domain, "key", "enter")


def look(domain: str, tag: str) -> Path:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    path = LOG_DIR / f"{domain}-{tag}.png"
    run_keysend(domain, "screenshot", str(path))
    print(f"Screenshot: {path}")
    return path


def cmd_login(args: argparse.Namespace) -> None:
    type_line(args.domain, args.username)
    time.sleep(1)
    type_line(args.domain, args.password)
    time.sleep(3)
    look(args.domain, "after-login")


def cmd_change_password(args: argparse.Namespace) -> None:
    # Guardium forces a password change on first login: current, new, confirm.
    type_line(args.domain, args.current)
    time.sleep(1)
    type_line(args.domain, args.new)
    time.sleep(1)
    type_line(args.domain, args.new)
    time.sleep(3)
    look(args.domain, "after-password-change")


def cmd_set_network(args: argparse.Namespace) -> None:
    # Confirmed working on the live Guardium 12.2 CLI: IP+prefix combined as
    # CIDR in one command (no separate mask command needed on this release).
    commands = [
        f"store network interface ip {args.ip}/{args.prefix}",
        f"store network resolvers {args.dns1} {args.dns2}",
        f"store network routes defaultroute {args.gateway}",
    ]
    for command in commands:
        type_line(args.domain, command)
        time.sleep(2)
        look(args.domain, f"after-{'-'.join(command.split()[1:4])}")


def cmd_restart_network(args: argparse.Namespace) -> None:
    type_line(args.domain, "restart network")
    time.sleep(2)
    type_line(args.domain, "yes")
    time.sleep(8)
    look(args.domain, "after-restart-network")


def cmd_look(args: argparse.Namespace) -> None:
    look(args.domain, "look")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("domain")
    sub = parser.add_subparsers(dest="stage", required=True)

    login_cmd = sub.add_parser("login")
    login_cmd.add_argument("--username", default="cli")
    login_cmd.add_argument("--password", default="guardium")
    login_cmd.set_defaults(func=cmd_login)

    change_cmd = sub.add_parser("change-password")
    change_cmd.add_argument("--current", default="guardium")
    change_cmd.add_argument("--new", required=True)
    change_cmd.set_defaults(func=cmd_change_password)

    net_cmd = sub.add_parser("set-network")
    net_cmd.add_argument("--ip", required=True)
    net_cmd.add_argument("--prefix", default="24")
    net_cmd.add_argument("--gateway", required=True)
    net_cmd.add_argument("--dns1", required=True)
    net_cmd.add_argument("--dns2", required=True)
    net_cmd.set_defaults(func=cmd_set_network)

    restart_cmd = sub.add_parser("restart-network")
    restart_cmd.set_defaults(func=cmd_restart_network)

    look_cmd = sub.add_parser("look")
    look_cmd.set_defaults(func=cmd_look)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
