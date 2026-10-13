# RSHNetwork AI — Full Platform Guide

> Full guide available as HTML at: /root/guardium-deployment/docs/PLATFORM-GUIDE.html
> Served at: https://171.78.153.147:8080/admin (view in browser)

## Quick Reference

| Task | Command |
|------|---------|
| Platform URL | https://171.78.153.147:8080 |
| Check training | `training-status all` |
| Ingest folder | `bash scripts/bulk-ingest.sh /path --workers 4` |
| Auto train | `bash scripts/auto-train.sh /path --steps 40` |
| Multilingual ingest | `docker compose exec -T api python scripts/ingest-multilingual.py /app/data/doc.pdf --tenant rsh-internal` |
| Restart platform | `cd /root/rsh-agent && docker compose restart api worker` |
| Job queue status | `docker compose exec -T db psql -U rsh_agent -d rsh_agent -c "SELECT status,count(*) FROM ingestion_jobs GROUP BY status;"` |

## Sections
1. Platform Overview
2. Accessing the Platform
3. Task Modes (Auto / Research / Coding / Chat / Logs / Kubernetes)
4. Prompting Guide + Examples
5. Code Generation
6. SSH & Remote Task Execution
7. Internet Search Fallback
8. Multilingual Support
9. Ingesting Documents (4 methods)
10. Bulk Folder Ingestion
11. Training the Model (JSONL format + steps)
12. Self-Training Pipeline (auto-train.sh)
13. Managing Adapters
14. Admin Panel
15. Monitoring
16. Troubleshooting Table
17. Architecture Diagram
18. Scripts Reference
19. Models Reference
