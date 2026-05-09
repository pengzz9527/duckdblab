#!/bin/bash
# DuckDB Blog - Deploy Script
# 1. Build Hugo site
# 2. Git commit and push (triggers Vercel auto-deploy)

set -e

cd "$(dirname "$0")"

echo "🔨 Building Hugo site..."
hugo --gc --minify

echo "✅ Build complete: public/"

# Check if git remote is set
if git remote -v | grep -q origin; then
    echo "📤 Pushing to GitHub..."
    git add -A
    git commit -m "blog: auto-update $(date +%Y-%m-%d)"
    git push origin main
    echo "✅ Deployed!"
else
    echo "⚠️  No git remote configured."
    echo "   Run: git remote add origin <your-github-repo-url>"
    echo "   Then connect to Vercel: https://vercel.com/import"
    echo ""
    echo "📋 To deploy manually:"
    echo "   1. Create a GitHub repo: gh repo create duckdb-blog --public"
    echo "   2. Push: git remote add origin <url> && git push -u origin main"
    echo "   3. Go to vercel.com → Import repo → Deploy"
fi
