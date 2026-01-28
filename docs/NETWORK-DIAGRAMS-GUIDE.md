# Network Diagrams Guide

**Date:** January 27, 2026

## Available Diagrams

### Version 1: Communication Flow Diagram
**File:** `docs/diagrams/network-topology.png`
**Script:** `./scripts/generate-network-diagram.sh`

**Purpose:** Shows the communication patterns and traffic flows

**What it shows:**
- ✅ Main path: Fully private Event Hub communication flow
- ⚠️ Comparison path: Webhook communication flow
- 📊 Simplified view focusing on data flow
- 🎯 Clear distinction between private and public paths

**Best for:**
- Understanding communication patterns
- Explaining the PoC to stakeholders
- Comparing webhook vs Event Hub approaches
- Documentation and presentations

**View it:**
```bash
open docs/diagrams/network-topology.png
```

---

### Version 2: Core Infrastructure Topology
**File:** `docs/diagrams/network-topology-v2.png`
**Script:** `./scripts/generate-network-diagram-v2.sh`

**Purpose:** Shows the core PoC infrastructure with real traffic flows

**What it shows:**
- ✅ **Subscriptions:**
  - Subscription 1 (primary infrastructure)
  - Subscription 2 (cross-subscription function)

- ✅ **VNETs and Networking:**
  - 3 VNETs with address spaces (10.0.0.0/16, 10.1.0.0/16, 10.2.0.0/16)
  - Subnets with CIDR blocks and delegations
  - NSG/Firewall status
  - VNET peering (within and cross-subscription)

- ✅ **Core Services:**
  - Function Apps (Python and .NET) with VNET integration
  - Event Grid Topic with private endpoint (10.1.1.4)
  - Event Hub Namespace with private endpoint (10.1.1.5)
  - Private DNS zones with VNET links

- ✅ **Private Endpoints:**
  - Private endpoint IPs
  - Connection states
  - Service attachments

- ✅ **Traffic Flows (numbered):**
  - ① .NET → Event Grid (fully private via VNET peering)
  - ② Event Grid → Event Hub (fully private via Azure backbone)
  - ③ Event Hub → .NET (fully private via VNET peering)
  - Python → Event Grid (private publish)
  - Event Grid → Python (public webhook delivery)

- ✅ **DNS Resolution:**
  - Private DNS zones
  - VNET links (including cross-subscription)

**Best for:**
- Technical reviews
- Infrastructure documentation
- Understanding network topology
- Troubleshooting connectivity
- Architecture discussions

**View it:**
```bash
open docs/diagrams/network-topology-v2.png
```

---

## Comparison

| Feature | V1: Communication Flow | V2: Core Infrastructure |
|---------|----------------------|------------------------|
| **Focus** | Data flow patterns | Network topology & core services |
| **Detail Level** | Simplified | Focused on PoC essentials |
| **Resources Shown** | Key services only | Core: VNETs, Functions, Event Grid, Event Hub, Private Endpoints |
| **Network Details** | Basic | Full (subnets, IPs, peering, NSG/FW status) |
| **Traffic Flows** | Emphasized | Numbered with full details |
| **Supporting Services** | Not shown | Not shown (storage, plans, etc.) |
| **Subscriptions** | Implied | Explicit with boundaries |
| **File Size** | Smaller | Medium |
| **Best Use Case** | Presentations | Technical documentation |

---

## What Each Diagram Shows

### Communication Patterns (V1)

```
┌─────────────────────────────────────────────────────────────┐
│ MAIN PATH: Fully Private Event Hub                         │
│                                                             │
│  .NET Publish                                              │
│       ↓ (via VNET peering - PRIVATE)                       │
│  Event Grid (10.1.1.4)                                     │
│       ↓ (backbone - PRIVATE)                               │
│  Event Hub (10.1.1.5)                                      │
│       ↓ (via VNET peering - PRIVATE)                       │
│  .NET Consume                                              │
│                                                             │
│  100% PRIVATE COMMUNICATION                                 │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ COMPARISON: Webhook Path                                   │
│                                                             │
│  Python Publish                                             │
│       ↓ (via VNET peering - PRIVATE)                       │
│  Event Grid (10.1.1.4)                                     │
│       ↓ (webhook - PUBLIC)                                 │
│  Python Consume                                             │
│                                                             │
│  ⚠️ Webhook uses public internet                           │
└─────────────────────────────────────────────────────────────┘
```

### Infrastructure Layout (V2)

```
┌───────────────────────────────────────────────────────────────┐
│ SUBSCRIPTION 1 (6391aa55-...)                                │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ VNET 1: Python Function (10.0.0.0/16)                  │ │
│  │                                                         │ │
│  │  [Subnet: 10.0.1.0/24]                                 │ │
│  │   • Python Function (func-eventgrid-*)                 │ │
│  │   • Storage Account (stfunc*)                          │ │
│  │   • App Service Plan (asp-function-*)                  │ │
│  │   • Application Insights (appi-function-*)             │ │
│  │                                                         │ │
│  │  VNET Integration: ✓                                   │ │
│  │  vnetRouteAllEnabled: true                             │ │
│  └─────────────────────────────────────────────────────────┘ │
│                          ↕ VNET Peering                      │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ VNET 2: Event Grid & Event Hub (10.1.0.0/16)          │ │
│  │                                                         │ │
│  │  [Private Endpoint Subnet: 10.1.1.0/27]               │ │
│  │   • Event Grid PE (10.1.1.4)                           │ │
│  │   • Event Hub PE (10.1.1.5)                            │ │
│  │                                                         │ │
│  │  [PaaS Services]                                       │ │
│  │   • Event Grid Topic (evgt-poc-*)                      │ │
│  │   • Event Hub Namespace (evhns-eventgrid-*)            │ │
│  │   • Event Hub (events, 2 partitions)                   │ │
│  │                                                         │ │
│  │  Public Access: DISABLED                               │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  [Shared Services]                                           │
│   • Private DNS: privatelink.eventgrid.azure.net            │
│   • Private DNS: privatelink.servicebus.windows.net         │
│   • Log Analytics Workspace                                 │
│                                                               │
│  [Resource Groups]                                           │
│   • rg-eventgrid-vnet-poc-network                           │
│   • rg-eventgrid-vnet-poc-function                          │
│   • rg-eventgrid-vnet-poc-eventgrid                         │
│   • rg-eventgrid-vnet-poc-eventhub                          │
└───────────────────────────────────────────────────────────────┘
                          ↕
              Cross-Subscription VNET Peering
                          ↕
┌───────────────────────────────────────────────────────────────┐
│ SUBSCRIPTION 2 (4f120dcf-...)                                │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ VNET 3: .NET Function (10.2.0.0/16)                    │ │
│  │                                                         │ │
│  │  [Subnet: 10.2.1.0/24]                                 │ │
│  │   • .NET Function (func-dotnet-*)                      │ │
│  │   • Storage Account (stdotnetfn*)                      │ │
│  │   • App Service Plan (asp-dotnet-function-*)           │ │
│  │   • Application Insights (appi-dotnet-function-*)      │ │
│  │                                                         │ │
│  │  VNET Integration: ✓                                   │ │
│  │  vnetRouteAllEnabled: true                             │ │
│  │                                                         │ │
│  │  Cross-Sub IAM:                                        │ │
│  │   • Event Grid Data Sender (Sub 1)                     │ │
│  │   • Event Hub Data Receiver (Sub 1)                    │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  [Resource Groups]                                           │
│   • rg-eventgrid-vnet-poc-dotnet-network                    │
│   • rg-eventgrid-vnet-poc-dotnet-function                   │
└───────────────────────────────────────────────────────────────┘
```

---

## Key Features Highlighted

### In V2 Diagram:

**1. Network Segregation:**
- Each VNET has its own address space
- Subnets properly sized and delegated
- Private endpoint subnet isolated

**2. Cross-Subscription Architecture:**
- Clear boundary between subscriptions
- VNET peering spans subscriptions
- IAM roles explicitly shown

**3. Private Endpoints:**
- Located in dedicated subnet (10.1.1.0/27)
- IP addresses shown (10.1.1.4, 10.1.1.5)
- Connections to PaaS services visualized

**4. Function Dependencies:**
- Storage accounts for function state
- App Service Plans for compute
- Application Insights for telemetry
- All relationships shown

**5. DNS Resolution:**
- Private DNS zones in Subscription 1
- Links to all 3 VNETs (including cross-sub)
- A records resolve to private IPs

**6. Identity & Access:**
- Managed identities for functions
- System identity for Event Grid
- Cross-subscription role assignments
- App registrations for Entra ID auth

**7. Monitoring Stack:**
- Application Insights per function
- Log Analytics workspace
- Diagnostic settings configured

**8. Traffic Flows:**
- 🟢 Green solid lines: Fully private paths
- 🔴 Red dashed lines: Public webhook path
- 🟣 Purple dashed lines: DNS resolution
- ⚫ Black dotted lines: IAM relationships

---

## When to Use Each Diagram

### Use V1 (Communication Flow) When:
- ✅ Presenting to stakeholders
- ✅ Explaining the PoC concept
- ✅ Comparing webhook vs Event Hub
- ✅ Creating documentation
- ✅ Quick reference
- ✅ Focus is on "what happens" not "how it's built"

### Use V2 (Full Topology) When:
- ✅ Technical architecture reviews
- ✅ Infrastructure documentation
- ✅ Troubleshooting issues
- ✅ Planning changes or additions
- ✅ Understanding resource relationships
- ✅ Security audits
- ✅ Cost analysis
- ✅ Focus is on "how it's built" and all components

### Use Both When:
- ✅ Complete documentation package
- ✅ Handover to operations team
- ✅ Architecture decision records
- ✅ Training materials

---

## Generating the Diagrams

### Generate V1 (Communication Flow)
```bash
./scripts/generate-network-diagram.sh
open docs/diagrams/network-topology.png
```

### Generate V2 (Full Topology)
```bash
./scripts/generate-network-diagram-v2.sh
open docs/diagrams/network-topology-v2.png
```

### Regenerate Both
```bash
./scripts/generate-network-diagram.sh
./scripts/generate-network-diagram-v2.sh
```

---

## File Formats

Both diagrams are generated in multiple formats:

| Format | Extension | Best For |
|--------|-----------|----------|
| **DOT** | `.dot` | Source file, version control |
| **PNG** | `.png` | Viewing, presentations, documentation |
| **SVG** | `.svg` | Scalable graphics, web, high-quality print |

**Tip:** Use SVG for documents that may be viewed at different zoom levels or screen sizes.

---

## Customization

### Modify V1 (Communication Flow)
Edit: `scripts/generate-network-diagram.sh`
- Focus: Communication patterns
- Keep simple and clear
- Highlight main vs comparison paths

### Modify V2 (Full Topology)
Edit: `scripts/generate-network-diagram-v2.sh`
- Add new resources as they're deployed
- Update address spaces if changed
- Add new traffic flows
- Keep comprehensive and accurate

### Tips for Customization:
1. Keep DOT syntax valid (use online validators)
2. Test with `dot -Tpng file.dot -o test.png`
3. Use consistent colors and styles
4. Add version numbers to diagrams
5. Document changes in git commits

---

## Legend Reference

### V2 Diagram Legend

| Symbol | Meaning | Example |
|--------|---------|---------|
| 🟢 Green solid arrow | Fully private traffic | VNET peering communication |
| 🟠 Orange dashed arrow | Hybrid (private publish, public deliver) | Webhook path |
| 🟣 Purple dashed line | DNS resolution | Private DNS links |
| ⚫ Black dotted line | IAM relationship | Role assignments |
| 🟡 Gold hexagon | Private endpoint | PE with private IP |
| 🔵 Blue double octagon | PaaS service | Event Grid, Event Hub |
| 🟢 Green component | Compute resource | Functions |
| 🟠 Orange cylinder | Storage/data | Storage accounts |
| 🟣 Purple cylinder | Observability | App Insights, DNS |
| 📁 Folder | Resource group | Container for resources |

---

## Diagram Sizes

### V1 (Communication Flow)
- Optimized for: Presentations (16:9, 4:3)
- File size: ~100-200 KB
- Dimensions: Automatic (compact)

### V2 (Full Topology)
- Optimized for: A3/A4 print, large screens
- File size: ~300-500 KB
- DPI: 150 (high quality)
- Dimensions: Automatic (comprehensive)

**Tip:** If V2 is too large, view the SVG version which scales perfectly.

---

## Related Documentation

- **Verification Guide:** `docs/NETWORK-VERIFICATION-GUIDE.md`
- **Deployment Report:** `docs/EVENT-HUB-DEPLOYMENT-REPORT.md`
- **Verification Summary:** `docs/NETWORK-VERIFICATION-SUMMARY.md`
- **Fixes Summary:** `docs/FIXES-SUMMARY.md`

---

## Quick Reference

```bash
# View V1 (communication flow)
open docs/diagrams/network-topology.png

# View V2 (full topology)
open docs/diagrams/network-topology-v2.png

# Regenerate V1
./scripts/generate-network-diagram.sh

# Regenerate V2
./scripts/generate-network-diagram-v2.sh

# View source DOT files
cat docs/diagrams/network-topology.dot
cat docs/diagrams/network-topology-v2.dot
```

---

**Last Updated:** January 27, 2026
**Diagrams:** v1 (Communication Flow), v2 (Full Topology)
**Status:** Both generated and ready to use ✅
