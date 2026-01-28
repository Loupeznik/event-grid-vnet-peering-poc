#!/bin/bash
set -e

echo "=================================================="
echo "Azure Network Topology Diagram v2 - Core Infrastructure"
echo "=================================================="
echo ""

# Check if graphviz is installed
if ! command -v dot &> /dev/null; then
    echo "⚠️  Graphviz not installed. Install it to generate PNG diagram:"
    echo "   macOS:   brew install graphviz"
    echo "   Linux:   apt-get install graphviz"
    echo "   Windows: choco install graphviz"
    echo ""
    echo "Will generate .dot file only (text format)"
    GRAPHVIZ_AVAILABLE=false
else
    echo "✅ Graphviz is installed"
    GRAPHVIZ_AVAILABLE=true
fi

# Get terraform outputs
cd "$(dirname "$0")/../terraform"
PYTHON_FUNC_NAME=$(terraform output -raw function_app_name 2>/dev/null || echo "func-eventgrid-3tlv1w")
DOTNET_FUNC_NAME=$(terraform output -raw dotnet_function_app_name 2>/dev/null || echo "func-dotnet-3tlv1w")
EVENTGRID_TOPIC=$(terraform output -raw eventgrid_topic_name 2>/dev/null || echo "evgt-poc-3tlv1w")
EVENTHUB_NS=$(terraform output -raw eventhub_namespace_name 2>/dev/null || echo "evhns-eventgrid-3tlv1w")
EVENTHUB_NAME=$(terraform output -raw eventhub_name 2>/dev/null || echo "events")
PYTHON_VNET=$(terraform output -raw function_vnet_name 2>/dev/null || echo "vnet-function-3tlv1w")
EVENTGRID_VNET=$(terraform output -raw eventgrid_vnet_name 2>/dev/null || echo "vnet-eventgrid-3tlv1w")
DOTNET_VNET=$(terraform output -raw dotnet_vnet_name 2>/dev/null || echo "vnet-dotnet-3tlv1w")

# Create output directory
mkdir -p ../docs/diagrams

# Generate DOT file
DOT_FILE="../docs/diagrams/network-topology-v2.dot"
echo "Generating core infrastructure topology diagram..."

cat > "$DOT_FILE" << 'EOF'
digraph azure_core_topology {
    # Graph settings
    rankdir=TB;
    ranksep=1.2;
    nodesep=1.0;
    splines=polyline;
    fontname="Arial";
    fontsize=14;
    compound=true;

    # Title
    labelloc="t";
    label="Azure Event Grid VNET Peering PoC\nCore Infrastructure & Traffic Flow";
    fontsize=18;
    fontname="Arial Bold";

    # Node styles
    node [shape=box, style="rounded,filled", fontname="Arial", fontsize=11];
    edge [fontname="Arial", fontsize=10];

    # ============================================================================
    # SUBSCRIPTION 1
    # ============================================================================
    subgraph cluster_sub1 {
        label="Subscription 1\n6391aa55-ec4d-40af-bc22-2e7ad5b7eda5";
        style="filled,bold";
        color="#E3F2FD";
        fontsize=14;
        fontname="Arial Bold";
        penwidth=3;

        # VNET 1 - Python Function
        subgraph cluster_vnet1 {
            label="VNET 1: vnet-function-*\n10.0.0.0/16";
            style="filled,bold";
            color="#90CAF9";
            fontsize=12;
            penwidth=2;

            subnet1 [label="Subnet: snet-function\n10.0.1.0/24\nDelegation: Microsoft.Web/serverFarms\nNSG: None", shape=box, fillcolor="#BBDEFB"];

            python_func [label="Azure Function App\nfunc-eventgrid-*\n━━━━━━━━━━━━━━\nRuntime: Python 3.11\nVNET Integration: ✓\nvnetRouteAllEnabled: true\n━━━━━━━━━━━━━━\nFunctions:\n• publish_event (HTTP)\n• consume_event (Event Grid)", fillcolor="#4CAF50", fontcolor="white", shape=component, penwidth=2];

            subnet1 -> python_func [style=dashed, color="#666666", label="integrated"];
        }

        # VNET 2 - Event Grid & Event Hub
        subgraph cluster_vnet2 {
            label="VNET 2: vnet-eventgrid-*\n10.1.0.0/16";
            style="filled,bold";
            color="#90CAF9";
            fontsize=12;
            penwidth=2;

            subnet2 [label="Private Endpoint Subnet\n10.1.1.0/27\nNSG: None\nRoute Table: None", shape=box, fillcolor="#BBDEFB"];

            # Private Endpoints
            eg_pe [label="Private Endpoint\npe-eventgrid-*\n━━━━━━━━━━━━━━\nPrivate IP: 10.1.1.4\nConnection State: Approved", fillcolor="#FFD700", fontcolor="black", shape=hexagon, penwidth=2];

            eh_pe [label="Private Endpoint\npe-eventhub-*\n━━━━━━━━━━━━━━\nPrivate IP: 10.1.1.5\nConnection State: Approved", fillcolor="#FFD700", fontcolor="black", shape=hexagon, penwidth=2];

            subnet2 -> eg_pe [style=dashed, color="#666666", label="contains"];
            subnet2 -> eh_pe [style=dashed, color="#666666", label="contains"];
        }

        # Event Grid (PaaS)
        eventgrid [label="Event Grid Topic\nevgt-poc-*\n━━━━━━━━━━━━━━\nPublic Network Access: Disabled\nPrivate Endpoint Only: ✓\n━━━━━━━━━━━━━━\nEvent Subscriptions:\n1. func-python-sub → Python Function\n2. eventgrid-to-eventhub → Event Hub", fillcolor="#2196F3", fontcolor="white", shape=doubleoctagon, penwidth=2];

        # Event Hub (PaaS)
        eventhub [label="Event Hub Namespace\nevhns-eventgrid-*\n━━━━━━━━━━━━━━\nEvent Hub: events\nPartitions: 2\nPublic Network Access: Disabled\nPrivate Endpoint Only: ✓", fillcolor="#2196F3", fontcolor="white", shape=doubleoctagon, penwidth=2];

        # Private DNS
        dns [label="Private DNS Zones\n━━━━━━━━━━━━━━\nprivatelink.eventgrid.azure.net\nprivatelink.servicebus.windows.net\n━━━━━━━━━━━━━━\nLinked to: VNET 1, 2, 3", fillcolor="#9C27B0", fontcolor="white", shape=cylinder];

        # Connections within Sub 1
        eventgrid -> eg_pe [label="attached to", dir=none, color="#2196F3", penwidth=2];
        eventhub -> eh_pe [label="attached to", dir=none, color="#2196F3", penwidth=2];
    }

    # ============================================================================
    # SUBSCRIPTION 2
    # ============================================================================
    subgraph cluster_sub2 {
        label="Subscription 2\n4f120dcf-daee-4def-b87c-4139995ca024";
        style="filled,bold";
        color="#E8F5E9";
        fontsize=14;
        fontname="Arial Bold";
        penwidth=3;

        # VNET 3 - .NET Function
        subgraph cluster_vnet3 {
            label="VNET 3: vnet-dotnet-*\n10.2.0.0/16";
            style="filled,bold";
            color="#81C784";
            fontsize=12;
            penwidth=2;

            subnet3 [label="Subnet: snet-dotnet-function\n10.2.1.0/24\nDelegation: Microsoft.Web/serverFarms\nNSG: None", shape=box, fillcolor="#C8E6C9"];

            dotnet_func [label="Azure Function App\nfunc-dotnet-*\n━━━━━━━━━━━━━━\nRuntime: .NET 10 (isolated)\nVNET Integration: ✓\nvnetRouteAllEnabled: true\n━━━━━━━━━━━━━━\nFunctions:\n• PublishEvent (HTTP)\n• ConsumeEvent (Event Grid)\n• ConsumeEventFromEventHub", fillcolor="#4CAF50", fontcolor="white", shape=component, penwidth=2];

            subnet3 -> dotnet_func [style=dashed, color="#666666", label="integrated"];
        }
    }

    # ============================================================================
    # VNET PEERING
    # ============================================================================

    # Peering within Subscription 1
    subnet1 -> subnet2 [label="VNET Peering\npeer-function-to-eventgrid\n↕\npeer-eventgrid-to-function\n━━━━━━━━━━━━━━\nState: Connected\nAllowForwardedTraffic: true", color="#2196F3", penwidth=3, style=bold, dir=both];

    # Cross-Subscription Peering
    subnet2 -> subnet3 [label="Cross-Subscription\nVNET Peering\npeer-eventgrid-to-dotnet (Sub1)\n↕\npeer-dotnet-to-eventgrid (Sub2)\n━━━━━━━━━━━━━━\nState: Connected\nAllowForwardedTraffic: true", color="#4CAF50", penwidth=3, style=bold, dir=both];

    # ============================================================================
    # DNS RESOLUTION
    # ============================================================================

    dns -> python_func [label="DNS resolution\n(VNET link)", style=dashed, color="#9C27B0"];
    dns -> dotnet_func [label="DNS resolution\n(VNET link)", style=dashed, color="#9C27B0"];

    # ============================================================================
    # TRAFFIC FLOWS - FULLY PRIVATE (EVENT HUB PATH)
    # ============================================================================

    # Flow 1: .NET publishes to Event Grid
    dotnet_func -> eg_pe [label="①  HTTP POST\nPublish Event\n━━━━━━━━━━━━━━\nPath: 10.2.x.x → 10.1.1.4\nAuth: Managed Identity\nDNS: privatelink.eventgrid.azure.net\n━━━━━━━━━━━━━━\nFULLY PRIVATE (VNET peering)", color="#4CAF50", penwidth=3, fontcolor="#2E7D32", fontsize=11];

    # Flow 2: Event Grid to Event Hub
    eventgrid -> eventhub [label="②  Event Delivery\n━━━━━━━━━━━━━━\nEvent Grid → Event Hub\nAuth: System Managed Identity\nProtocol: AMQP\n━━━━━━━━━━━━━━\nFULLY PRIVATE (Azure backbone)", color="#4CAF50", penwidth=3, fontcolor="#2E7D32", fontsize=11];

    # Flow 3: .NET consumes from Event Hub
    eh_pe -> dotnet_func [label="③  Poll/Consume\nEvent Hub Trigger\n━━━━━━━━━━━━━━\nPath: 10.1.1.5 → 10.2.x.x\nAuth: Managed Identity\nDNS: privatelink.servicebus.windows.net\n━━━━━━━━━━━━━━\nFULLY PRIVATE (VNET peering)", color="#4CAF50", penwidth=3, fontcolor="#2E7D32", fontsize=11];

    # ============================================================================
    # TRAFFIC FLOWS - WEBHOOK (COMPARISON)
    # ============================================================================

    # Flow 4: Python publishes to Event Grid
    python_func -> eg_pe [label="HTTP POST\nPublish Event\n━━━━━━━━━━━━━━\nPath: 10.0.x.x → 10.1.1.4\nAuth: Managed Identity\n━━━━━━━━━━━━━━\nPRIVATE (VNET peering)", color="#FF9800", penwidth=2, fontcolor="#E65100", fontsize=10];

    # Flow 5: Event Grid webhook to Python
    eventgrid -> python_func [label="Webhook Delivery\n━━━━━━━━━━━━━━\nEvent Grid → Python Function\nProtocol: HTTPS (webhook)\nIP Restrictions: AzureEventGrid tag\n━━━━━━━━━━━━━━\nPUBLIC (Azure backbone)", color="#F44336", penwidth=2, fontcolor="#C62828", fontsize=10, style=dashed];

    # ============================================================================
    # LEGEND
    # ============================================================================

    subgraph cluster_legend {
        label="Legend";
        style=filled;
        color="#FFFFFF";
        fontsize=12;
        rank=sink;

        legend_private [label="🟢 Fully Private Path\n(VNET peering)", fillcolor="#4CAF50", fontcolor="white", penwidth=2];
        legend_hybrid [label="🟠 Publish: Private\n🔴 Delivery: Public (webhook)", fillcolor="#FF9800", fontcolor="white"];
        legend_pe [label="Private Endpoint\n(10.1.1.x)", fillcolor="#FFD700", fontcolor="black", shape=hexagon];
        legend_paas [label="PaaS Service", fillcolor="#2196F3", fontcolor="white", shape=doubleoctagon];
        legend_func [label="Function App", fillcolor="#4CAF50", fontcolor="white", shape=component];
        legend_vnet [label="VNET / Subnet", fillcolor="#90CAF9", fontcolor="black", shape=box];

        legend_private -> legend_hybrid [style=invis];
        legend_hybrid -> legend_pe [style=invis];
        legend_pe -> legend_paas [style=invis];
        legend_paas -> legend_func [style=invis];
        legend_func -> legend_vnet [style=invis];
    }

    # Notes
    note [label="✅ Event Hub Path: 100% Private\n(No public internet at any point)\n\n⚠️  Webhook Path: Hybrid\n(Private publish, public delivery)", shape=note, fillcolor="#FFEB3B", fontcolor="black", penwidth=2, fontsize=11];
}
EOF

echo "✅ Network topology DOT file created: $DOT_FILE"
echo ""

# Generate PNG if graphviz is available
if [ "$GRAPHVIZ_AVAILABLE" = true ]; then
    echo "Generating PNG diagram..."
    PNG_FILE="../docs/diagrams/network-topology-v2.png"
    dot -Tpng -Gdpi=120 "$DOT_FILE" -o "$PNG_FILE"
    echo "✅ PNG diagram created: $PNG_FILE"

    echo ""
    echo "Generating SVG diagram (scalable)..."
    SVG_FILE="../docs/diagrams/network-topology-v2.svg"
    dot -Tsvg "$DOT_FILE" -o "$SVG_FILE"
    echo "✅ SVG diagram created: $SVG_FILE"

    echo ""
    echo "Opening diagram..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        open "$PNG_FILE"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        xdg-open "$PNG_FILE" 2>/dev/null || echo "Please open manually: $PNG_FILE"
    fi
else
    echo ""
    echo "To generate visual diagram, install Graphviz then run:"
    echo "  dot -Tpng -Gdpi=120 docs/diagrams/network-topology-v2.dot -o docs/diagrams/network-topology-v2.png"
fi

echo ""
echo "=================================================="
echo "Core Infrastructure Diagram Generated!"
echo "=================================================="
echo ""
echo "This diagram shows:"
echo "  ✅ Subscriptions (2)"
echo "  ✅ VNETs with subnets (3 VNETs)"
echo "  ✅ Function Apps (Python & .NET)"
echo "  ✅ Event Grid Topic"
echo "  ✅ Event Hub Namespace"
echo "  ✅ Private Endpoints (with IPs)"
echo "  ✅ VNET Peering (including cross-subscription)"
echo "  ✅ Private DNS zones"
echo "  ✅ Traffic flows (private & public paths)"
echo "  ✅ NSG/FW info (where applicable)"
echo ""
echo "Files created:"
echo "  - docs/diagrams/network-topology-v2.dot (source)"
if [ "$GRAPHVIZ_AVAILABLE" = true ]; then
    echo "  - docs/diagrams/network-topology-v2.png (image)"
    echo "  - docs/diagrams/network-topology-v2.svg (scalable)"
fi
echo ""
