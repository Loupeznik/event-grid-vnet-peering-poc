# Network Diagram V2 - Update Summary

**Date:** January 27, 2026
**Change:** Simplified V2 to show only core PoC services

---

## What Changed

### Before (V2 - Too Detailed)
❌ Showed all Azure resources:
- Storage accounts
- App Service Plans
- Application Insights
- Log Analytics
- Resource groups
- App registrations
- All dependencies and relationships

**Problem:** Too much detail, overwhelming for understanding the core PoC

### After (V2 - Core Services Focus)
✅ Shows only essential PoC components:
- **Subscriptions** (2 subscriptions with clear boundaries)
- **Function Apps** (Python and .NET with VNET integration details)
- **VNETs** (3 VNETs with subnets, address spaces, delegations)
- **Private Endpoints** (with IPs: 10.1.1.4, 10.1.1.5)
- **Event Grid Topic** (with private endpoint configuration)
- **Event Hub** (with private endpoint configuration)
- **VNET Peering** (including cross-subscription)
- **Private DNS Zones** (with VNET links)
- **Traffic Flows** (numbered with full path details)

**Result:** Clean, focused diagram showing the network topology and communication patterns

---

## What V2 Now Shows

### 1. Subscription Architecture
```
┌─────────────────────────────────────────────────┐
│ Subscription 1 (6391aa55-...)                  │
│                                                 │
│  • VNET 1: Python Function (10.0.0.0/16)      │
│  • VNET 2: Event Grid + Event Hub (10.1.0.0/16)│
│  • Private DNS Zones                            │
│                                                 │
└─────────────────────────────────────────────────┘
                    ↕
         Cross-Subscription VNET Peering
                    ↕
┌─────────────────────────────────────────────────┐
│ Subscription 2 (4f120dcf-...)                  │
│                                                 │
│  • VNET 3: .NET Function (10.2.0.0/16)        │
│                                                 │
└─────────────────────────────────────────────────┘
```

### 2. VNET Details

**VNET 1 (10.0.0.0/16):**
- Subnet: snet-function (10.0.1.0/24)
- Delegation: Microsoft.Web/serverFarms
- NSG: None
- Contains: Python Function App with VNET integration

**VNET 2 (10.1.0.0/16):**
- Subnet: Private Endpoint Subnet (10.1.1.0/27)
- NSG: None
- Route Table: None
- Contains:
  - Event Grid Private Endpoint (10.1.1.4)
  - Event Hub Private Endpoint (10.1.1.5)

**VNET 3 (10.2.0.0/16):**
- Subnet: snet-dotnet-function (10.2.1.0/24)
- Delegation: Microsoft.Web/serverFarms
- NSG: None
- Contains: .NET Function App with VNET integration

### 3. Function Apps

**Python Function (func-eventgrid-*):**
- Runtime: Python 3.11
- VNET Integration: ✓
- vnetRouteAllEnabled: true
- Functions:
  - publish_event (HTTP trigger)
  - consume_event (Event Grid trigger)

**.NET Function (func-dotnet-*):**
- Runtime: .NET 10 (isolated)
- VNET Integration: ✓
- vnetRouteAllEnabled: true
- Functions:
  - PublishEvent (HTTP trigger)
  - ConsumeEvent (Event Grid trigger)
  - ConsumeEventFromEventHub (Event Hub trigger)

### 4. Private Endpoints

**Event Grid Private Endpoint (pe-eventgrid-*):**
- Private IP: 10.1.1.4
- Connection State: Approved
- Target: Event Grid Topic

**Event Hub Private Endpoint (pe-eventhub-*):**
- Private IP: 10.1.1.5
- Connection State: Approved
- Target: Event Hub Namespace

### 5. PaaS Services

**Event Grid Topic (evgt-poc-*):**
- Public Network Access: Disabled
- Private Endpoint Only: ✓
- Event Subscriptions:
  1. func-python-sub → Python Function (webhook)
  2. eventgrid-to-eventhub → Event Hub

**Event Hub Namespace (evhns-eventgrid-*):**
- Event Hub: events
- Partitions: 2
- Public Network Access: Disabled
- Private Endpoint Only: ✓

### 6. VNET Peering

**Within Subscription 1:**
- peer-function-to-eventgrid (VNET 1 → VNET 2)
- peer-eventgrid-to-function (VNET 2 → VNET 1)
- State: Connected
- AllowForwardedTraffic: true

**Cross-Subscription:**
- peer-eventgrid-to-dotnet (Sub 1: VNET 2 → Sub 2: VNET 3)
- peer-dotnet-to-eventgrid (Sub 2: VNET 3 → Sub 1: VNET 2)
- State: Connected
- AllowForwardedTraffic: true

### 7. Traffic Flows (Numbered)

**Fully Private Event Hub Path:**
1. ① .NET → Event Grid Private Endpoint
   - Path: 10.2.x.x → 10.1.1.4
   - Protocol: HTTPS
   - Auth: Managed Identity
   - Route: VNET peering (fully private)

2. ② Event Grid → Event Hub
   - Protocol: AMQP
   - Auth: System Managed Identity
   - Route: Azure backbone (fully private)

3. ③ Event Hub Private Endpoint → .NET
   - Path: 10.1.1.5 → 10.2.x.x
   - Protocol: AMQP (poll/consume)
   - Auth: Managed Identity
   - Route: VNET peering (fully private)

**Webhook Path (Comparison):**
- Python → Event Grid: Private (VNET peering)
- Event Grid → Python: Public (webhook via Azure backbone)

### 8. Private DNS

**Zones:**
- privatelink.eventgrid.azure.net
- privatelink.servicebus.windows.net

**VNET Links:**
- Linked to VNET 1 (Python)
- Linked to VNET 2 (Event Grid/Event Hub)
- Linked to VNET 3 (.NET, cross-subscription)

---

## What's NOT Shown (Intentionally Simplified)

❌ **Supporting Resources:**
- Storage accounts
- App Service Plans
- Application Insights
- Log Analytics Workspace

❌ **IAM Details:**
- Managed identities (mentioned but not visualized)
- Role assignments
- App registrations

❌ **Resource Groups:**
- Not shown (focus on services, not organization)

❌ **Monitoring:**
- Diagnostic settings
- Log collection

**Why?** These are important but not essential for understanding the core network topology and traffic flow of the PoC.

---

## Diagram Comparison

### V1: Communication Flow
- **Purpose:** Show data flow patterns
- **Style:** Simplified, abstract
- **Best for:** Presentations, explaining concepts

### V2: Core Infrastructure
- **Purpose:** Show network topology and services
- **Style:** Technical but focused
- **Best for:** Technical documentation, architecture reviews

### When to Use Each:

**Use V1 when:**
- Presenting to non-technical stakeholders
- Explaining the PoC concept
- Comparing webhook vs Event Hub approaches
- Creating quick reference guides

**Use V2 when:**
- Documenting the infrastructure
- Technical architecture reviews
- Troubleshooting network issues
- Understanding VNET topology
- Planning changes or additions
- Security reviews

---

## Files Generated

```bash
# View V1 (communication flow)
open docs/diagrams/network-topology.png

# View V2 (core infrastructure)
open docs/diagrams/network-topology-v2.png

# Regenerate V2
./scripts/generate-network-diagram-v2.sh
```

**Formats Available:**
- `.dot` - Source file (text, version control friendly)
- `.png` - Image (best for viewing, documentation)
- `.svg` - Scalable vector (best for zooming, web)

---

## Key Improvements in V2

✅ **Focused:** Only core PoC services shown
✅ **Clear:** Network topology is easy to understand
✅ **Complete:** All essential networking details included
✅ **Numbered Flows:** Traffic paths are clearly labeled
✅ **Subscription Boundaries:** Cross-subscription architecture visible
✅ **Technical Details:** Subnets, IPs, delegations, NSG status

---

## Summary

**V2 is now simplified to focus on the core PoC infrastructure:**
- Subscriptions
- VNETs and subnets
- Function Apps (with VNET integration)
- Event Grid and Event Hub (with private endpoints)
- VNET peering (including cross-subscription)
- Private DNS zones
- Real traffic flows (numbered and detailed)

**This provides the right level of detail for technical documentation without overwhelming with supporting resources.**

---

**Status:** ✅ V2 simplified and regenerated
**Date:** January 27, 2026
**Ready for:** Technical documentation, architecture reviews
