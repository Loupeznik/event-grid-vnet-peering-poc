#!/bin/bash
set -e

echo "=================================================="
echo "Azure Network Topology Diagram Generator"
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
PYTHON_FUNC_NAME=$(terraform output -raw function_app_name)
DOTNET_FUNC_NAME=$(terraform output -raw dotnet_function_app_name)
EVENTGRID_TOPIC=$(terraform output -raw eventgrid_topic_name)
EVENTHUB_NS=$(terraform output -raw eventhub_namespace_name)
EVENTHUB_NAME=$(terraform output -raw eventhub_name)
EVENTGRID_IP=$(terraform output -raw eventgrid_private_endpoint_ip)
PYTHON_VNET=$(terraform output -raw function_vnet_name)
EVENTGRID_VNET=$(terraform output -raw eventgrid_vnet_name)
DOTNET_VNET=$(terraform output -raw dotnet_vnet_name)

# Create output directory
mkdir -p ../docs/diagrams

# Generate DOT file
DOT_FILE="../docs/diagrams/network-topology.dot"
echo "Generating network topology diagram..."

cat > "$DOT_FILE" << 'DOT_START'
digraph azure_network_topology {
    # Graph settings
    rankdir=TB;
    ranksep=1.2;
    nodesep=1.0;
    splines=ortho;
    fontname="Arial";
    fontsize=12;
    compound=true;

    # Node styles
    node [shape=box, style="rounded,filled", fontname="Arial", fontsize=11];
    edge [fontname="Arial", fontsize=10];

    # Color scheme
    # Subscription 1: Light blue (#E3F2FD)
    # Subscription 2: Light green (#E8F5E9)
    # Private: Green (#4CAF50)
    # Public: Red (#F44336)

    # Title
    labelloc="t";
    label="Azure Event Grid VNET Peering PoC\nFully Private Event Hub Path (Main) + Webhook Path (Comparison)";
    fontsize=16;
    fontname="Arial Bold";

    # MAIN PATH: Fully Private Event Hub Communication
    subgraph cluster_main_path {
        label="✅ MAIN: Fully Private Event Hub Path\n(All traffic via VNET peering - NO public internet)";
        style="filled,bold";
        color="#C8E6C9";
        fontsize=13;
        fontname="Arial Bold";

        # .NET Function (Subscription 2)
        dotnet_publish [label=".NET Function\nPublishEvent\n(Subscription 2)\n10.2.0.0/16", fillcolor="#4CAF50", fontcolor="white", penwidth=2];

        # Event Grid via Private Endpoint
        eg_pe_main [label="Event Grid Topic\n(via Private Endpoint)\n10.1.1.4\nPublic Access: DISABLED", fillcolor="#2196F3", fontcolor="white", penwidth=2];

        # Event Hub via Private Endpoint
        eh_pe_main [label="Event Hub\n(via Private Endpoint)\n10.1.1.5\nPublic Access: DISABLED", fillcolor="#2196F3", fontcolor="white", penwidth=2];

        # .NET Consumer
        dotnet_consume [label=".NET Function\nConsumeEventFromEventHub\n(Subscription 2)\n10.2.0.0/16", fillcolor="#4CAF50", fontcolor="white", penwidth=2];

        # Flow arrows
        dotnet_publish -> eg_pe_main [label="  1. Publish via\n  VNET Peering  ", color="#4CAF50", penwidth=4, fontcolor="#2E7D32", fontsize=11];
        eg_pe_main -> eh_pe_main [label="  2. Deliver\n  (Managed Identity)  ", color="#4CAF50", penwidth=4, fontcolor="#2E7D32", fontsize=11];
        eh_pe_main -> dotnet_consume [label="  3. Poll/Consume\n  via VNET Peering  ", color="#4CAF50", penwidth=4, fontcolor="#2E7D32", fontsize=11];
    }

    # COMPARISON PATH: Public Webhook (Original PoC)
    subgraph cluster_webhook_path {
        label="⚠️  COMPARISON: Webhook Path\n(Uses public internet for delivery)";
        style="filled,dashed";
        color="#FFE0B2";
        fontsize=13;
        fontname="Arial Bold";

        # Python Function
        python_publish [label="Python Function\nPublishEvent\n(Subscription 1)\n10.0.0.0/16", fillcolor="#FF9800", fontcolor="white"];

        # Event Grid via Private Endpoint
        eg_pe_webhook [label="Event Grid Topic\n(via Private Endpoint)\n10.1.1.4", fillcolor="#FF9800", fontcolor="white"];

        # Python Consumer (webhook)
        python_consume [label="Python Function\nconsum_event\n(Subscription 1)\nReceives via Webhook", fillcolor="#FF9800", fontcolor="white"];

        # Flow arrows
        python_publish -> eg_pe_webhook [label="  Publish via\n  VNET Peering  ", color="#FF9800", penwidth=2, fontcolor="#E65100", fontsize=10];
        eg_pe_webhook -> python_consume [label="  Webhook Delivery\n  (PUBLIC INTERNET)  ", color="#F44336", penwidth=2, fontcolor="#C62828", fontsize=10, style=dashed];
    }

    # Infrastructure Details
    subgraph cluster_infrastructure {
        label="Network Infrastructure";
        style=filled;
        color="#E3F2FD";
        fontsize=13;
        fontname="Arial Bold";

        # VNETs
        vnet1 [label="VNET 1\nPython Function\n10.0.0.0/16\n(Subscription 1)", shape=folder, fillcolor="#90CAF9", fontcolor="black"];
        vnet2 [label="VNET 2\nEvent Grid + Event Hub\n10.1.0.0/16\n(Subscription 1)", shape=folder, fillcolor="#90CAF9", fontcolor="black"];
        vnet3 [label="VNET 3\n.NET Function\n10.2.0.0/16\n(Subscription 2)", shape=folder, fillcolor="#81C784", fontcolor="black"];

        # Peering
        vnet1 -> vnet2 [label="VNET Peering", dir=both, color="#2196F3", penwidth=2];
        vnet2 -> vnet3 [label="VNET Peering\n(Cross-Subscription)", dir=both, color="#4CAF50", penwidth=2];

        # Private DNS
        dns [label="Private DNS Zones\nprivatelink.eventgrid.azure.net\nprivatelink.servicebus.windows.net\n\nLinked to all VNETs", shape=cylinder, fillcolor="#9C27B0", fontcolor="white"];
    }

    # Legend
    subgraph cluster_legend {
        label="Legend";
        style=filled;
        color="#FFFFFF";
        fontsize=12;

        legend_private [label="Fully Private Path\n(VNET peering only)", fillcolor="#4CAF50", fontcolor="white", penwidth=2];
        legend_public [label="Hybrid Path\n(Private publish,\nPublic webhook delivery)", fillcolor="#FF9800", fontcolor="white"];
        legend_pe [label="Private Endpoint\n10.1.1.x", fillcolor="#2196F3", fontcolor="white"];

        legend_private -> legend_public [style=invis];
        legend_public -> legend_pe [style=invis];
    }

    # Key highlight
    note [label="KEY: Event Hub path achieves\n100% private communication\n(No public internet)", shape=note, fillcolor="#FFEB3B", fontcolor="black", penwidth=2];
}
DOT_START

echo "✅ Network topology DOT file created: $DOT_FILE"
echo ""

# Generate PNG if graphviz is available
if [ "$GRAPHVIZ_AVAILABLE" = true ]; then
    echo "Generating PNG diagram..."
    PNG_FILE="../docs/diagrams/network-topology.png"
    dot -Tpng "$DOT_FILE" -o "$PNG_FILE"
    echo "✅ PNG diagram created: $PNG_FILE"

    echo ""
    echo "Generating SVG diagram (scalable)..."
    SVG_FILE="../docs/diagrams/network-topology.svg"
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
    echo "  dot -Tpng docs/diagrams/network-topology.dot -o docs/diagrams/network-topology.png"
fi

echo ""
echo "=================================================="
echo "Diagram Generation Complete!"
echo "=================================================="
echo ""
echo "Files created:"
echo "  - docs/diagrams/network-topology.dot (text format)"
if [ "$GRAPHVIZ_AVAILABLE" = true ]; then
    echo "  - docs/diagrams/network-topology.png (image)"
    echo "  - docs/diagrams/network-topology.svg (scalable vector)"
fi
echo ""
