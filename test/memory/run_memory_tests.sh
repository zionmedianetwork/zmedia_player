#!/bin/bash

# Memory Leak Test Runner Script
# This script runs all memory leak tests with various options

set -e

echo "================================================"
echo "  ZMedia Player - Memory Leak Test Suite"
echo "================================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if flutter is available
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Flutter is not installed or not in PATH${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Flutter found: $(flutter --version | head -n 1)"
echo ""

# Get dependencies
echo "📦 Getting dependencies..."
flutter pub get
echo ""

# Run all memory tests
echo "🧪 Running Memory Leak Tests..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
flutter test test/memory/memory_leak_test.dart --reporter expanded

TEST_EXIT_CODE=$?

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ All memory leak tests PASSED!${NC}"
    echo ""
    
    # Optional: Run with coverage
    read -p "Generate coverage report? (y/N) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "📊 Generating coverage report..."
        flutter test test/memory/ --coverage
        
        if command -v lcov &> /dev/null; then
            lcov --list coverage/lcov.info
            echo ""
            echo -e "${GREEN}✓${NC} Coverage report generated at coverage/lcov.info"
        else
            echo -e "${YELLOW}⚠${NC}  lcov not installed. Install with: brew install lcov"
        fi
    fi
    
    # Optional: Run benchmarks only
    echo ""
    read -p "Run performance benchmarks only? (y/N) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "⏱️  Running performance benchmarks..."
        flutter test test/memory/memory_leak_test.dart --name "Performance Benchmarks" --reporter expanded
    fi
    
else
    echo -e "${RED}❌ Some tests FAILED${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check that Fix #1 is properly implemented"
    echo "2. Verify platform channel is mocked in test setup"
    echo "3. Review test output above for specific failures"
    echo "4. Consult test/memory/README.md for more info"
    exit 1
fi

echo ""
echo "================================================"
echo "  Test run complete!"
echo "================================================"

exit 0

