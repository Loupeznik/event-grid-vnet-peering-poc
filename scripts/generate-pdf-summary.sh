#!/bin/bash
set -e

echo "=================================================="
echo "Generate PDF Summary from Markdown"
echo "=================================================="
echo ""

MD_FILE="docs/POC-SUMMARY.md"
MD_FILE_PDF="docs/POC-SUMMARY-PDF.md"
PDF_FILE="docs/POC-SUMMARY.pdf"

# Check if pandoc is available
if command -v pandoc &> /dev/null; then
    echo "✅ Using pandoc for PDF generation..."

    cd "$(dirname "$0")/.."

    echo "Checking diagram files..."
    if [ -f "docs/diagrams/network-topology.png" ]; then
        echo "  ✅ network-topology.png found"
    else
        echo "  ⚠️  network-topology.png missing"
    fi

    if [ -f "docs/diagrams/network-topology-v2.png" ]; then
        echo "  ✅ network-topology-v2.png found"
    else
        echo "  ⚠️  network-topology-v2.png missing"
    fi
    echo ""

    echo "Creating PDF-friendly version (replacing emojis)..."
    cat "$MD_FILE" | \
        sed 's/✅/**[✓]**/g' | \
        sed 's/❌/**[✗]**/g' | \
        sed 's/⚠️/**(!)** /g' | \
        sed 's/🟢/**(private)**/g' | \
        sed 's/🟠/**(hybrid)**/g' | \
        sed 's/🔴/**(public)**/g' > "$MD_FILE_PDF"
    echo "  ✅ PDF-friendly markdown created"

    echo "Generating PDF with enhanced formatting..."

    # Generate PDF with pandoc using xelatex (stable, widely supported)
    pandoc "$MD_FILE_PDF" \
        -o "$PDF_FILE" \
        --pdf-engine=xelatex \
        --resource-path=docs \
        -V geometry:margin=0.75in \
        -V geometry:top=0.75in \
        -V geometry:bottom=0.75in \
        -V fontsize=10pt \
        -V documentclass=article \
        -V colorlinks=true \
        -V linkcolor=blue \
        -V urlcolor=blue \
        -V toccolor=black \
        -V linestretch=1.2 \
        --toc \
        --toc-depth=2 \
        --number-sections \
        -V papersize=a4 \
        -V block-headings \
        2>&1 | grep -v "WARNING" || true

    echo "✅ PDF generated: $PDF_FILE"

    # Get file size
    FILE_SIZE=$(du -h "$PDF_FILE" | cut -f1)
    echo "   File size: $FILE_SIZE"

    # Count pages (if pdfinfo is available)
    if command -v pdfinfo &> /dev/null; then
        PAGE_COUNT=$(pdfinfo "$PDF_FILE" 2>/dev/null | grep "Pages:" | awk '{print $2}')
        echo "   Pages: $PAGE_COUNT"
    fi

    # Cleanup temporary PDF-friendly markdown
    rm -f "$MD_FILE_PDF"

    # Open PDF
    if [[ "$OSTYPE" == "darwin"* ]]; then
        open "$PDF_FILE"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        xdg-open "$PDF_FILE" 2>/dev/null || echo "Please open manually: $PDF_FILE"
    fi

elif command -v markdown-pdf &> /dev/null; then
    echo "✅ Using markdown-pdf for generation..."

    cd "$(dirname "$0")/.."
    markdown-pdf "$MD_FILE" -o "$PDF_FILE"

    echo "✅ PDF generated: $PDF_FILE"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        open "$PDF_FILE"
    fi

elif command -v grip &> /dev/null; then
    echo "ℹ️  Using grip to preview (will open in browser)..."
    echo "   You can print to PDF from the browser"

    cd "$(dirname "$0")/.."
    grip "$MD_FILE" --export "$PDF_FILE.html"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        open "$PDF_FILE.html"
    fi

    echo ""
    echo "📄 HTML generated: $PDF_FILE.html"
    echo "   Use browser's 'Print to PDF' to create PDF"

else
    echo "⚠️  No PDF conversion tool found"
    echo ""
    echo "Please install one of the following:"
    echo ""
    echo "Option 1: pandoc (recommended)"
    echo "  macOS:   brew install pandoc"
    echo "  macOS:   brew install basictex  # for PDF engine"
    echo "  Linux:   apt-get install pandoc texlive-xetex"
    echo ""
    echo "Option 2: markdown-pdf (Node.js)"
    echo "  npm install -g markdown-pdf"
    echo ""
    echo "Option 3: Use VSCode or online converters"
    echo "  - VSCode: Install 'Markdown PDF' extension"
    echo "  - Online: https://www.markdowntopdf.com/"
    echo "  - Online: https://md2pdf.netlify.app/"
    echo ""
    echo "Option 4: Use grip (GitHub-flavored preview)"
    echo "  pip install grip"
    echo ""
    exit 1
fi

echo ""
echo "=================================================="
echo "PDF Generation Complete!"
echo "=================================================="
