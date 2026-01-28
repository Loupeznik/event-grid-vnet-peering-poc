#!/bin/bash
set -e

echo "Building .NET function..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOTNET_DIR="$PROJECT_ROOT/EventGridPubSubFunction"

cd "$DOTNET_DIR"

echo "Restoring NuGet packages..."
dotnet restore

echo "Publishing .NET function..."
dotnet publish -c Release -o bin/Release/publish

cd bin/Release/publish

if [ -f "../../../deployment.zip" ]; then
    rm ../../../deployment.zip
fi

echo "Creating deployment package..."
zip -r ../../../deployment.zip . -q

echo "✅ .NET deployment package created"
