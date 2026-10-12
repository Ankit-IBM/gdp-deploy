# IBM Security Portfolio — Complete Product Knowledge Base

## 1. IBM Guardium

### 1.1 IBM Guardium Data Protection (GDP)
IBM Guardium Data Protection is a database activity monitoring (DAM) platform that provides real-time visibility into database activity, protecting sensitive data from internal and external threats.

**Core components:**
- **Collector** — deployed close to the database server; captures and inspects all database traffic via S-TAP agents or network sniffing. Runs Guardium 12.x on RHEL 9 base. Default admin port: 8443 (REST API/UI), 16022 (SSH CLI).
- **Aggregator** — consolidates data from multiple Collectors for centralised reporting, policy management, and compliance. Registered to via POST /restAPI/register_aggregator on the Collector.
- **Central Manager (CM)** — manages multiple Aggregators and Collectors at enterprise scale; distributes policies, manages updates, provides a single pane of glass.
- **S-TAP (Software Tap)** — lightweight agent installed on the database server. Captures database traffic at the kernel/OS level. Communicates back to the Collector on TCP 8075. Installation: RPM on Linux, MSI on Windows. Config file: /etc/sysconfig/guard.conf (Linux), registry on Windows.
- **GIM (Guardium Installation Manager)** — IBM enterprise tool for centralised S-TAP lifecycle management: install, upgrade, removal, config push, health monitoring. REST API on TCP 8082.

**Key REST API endpoints (Guardium 12.x):**
- POST /restAPI/register_aggregator — register Collector to Aggregator
- GET /restAPI/aggregator_registration_status — poll registration status
- GET /restAPI/managed_units — list managed units on Aggregator
- POST /restAPI/policy — create security policy
- POST /restAPI/policy_rule — add rule to policy
- POST /restAPI/install_policy — activate policy on appliance
- GET /restAPI/policy — list policies
- GET /restAPI/system_info — appliance health/info

**Guardium CLI key commands:**
- store network interface ip <IP/prefix> — set static IP
- store network routes defaultroute <gateway> — set default gateway
- store network resolvers <dns1> <dns2> — set DNS servers
- restart network — apply network changes
- store aggregator <aggregator_ip> — register to aggregator (CLI method)
- show services — show running services

**Required firewall ports:**
- TCP 8075 — S-TAP to Collector communication
- TCP 8443 — REST API and Web UI
- TCP 16022 — Guardium appliance SSH/CLI
- TCP 8082 — GIM server
- TCP 9500 — Collector to Aggregator data transfer

**Supported database platforms:** Oracle, IBM Db2, Microsoft SQL Server, MySQL, PostgreSQL, SAP HANA, MongoDB, Cassandra, Teradata, Sybase/SAP ASE, Informix, Amazon RDS variants.

**Supported deployment platforms:** VMware vSphere (ISO from Datastore), AWS (custom AMI), GCP (custom image), Azure (managed image), KVM/libvirt.

**Guardium versions:** GDP 11.x (RHEL 7 base), GDP 12.x (RHEL 9 base). Version 12.2 introduced RHEL 9.6 base with updated isolinux menu (std=Collector entry 1, agg=Aggregator entry 3).

**Compliance frameworks supported:** PCI DSS, HIPAA, SOX, GDPR, CCPA, DPDP (India), NIST 800-53, ISO 27001.

**Sample policies:**
- BASELINE_AUDIT — audit all privileged DB user activity (DBA, sys, sa, root, postgres)
- PCI_DSS_AUDIT — audit cardholder data table access and failed logins
- HIPAA_AUDIT — audit PHI table access (patient%, phi%, medical%, health%)
- EXTRUSION_DETECT — alert on SELECT returning more than 1,000 rows

### 1.2 IBM Guardium Insights
IBM Guardium Insights is a SaaS and on-premises analytics platform that provides data risk intelligence across hybrid, multi-cloud environments. It aggregates data from Guardium Data Protection Collectors and provides risk scoring, compliance reports, and anomaly detection using AI/ML.

**Key capabilities:**
- Risk-based data activity analytics with ML anomaly detection
- Compliance reporting for PCI DSS, HIPAA, GDPR, SOX
- Integration with IBM QRadar SIEM via Guardium DSM
- Federated search across multiple Guardium environments
- Data classification and sensitive data discovery

**Deployment:** Available as SaaS on IBM Cloud or on-premises on Red Hat OpenShift 4.x.

### 1.3 IBM Guardium Key Lifecycle Manager (GKLM)
GKLM provides centralised cryptographic key management for IBM storage (DS8000, FlashSystem, Spectrum Virtualize, tape libraries) and third-party devices using KMIP 1.1/1.2.

**Key capabilities:**
- Centralised key lifecycle: creation, rotation, expiration, revocation
- KMIP protocol support for third-party device integration
- FIPS 140-2 Level 1 compliance
- Clustering for high availability
- Integration with IBM Db2, IBM Spectrum Scale encryption

### 1.4 IBM Guardium Data Encryption (GDE) / IBM Security Guardium Data Encryption
Formerly Vormetric Data Security Manager. Provides file-level, volume-level, and application-level encryption with policy-based access control and key management.

**Components:**
- Data Security Manager (DSM) — central management server for policies and keys
- Encryption Agent — installed on data servers; enforces encryption and access policies
- Live Data Transformation (LDT) — encrypt/re-key data without taking systems offline

---

## 2. IBM QRadar

### 2.1 IBM QRadar SIEM
IBM QRadar Security Information and Event Management is an enterprise SIEM platform that collects, normalises, correlates, and analyses security events and network flows in real time.

**Core components:**
- **All-in-One (AIO)** — single appliance combining all QRadar functions; suitable for smaller deployments.
- **Console** — central management UI and correlation engine. Runs the Ariel Query Engine for log searches.
- **Event Processor (EP)** — collects and processes log events from data sources. Communicates to Console on TCP 32004.
- **Flow Processor (FP)** — collects and processes network flow data (NetFlow, sFlow, IPFIX, JFlow).
- **Event Collector (EC)** — lightweight collector deployed close to data sources; forwards to Event Processors.
- **Data Node** — expands storage capacity for events and flows without adding processing power.

**Key ports:**
- TCP 443 — QRadar Console HTTPS UI
- TCP 32004 — Event Processor to Console communication
- TCP 514 / UDP 514 — Syslog ingestion
- TCP 8413 — QRadar API
- TCP 8080 — QRadar RESTful API (internal)

**Log sources and DSMs (Device Support Modules):**
QRadar supports 450+ DSM parsers. Key IBM integrations:
- IBM Guardium DSM — integrates Guardium audit events into QRadar
- IBM MaaS360 DSM — mobile device management events
- IBM Verify DSM — identity events
- IBM DataPower DSM — API gateway events

**QRadar rules and offenses:**
- Rules are correlation logic triggered when events/flows match defined conditions
- Offenses are alerts generated when rules fire; they aggregate related events
- Building Block — reusable rule component, not an offense trigger itself
- Custom rules use the QRadar Rules Engine (QRE) syntax

**QRadar AQL (Ariel Query Language):**
```
SELECT sourceip, destinationip, eventname, COUNT(*) AS cnt
FROM events
WHERE LOGSOURCETYPENAME(logsourceid) = 'IBM Guardium'
  AND eventname ILIKE '%policy violation%'
  LAST 24 HOURS
GROUP BY sourceip, destinationip, eventname
ORDER BY cnt DESC
LIMIT 100
```

**QRadar REST API:**
- GET /api/ariel/searches — list Ariel searches
- POST /api/ariel/searches — run AQL query
- GET /api/siem/offenses — list offenses
- GET /api/config/event_sources/log_source_management/log_sources — list log sources
- POST /api/reference_data/sets/{name} — add to reference set
- Authentication: SEC header with API token, or Basic Auth

**QRadar Use Case Manager (UCM):** Pre-built use cases aligned to MITRE ATT&CK framework; includes content packs for compliance (PCI DSS, HIPAA, NIST).

**QRadar Advisor with Watson:** AI-powered investigation; enriches offenses with threat intelligence from IBM X-Force, MITRE ATT&CK mapping, and related indicator correlation.

### 2.2 IBM QRadar SOAR (formerly Resilient)
IBM QRadar SOAR is a security orchestration, automation, and response platform. It manages incident response workflows through customisable playbooks.

**Key concepts:**
- **Incident** — a security event requiring response; has phases, tasks, artifacts, and a timeline
- **Playbook** — automated or semi-automated workflow triggered on incident creation or manually
- **Function** — Python-based integration that executes an action (e.g., block IP in firewall, lookup threat intel)
- **App Exchange** — IBM marketplace for pre-built SOAR integrations
- **Workflow** — Drag-and-drop automation designer using Resilient Circuits

**Integration with QRadar SIEM:** QRadar offenses can automatically create SOAR incidents via the built-in QRadar SOAR connector, bidirectionally synchronising status.

### 2.3 IBM QRadar EDR (formerly ReaQta)
Agent-based endpoint detection and response. Uses a NanoOS hypervisor-level agent for tamper-resistant endpoint monitoring. Provides behavioural threat detection and automated response.

### 2.4 IBM QRadar Network Detection and Response (NDR)
Network-based threat detection using ML and behavioural analytics on full packet capture and metadata. Formerly IBM QRadar Network Insights (QNI) and QRadar Network Traffic Analysis (NTA).

---

## 3. IBM Verify

### 3.1 IBM Verify (SaaS — formerly IBM Cloud Identity)
IBM Verify is IBM's cloud Identity-as-a-Service (IDaaS) platform providing:
- Single Sign-On (SSO) with SAML 2.0, OIDC, OAuth 2.0
- Multi-Factor Authentication (MFA): TOTP, push, SMS, email, FIDO2/WebAuthn
- Adaptive risk-based authentication
- User lifecycle management
- API access management

**Key integrations:** Active Directory/LDAP federation, Salesforce, ServiceNow, Microsoft 365, SAP.

### 3.2 IBM Security Verify Access (ISVA — formerly IBM Security Access Manager / ISAM)
On-premises or containerised (OpenShift) access management appliance providing:
- Web reverse proxy and session management
- Federated SSO (SAML, OIDC, OAuth 2.0, WS-Federation)
- Step-up authentication, contextual MFA
- API protection (OAuth/OIDC server)
- Risk-based access with IBM Verify Intelligence

**Deployment modes:** Hardware appliance, virtual appliance (OVA), Docker/Podman, Red Hat OpenShift.

**Key components:**
- Policy Decision Point (PDP) — WebSEAL reverse proxy that enforces access policy
- Policy Administration Point (PAP) — Local Management Interface (LMI) for configuration
- Policy Information Point (PIP) — retrieves attributes from LDAP/AD
- Runtime Security Services (ISAM Runtime) — provides OAuth/OIDC server and federation

### 3.3 IBM Verify Governance (formerly IBM Security Identity Governance and Intelligence / IGI)
Identity governance platform providing:
- Access certification and review campaigns
- Separation of duties (SoD) policy enforcement
- Role mining and role lifecycle management
- Provisioning workflows to target systems
- Compliance reporting for SOX, HIPAA, GDPR

### 3.4 IBM Verify Identity (formerly IBM Security Identity Manager / ISIM)
Automated identity lifecycle management:
- Provisioning and de-provisioning to target systems (AD, LDAP, SAP, databases)
- Password self-service and synchronisation
- Policy-based access request and approval workflows
- Recertification campaigns

---

## 4. IBM MaaS360

IBM MaaS360 is IBM's Unified Endpoint Management (UEM) platform providing:
- Mobile Device Management (MDM) — iOS, Android, macOS, Windows, ChromeOS
- Mobile Application Management (MAM) — app distribution, wrapping, and containerisation
- Mobile Content Management (MCM) — secure document access
- Endpoint security: threat management with Watson AI anomaly detection
- Zero Trust Network Access (ZTNA) integration
- Compliance enforcement and remote wipe

**Deployment:** SaaS only (IBM Cloud hosted). On-premises connector (MaaS360 Connector) for AD/LDAP integration and intranet resource access.

---

## 5. IBM Security Trusteer

IBM Trusteer provides fraud prevention and advanced malware protection for online banking and enterprise access:
- **Trusteer Rapport** — browser protection against man-in-the-browser (MitB) attacks and keylogging
- **Trusteer Pinpoint Detect** — device risk assessment and account takeover prevention
- **Trusteer Pinpoint Assure** — new account fraud detection using device and behavioural signals
- **Trusteer Mobile SDK** — mobile app integration for device risk signals

---

## 6. IBM Security Randori (Attack Surface Management)
IBM Randori Recon provides external attack surface management (EASM):
- Continuous discovery of externally exposed assets (IP ranges, domains, shadow IT)
- Asset inventory with risk scoring
- Target prioritisation for penetration testing
- Integration with QRadar SIEM for threat correlation

**IBM Randori Attack:** Automated red team platform for continuous adversarial simulation.

---

## 7. IBM Security X-Force

### 7.1 IBM X-Force Threat Intelligence
IBM X-Force is IBM's threat intelligence platform:
- Threat intelligence feeds: IP reputation, URL/domain reputation, file hashes, vulnerability data
- STIX/TAXII compatible for integration with SIEM/SOAR platforms
- X-Force Exchange — collaborative threat sharing platform
- Integration with QRadar Advisor with Watson and QRadar SOAR

### 7.2 IBM X-Force Red
IBM X-Force Red is IBM's offensive security team and platform:
- Penetration testing services (network, application, mobile, IoT, cloud)
- Adversary Simulation (red team exercises)
- Vulnerability Management as a Service
- Attack Surface Management

---

## 8. IBM DataPower Gateway
IBM DataPower Gateway is a multi-protocol, multi-channel security and integration appliance:
- API security enforcement (OAuth 2.0, JWT, API keys, mutual TLS)
- XML/JSON threat protection, schema validation, XSL transformation
- Protocol mediation: REST, SOAP, WebSockets, MQ, JMS
- Rate limiting, quota management, analytics
- Deployment: hardware appliance, virtual (Docker, OpenShift, VMware)

---

## 9. IBM Security Verify Privilege (formerly IBM Secret Server / Thycotic)
Privileged Access Management (PAM):
- Privileged credential vaulting (passwords, SSH keys, certificates)
- Just-in-time privileged access
- Session recording and monitoring
- Privileged Identity Management for service accounts
- Integration with ISVA and QRadar SIEM

---

## 10. IBM Security zSecure
Security intelligence for IBM Z (mainframe):
- **zSecure Audit** — RACF audit and compliance reporting
- **zSecure Alert** — real-time security event monitoring for z/OS
- **zSecure Admin** — RACF administration automation
- **zSecure CICS Toolkit** — CICS transaction security
- **zSecure Visual** — graphical RACF administration

**Integration:** zSecure Alert feeds events to QRadar SIEM via the zSecure DSM.

---

## 11. IBM Security Directory Services

### 11.1 IBM Security Directory Server (SDS)
LDAP v3 directory server for enterprise identity storage. Supports replication, SSL/TLS, SASL authentication. Used as PIP (Policy Information Point) with ISVA.

### 11.2 IBM Security Directory Integrator (SDI / formerly TDI)
Identity data synchronisation engine — aggregates, transforms, and synchronises identity data between LDAP directories, databases, HR systems, and IAM platforms.

---

## 12. IBM Security Common Event Infrastructure
Standards-based syslog and event forwarding framework used by IBM security products for integration with SIEM platforms. Supports RFC 5424 syslog, CEF (Common Event Format), LEEF (Log Event Extended Format — IBM QRadar's native format).

---

## 13. IBM OpenPages (Governance, Risk and Compliance)
IBM OpenPages is a GRC platform:
- IT Governance and Risk Management
- Operational Risk Management
- Regulatory Compliance Management (SOX, BCBS 239, GDPR, Basel III)
- Third-Party Risk Management (TPRM)
- Internal Audit Management
- AI-powered risk insights (watsonx integration)

---

## 14. IBM Security Key Relationships

| Integration | How |
|---|---|
| Guardium → QRadar | Guardium DSM; syslog LEEF events |
| Guardium → SOAR | QRadar offense triggers SOAR incident |
| ISVA → QRadar | ISVA DSM; authentication/access events |
| MaaS360 → QRadar | MaaS360 DSM; MDM compliance events |
| zSecure → QRadar | zSecure DSM; RACF audit events |
| X-Force → QRadar | QRadar Advisor with Watson threat enrichment |
| Guardium → Guardium Insights | Direct Collector data forwarding |
| ISVA → Verify | Federation bridge; SAML/OIDC |
| Randori → QRadar | Attack surface data imported as reference sets |

---

## 15. IBM Security Deployment & Operations Reference

### Guardium Deployment Checklist
1. Deploy Collector VM (KVM/vSphere/AWS/GCP/Azure) from Guardium ISO
2. Complete first-boot NM_setup wizard on console (set static IP, gateway, DNS, hostname)
3. Deploy Aggregator VM with same process
4. Register Collector to Aggregator: POST /restAPI/register_aggregator
5. Deploy sample policies via REST API
6. Install S-TAP on database servers (SSH RPM / WinRM MSI / GIM push)
7. Validate agent connectivity: check S-TAP status in Guardium UI

### QRadar Deployment Checklist
1. Deploy QRadar Console (All-in-One for <1000 EPS, separate Event Processors for larger)
2. Configure log sources (auto-discovery or manual DSM configuration)
3. Tune rules — disable noisy low-value rules, adjust thresholds
4. Configure Guardium DSM for database activity events
5. Enable QRadar Advisor with Watson (requires IBM X-Force API key)
6. Connect QRadar SOAR for automated incident response

### IBM Security Common Integration Patterns
- **Defence in depth:** Perimeter (DataPower) → Identity (ISVA/Verify) → Endpoint (MaaS360/EDR) → Database (Guardium) → SIEM (QRadar) → SOAR (QRadar SOAR)
- **Zero Trust:** MaaS360 ZTNA + ISVA step-up auth + Guardium DAM + QRadar continuous monitoring
- **Compliance automation:** Guardium policies → QRadar correlation → SOAR automated evidence collection → OpenPages GRC reporting
