#!/usr/bin/env bash
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${GUARDIUM_CONFIG:-$PROJECT_ROOT/config/lab.yml}"
VENV_DIR="$PROJECT_ROOT/.venv"
VENV_PYTHON="${VENV_DIR}/bin/python3"
VENV_PIP="${VENV_DIR}/bin/pip"
VENV_ANSIBLE="${VENV_DIR}/bin/ansible-playbook"

COLLECTOR_HOSTNAME=""
COLLECTOR_IP=""
AGGREGATOR_HOSTNAME=""
AGGREGATOR_IP=""
NETWORK_GATEWAY=""
NETWORK_PREFIX="24"
DNS1=""
DNS2=""
CURRENT_PASSWORD="guardium"
NEW_PASSWORD="guardium"

prompt_if_missing() {
  local variable_name="$1"
  local prompt_text="$2"
  local default_value="$3"
  local value
  value="${!variable_name}"
  if [[ -z "$value" ]]; then
    read -r -p "$prompt_text [$default_value]: " value
    if [[ -z "$value" ]]; then
      value="$default_value"
    fi
    printf -v "$variable_name" '%s' "$value"
  fi
}

usage() {
  cat <<'EOF'
Usage: ./scripts/guardium-everything.sh [collector|aggregator|full] [options]

Options:
  --collector-hostname NAME
  --collector-ip IP
  --aggregator-hostname NAME
  --aggregator-ip IP
  --gateway IP
  --prefix CIDR_PREFIX
  --dns1 IP
  --dns2 IP
  --current-password PASSWORD
  --new-password PASSWORD
  --help

Examples:
  ./scripts/guardium-everything.sh full \
    --collector-hostname gdp-col01 --collector-ip 10.50.20.31 \
    --aggregator-hostname gdp-agg01 --aggregator-ip 10.50.20.21 \
    --gateway 10.50.20.1 --prefix 24 --dns1 10.50.20.1 --dns2 8.8.8.8 \
    --current-password guardium --new-password Ankit@#1
EOF
}

parse_args() {
  local target="${1:-full}"
  shift || true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      collector|aggregator|full)
        target="$1"
        ;;
      --collector-hostname)
        COLLECTOR_HOSTNAME="$2"; shift 2 ;;
      --collector-ip)
        COLLECTOR_IP="$2"; shift 2 ;;
      --aggregator-hostname)
        AGGREGATOR_HOSTNAME="$2"; shift 2 ;;
      --aggregator-ip)
        AGGREGATOR_IP="$2"; shift 2 ;;
      --gateway)
        NETWORK_GATEWAY="$2"; shift 2 ;;
      --prefix)
        NETWORK_PREFIX="$2"; shift 2 ;;
      --dns1)
        DNS1="$2"; shift 2 ;;
      --dns2)
        DNS2="$2"; shift 2 ;;
      --current-password)
        CURRENT_PASSWORD="$2"; shift 2 ;;
      --new-password)
        NEW_PASSWORD="$2"; shift 2 ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        fatal "Unknown argument: $1"
        ;;
    esac
  done

  if [[ -z "$COLLECTOR_HOSTNAME" || -z "$COLLECTOR_IP" || -z "$AGGREGATOR_HOSTNAME" || -z "$AGGREGATOR_IP" || -z "$NETWORK_GATEWAY" || -z "$DNS1" || -z "$DNS2" ]]; then
    prompt_if_missing COLLECTOR_HOSTNAME "Collector hostname" "$(config_value collector.hostname 2>/dev/null || echo gdp-col01)"
    prompt_if_missing COLLECTOR_IP "Collector IP" "$(config_value collector.ip 2>/dev/null || echo 10.50.20.31)"
    prompt_if_missing AGGREGATOR_HOSTNAME "Aggregator hostname" "$(config_value aggregator.hostname 2>/dev/null || echo gdp-agg01)"
    prompt_if_missing AGGREGATOR_IP "Aggregator IP" "$(config_value aggregator.ip 2>/dev/null || echo 10.50.20.21)"
    prompt_if_missing NETWORK_GATEWAY "Gateway" "$(config_value network.gateway 2>/dev/null || echo 10.50.20.1)"
    prompt_if_missing NETWORK_PREFIX "Network prefix" "$(config_value network.prefix 2>/dev/null || echo 24)"
    prompt_if_missing DNS1 "DNS 1" "$(config_value guardium.dns.0 2>/dev/null || echo 10.50.20.1)"
    prompt_if_missing DNS2 "DNS 2" "$(config_value guardium.dns.1 2>/dev/null || echo 8.8.8.8)"
    prompt_if_missing CURRENT_PASSWORD "Current login password" "guardium"
    prompt_if_missing NEW_PASSWORD "New password after first login change" "Ankit@#1"
  fi

  printf '%s\n' "$target"
}

if [[ ! -x "$VENV_PYTHON" ]]; then
  log "Creating Python virtual environment at $VENV_DIR"
  python3 -m venv "$VENV_DIR" || fatal "Failed to create virtual environment at $VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fatal() {
  log "ERROR: $*" >&2
  exit 1
}

config_value() {
  "$VENV_PYTHON" - "$CONFIG_FILE" "$1" <<'PY'
import sys
try:
    import yaml
except ImportError:
    raise SystemExit("PyYAML is required; activate the project virtual environment")
with open(sys.argv[1], encoding='utf-8') as stream:
    data = yaml.safe_load(stream) or {}
parts = sys.argv[2].split('.')
value = data
for part in parts:
    if not isinstance(value, dict) or part not in value:
        print('')
        raise SystemExit(0)
    value = value[part]
print('' if value is None else value)
PY
}

ensure_python_tools() {
  if ! "$VENV_PYTHON" - <<'PY'
import importlib
for name in ('yaml',):
    importlib.import_module(name)
PY
  then
    log "Installing Python dependencies for Ansible and config parsing"
    "$VENV_PYTHON" -m pip install --upgrade pip >/dev/null 2>&1 || true
    "$VENV_PYTHON" -m pip install ansible PyYAML >/dev/null 2>&1 || fatal "Failed to install ansible and PyYAML"
  fi

  if [[ ! -x "$VENV_ANSIBLE" ]]; then
    log "Installing ansible-playbook"
    "$VENV_PYTHON" -m pip install ansible >/dev/null 2>&1 || fatal "Failed to install ansible-playbook"
  fi
}

ensure_sudoers() {
  if sudo -n true >/dev/null 2>&1; then
    return 0
  fi

  log "Configuring passwordless sudo for libvirt automation"
  sudo tee /etc/sudoers.d/guardium-deploy >/dev/null <<'EOF'
dev ALL=(root) NOPASSWD: ALL
EOF
  sudo chmod 440 /etc/sudoers.d/guardium-deploy
  sudo visudo -cf /etc/sudoers.d/guardium-deploy >/dev/null || fatal "sudoers validation failed"
}

wait_for_domain_running() {
  local name="$1"
  local tries=0
  while (( tries < 180 )); do
    local state
    state="$(sudo -n virsh domstate "$name" 2>/dev/null || true)"
    if [[ "$state" == "running" ]]; then
      return 0
    fi
    sleep 10
    ((tries += 1))
  done
  return 1
}

run_with_retries() {
  local label="$1"
  shift
  local attempt max_attempts
  max_attempts=30
  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if "$@" >/tmp/guardium-auto.log 2>&1; then
      log "${label} succeeded on attempt ${attempt}"
      return 0
    fi
    log "${label} not ready yet (attempt ${attempt}/${max_attempts}); waiting 30s"
    sleep 30
  done
  log "${label} failed after ${max_attempts} attempts" >&2
  cat /tmp/guardium-auto.log >&2 || true
  return 1
}

wait_for_guardium_ssh() {
  local role="$1" ip="$2"
  local attempt max_attempts
  max_attempts=24
  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "root@${ip}" true >/tmp/guardium-ssh.log 2>&1; then
      log "SSH is reachable for $role at $ip"
      return 0
    fi
    log "Waiting for Guardium SSH on $role ($ip) to become available (attempt ${attempt}/${max_attempts}); sleeping 60s"
    sleep 60
  done
  log "Guardium SSH never became reachable for $role at $ip" >&2
  cat /tmp/guardium-ssh.log >&2 || true
  return 1
}

setup_console_for_role() {
  local role="$1" name ip gateway dns1 dns2 prefix current_password new_password

  if [[ "$role" == "collector" ]]; then
    name="$COLLECTOR_HOSTNAME"
    ip="$COLLECTOR_IP"
  else
    name="$AGGREGATOR_HOSTNAME"
    ip="$AGGREGATOR_IP"
  fi

  gateway="$NETWORK_GATEWAY"
  prefix="$NETWORK_PREFIX"
  dns1="$DNS1"
  dns2="$DNS2"
  current_password="$CURRENT_PASSWORD"
  new_password="$NEW_PASSWORD"

  if [[ -z "$name" || -z "$ip" ]]; then
    fatal "Missing hostname or IP for role '$role'"
  fi

  log "Waiting for VM $name to start"
  wait_for_domain_running "$name" || fatal "VM $name never reached the running state"

  log "Attempting Guardium first-login and network setup for $name"
  run_with_retries "login for $name" python "$PROJECT_ROOT/automation/console/guardium_first_login.py" "$name" login \
    --username cli --password "$current_password"

  if [[ "$new_password" != "$current_password" ]]; then
    run_with_retries "password change for $name" python "$PROJECT_ROOT/automation/console/guardium_first_login.py" "$name" change-password \
      --current "$current_password" --new "$new_password"
  fi

  run_with_retries "network config for $name" python "$PROJECT_ROOT/automation/console/guardium_first_login.py" "$name" set-network \
    --ip "$ip" --prefix "$prefix" --gateway "$gateway" --dns1 "$dns1" --dns2 "$dns2"

  run_with_retries "network restart for $name" python "$PROJECT_ROOT/automation/console/guardium_first_login.py" "$name" restart-network
}

provision_and_converge_role() {
  local role="$1"
  local ip

  if [[ "$role" == "collector" ]]; then
    ip="$COLLECTOR_IP"
  else
    ip="$AGGREGATOR_IP"
  fi

  log "Provisioning role: $role"
  "$PROJECT_ROOT/scripts/guardium-deploy" "$role" || fatal "Provisioning failed for role '$role'"
  setup_console_for_role "$role"

  log "Waiting for the installed Guardium appliance to become reachable for converge"
  if ! wait_for_guardium_ssh "$role" "$ip"; then
    fatal "Guardium appliance $role did not become reachable on $ip after installation; check the console and network setup"
  fi

  log "Converging role: $role"
  local attempt max_attempts
  max_attempts=6
  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if "$PROJECT_ROOT/scripts/guardium-deploy" converge "$role"; then
      return 0
    fi
    log "Converge for $role failed on attempt ${attempt}/${max_attempts}; waiting 90s before retry"
    sleep 90
  done
  fatal "Converge failed for role '$role' after retries"
}

main() {
  ensure_python_tools
  ensure_sudoers

  local target="${1:-full}"
  case "$target" in
    collector|aggregator|full)
      ;;
    *)
      printf 'Usage: %s [collector|aggregator|full]\n' "$0" >&2
      exit 2
      ;;
  esac

  if ! command -v virsh >/dev/null 2>&1; then
    fatal "virsh is required to create and control the libvirt VMs"
  fi

  if [[ -z "$COLLECTOR_HOSTNAME" && -z "$AGGREGATOR_HOSTNAME" && -z "$NETWORK_GATEWAY" && -z "$DNS1" && -z "$DNS2" ]]; then
    parse_args "$target" "$@"
  else
    parse_args "$target" "$@"
  fi

  if [[ "$target" == "collector" ]]; then
    provision_and_converge_role collector
    exit 0
  fi

  if [[ "$target" == "aggregator" ]]; then
    provision_and_converge_role aggregator
    exit 0
  fi

  provision_and_converge_role collector
  provision_and_converge_role aggregator
  log "Full deployment automation completed"
}

main "$@"
