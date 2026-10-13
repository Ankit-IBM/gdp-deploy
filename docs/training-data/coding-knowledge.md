# Software Development — Coding Knowledge Base

## 1. Python

### Functions, Type Hints, Dataclasses
```python
from dataclasses import dataclass, field
from typing import Optional

@dataclass
class Config:
    host: str
    port: int = 8080
    tags: list[str] = field(default_factory=list)
    timeout: Optional[float] = None

def connect(cfg: Config) -> bool:
    return cfg.host != ""
```

### Decorators
```python
import functools, time

def retry(times=3, delay=1.0):
    def decorator(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            for attempt in range(times):
                try:
                    return fn(*args, **kwargs)
                except Exception as e:
                    if attempt == times - 1:
                        raise
                    time.sleep(delay)
        return wrapper
    return decorator

@retry(times=3, delay=0.5)
def fetch_data(url: str) -> dict:
    ...
```

### Async/Await
```python
import asyncio
import aiohttp

async def fetch(session: aiohttp.ClientSession, url: str) -> dict:
    async with session.get(url, timeout=aiohttp.ClientTimeout(total=10)) as resp:
        resp.raise_for_status()
        return await resp.json()

async def fetch_all(urls: list[str]) -> list[dict]:
    async with aiohttp.ClientSession() as session:
        tasks = [fetch(session, u) for u in urls]
        return await asyncio.gather(*tasks, return_exceptions=True)

if __name__ == "__main__":
    results = asyncio.run(fetch_all(["https://api.example.com/v1", "https://api.example.com/v2"]))
```

### Context Managers
```python
from contextlib import contextmanager
import sqlite3

@contextmanager
def db_connection(path: str):
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

with db_connection("app.db") as conn:
    conn.execute("INSERT INTO users(name) VALUES(?)", ("alice",))
```

### Generators
```python
def read_chunks(path: str, size: int = 65536):
    with open(path, "rb") as f:
        while chunk := f.read(size):
            yield chunk

# Pipeline pattern
def parse_lines(path):
    for line in open(path):
        yield line.strip()

def filter_comments(lines):
    return (l for l in lines if l and not l.startswith("#"))

def process(path):
    return list(filter_comments(parse_lines(path)))
```

### Error Handling
```python
class AppError(Exception):
    def __init__(self, msg: str, code: int = 500):
        super().__init__(msg)
        self.code = code

try:
    result = risky_operation()
except (ValueError, KeyError) as e:
    raise AppError(f"Bad input: {e}", code=400) from e
except Exception:
    logger.exception("Unexpected error")
    raise
finally:
    cleanup()
```

---

## 2. JavaScript & TypeScript

### Promises and Async/Await
```javascript
// Promise chaining
fetch('/api/users')
  .then(res => { if (!res.ok) throw new Error(res.statusText); return res.json(); })
  .then(users => console.log(users))
  .catch(err => console.error('Failed:', err));

// async/await with error handling
async function getUsers() {
  try {
    const res = await fetch('/api/users');
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return await res.json();
  } catch (err) {
    console.error('getUsers failed:', err.message);
    return [];
  }
}

// Parallel fetching
const [users, posts] = await Promise.all([
  fetch('/api/users').then(r => r.json()),
  fetch('/api/posts').then(r => r.json()),
]);
```

### TypeScript Interfaces and Generics
```typescript
interface Paginated<T> {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
}

interface User {
  id: number;
  email: string;
  role: 'admin' | 'user' | 'viewer';
  createdAt: Date;
}

async function fetchPage<T>(url: string, page = 1): Promise<Paginated<T>> {
  const res = await fetch(`${url}?page=${page}`);
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  return res.json();
}

const result = await fetchPage<User>('/api/users');
```

### ES Modules
```javascript
// math.js
export const add = (a, b) => a + b;
export default class Calculator {
  #history = [];
  add(a, b) { const r = a + b; this.#history.push(r); return r; }
  get history() { return [...this.#history]; }
}

// main.js
import Calculator, { add } from './math.js';
const calc = new Calculator();
console.log(calc.add(3, 4)); // 7
```

---

## 3. Bash Scripting

### Script Template
```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/myscript.log"

log()  { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }
die()  { log "ERROR: $*"; exit 1; }
usage(){ echo "Usage: $0 [--dry-run] <env>"; exit 0; }

DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage ;;
    *) ENV="$1"; shift ;;
  esac
done

[[ -z "${ENV:-}" ]] && die "Environment required"

# Trap for cleanup
cleanup() { log "Cleaning up..."; rm -f /tmp/myscript.lock; }
trap cleanup EXIT INT TERM
```

### sed, awk, grep patterns
```bash
# Replace in-place
sed -i 's/old_value/new_value/g' config.yml
sed -i "/^#/d; /^$/d" config.yml          # remove comments and blank lines

# awk: sum column 3 where col 1 matches
awk '$1 ~ /prod/ { sum += $3 } END { print sum }' report.txt

# awk: print specific fields from CSV
awk -F',' 'NR>1 { print $2, $4 }' data.csv

# grep with context
grep -B2 -A5 "ERROR" app.log
grep -rn "TODO\|FIXME" src/ --include="*.py"

# Process substitution
diff <(ssh host1 cat /etc/hosts) <(ssh host2 cat /etc/hosts)
```

---

## 4. SQL

### Joins, Aggregations
```sql
-- Window function: rank users by spend per region
SELECT
  user_id,
  region,
  total_spend,
  RANK() OVER (PARTITION BY region ORDER BY total_spend DESC) AS rank_in_region,
  AVG(total_spend) OVER (PARTITION BY region) AS avg_region_spend
FROM orders
WHERE created_at >= NOW() - INTERVAL '30 days';

-- CTE for readability
WITH monthly AS (
  SELECT
    DATE_TRUNC('month', created_at) AS month,
    SUM(amount) AS revenue
  FROM orders
  GROUP BY 1
)
SELECT month, revenue,
       LAG(revenue) OVER (ORDER BY month) AS prev_month,
       revenue - LAG(revenue) OVER (ORDER BY month) AS delta
FROM monthly;
```

### Indexes and EXPLAIN
```sql
-- Create partial index for active users only
CREATE INDEX idx_users_active_email ON users(email) WHERE active = true;

-- Composite index: column order matters — put equality cols first
CREATE INDEX idx_orders_user_status ON orders(user_id, status, created_at);

-- EXPLAIN ANALYZE to find seq scans
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT * FROM orders WHERE user_id = 42 AND status = 'pending';
-- Look for: Seq Scan → add index; high Buffers → cache miss

-- Transactions
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;  -- or ROLLBACK on error
```

---

## 5. Git

### Essential Workflows
```bash
# Feature branch workflow
git checkout -b feature/my-feature
git add -p                              # interactive staging
git commit -m "feat: add user auth"

# Rebase onto main (clean history)
git fetch origin
git rebase origin/main
git push --force-with-lease            # safe force push

# Interactive rebase — squash last 3 commits
git rebase -i HEAD~3
# Change 'pick' to 'squash' on the commits to merge

# Cherry-pick a commit from another branch
git cherry-pick abc1234

# Stash with message
git stash push -m "WIP: partial auth"
git stash list
git stash pop stash@{0}

# Bisect to find regression
git bisect start
git bisect bad HEAD
git bisect good v1.2.0
# git runs binary search — mark each as good/bad
git bisect reset

# Reflog to recover lost commits
git reflog
git checkout -b recovery HEAD@{5}
```

---

## 6. Docker

### Dockerfile Best Practices
```dockerfile
# Multi-stage build — keep final image small
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim
WORKDIR /app
# Copy only installed packages, not the whole builder layer
COPY --from=builder /install /usr/local
COPY . .
# Non-root user
RUN groupadd -r app && useradd -r -g app app
USER app
# Use exec form (no shell) so signals reach the process
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
```

### Docker Compose
```yaml
services:
  api:
    build: .
    env_file: .env
    depends_on:
      db:
        condition: service_healthy
    ports: ["8080:8080"]
    restart: unless-stopped

  db:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - pg-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 3s
      retries: 10

volumes:
  pg-data:
```

### Docker Debugging
```bash
# Exec into running container
docker exec -it <container> /bin/sh

# Show resource usage
docker stats --no-stream

# Inspect network
docker network inspect bridge
docker inspect <container> --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'

# Copy files out of container
docker cp <container>:/app/logs/app.log ./app.log

# Debug stopped container (override entrypoint)
docker run --rm -it --entrypoint /bin/sh myimage

# Build with no cache
docker build --no-cache -t myimage .

# Prune everything unused
docker system prune -af --volumes
```

---

## 7. Terraform

### Modules and For_each
```hcl
# modules/vm/main.tf
variable "instances" {
  type = map(object({ size = string, zone = string }))
}

resource "google_compute_instance" "vm" {
  for_each     = var.instances
  name         = each.key
  machine_type = each.value.size
  zone         = each.value.zone
  boot_disk { initialize_params { image = "debian-cloud/debian-12" } }
  network_interface { network = "default" }
}

output "ips" {
  value = { for k, v in google_compute_instance.vm : k => v.network_interface[0].network_ip }
}
```

### State Management
```bash
# Remote state on GCS
terraform {
  backend "gcs" {
    bucket = "my-tf-state"
    prefix = "prod/network"
  }
}

# Move resource to new address (no destroy/recreate)
terraform state mv 'aws_instance.old_name' 'aws_instance.new_name'

# Import existing infra
terraform import aws_s3_bucket.mybucket my-existing-bucket-name

# Workspaces for environments
terraform workspace new staging
terraform workspace select prod
terraform plan -var-file=prod.tfvars
```

### Data Sources and Locals
```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical
  filter { name = "name";   values = ["ubuntu/images/hvm-ssd/ubuntu-*-22.04-amd64-*"] }
  filter { name = "state";  values = ["available"] }
}

locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = var.team
  }
  instance_count = var.environment == "prod" ? 3 : 1
}

resource "aws_instance" "web" {
  count         = local.instance_count
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  tags          = merge(local.common_tags, { Name = "web-${count.index}" })
}
```

---

## 8. Debugging

### Python pdb / breakpoint
```python
# Drop into debugger
breakpoint()  # Python 3.7+

# pdb commands:
# n = next line
# s = step into
# c = continue
# p expr = print expression
# l = list source
# bt = backtrace
# q = quit

# Post-mortem debugging
try:
    risky()
except Exception:
    import pdb; pdb.post_mortem()
```

### Linux Debugging Tools
```bash
# strace — trace system calls
strace -p <pid>                        # attach to running process
strace -e trace=network,file ./myapp   # filter by category
strace -o strace.log -f ./myapp        # log to file, follow forks

# lsof — list open files / ports
lsof -i :8080                          # what's on port 8080
lsof -p <pid>                          # files opened by process
lsof -u myuser                         # files opened by user

# tcpdump — capture network traffic
tcpdump -i eth0 port 8080 -w cap.pcap
tcpdump -r cap.pcap -A | head -100     # read and print ASCII

# ss / netstat
ss -tlnp                               # listening TCP sockets
ss -s                                  # summary

# Check what a process is doing right now
cat /proc/<pid>/status
ls -la /proc/<pid>/fd                  # open file descriptors
```

### Logging Best Practices
```python
import logging
import sys

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-8s %(name)s %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler("app.log"),
    ],
)
logger = logging.getLogger(__name__)

# Structured logging with extra fields
logger.info("Request received", extra={"user_id": 42, "endpoint": "/api/data"})

# Log exceptions with traceback
try:
    result = process()
except Exception:
    logger.exception("Processing failed for item %s", item_id)
```

---

## 9. REST API Design

```python
# FastAPI example with pagination, auth, proper status codes
from fastapi import FastAPI, Depends, HTTPException, status, Query
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

app = FastAPI()
security = HTTPBearer()

def verify_token(creds: HTTPAuthorizationCredentials = Depends(security)):
    if not creds.credentials.startswith("valid"):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    return creds.credentials

@app.get("/api/v1/users", status_code=200)
async def list_users(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    _token: str = Depends(verify_token),
):
    offset = (page - 1) * page_size
    users = await db.fetch_users(limit=page_size, offset=offset)
    total = await db.count_users()
    return {
        "items": users,
        "total": total,
        "page": page,
        "page_size": page_size,
        "pages": -(-total // page_size),  # ceiling division
    }

# Always use 201 for created, 204 for no-content deletes
@app.post("/api/v1/users", status_code=status.HTTP_201_CREATED)
async def create_user(body: UserCreate, _token = Depends(verify_token)):
    ...

@app.delete("/api/v1/users/{uid}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_user(uid: int, _token = Depends(verify_token)):
    ...
```

---

## 10. Clean Code Principles

- **Single Responsibility**: each function/class does one thing. If you need "and" to describe it, split it.
- **Meaningful names**: `get_active_user_ids()` not `get_data()`. Avoid abbreviations except universally known ones (`id`, `url`, `cpu`).
- **DRY but not over-abstracted**: don't abstract until you have 3 repetitions with the same pattern.
- **Small functions**: if a function is more than ~30 lines, consider splitting.
- **Fail fast**: validate inputs at the top of functions; raise early rather than propagating bad state.
- **Avoid magic numbers**: `MAX_RETRIES = 3` not bare `3`.
- **Comments explain why, not what**: code says what; comments explain non-obvious decisions.
- **Tests as documentation**: test names should read like specs: `test_login_fails_with_expired_token`.
