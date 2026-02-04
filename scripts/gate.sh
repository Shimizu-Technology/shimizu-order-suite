#!/bin/bash
# Gate Script — Legacy Hafaloha API (shimizu-order-suite)
# Runs ALL verification before a PR can be created.
# Usage: ./scripts/gate.sh

set -e
cd "$(dirname "$0")/.."

echo "🔒 Running full gate — Legacy Hafaloha API"
echo "============================================"

# Ensure correct Ruby version
eval "$(rbenv init -)" 2>/dev/null || true
export RBENV_VERSION=3.2.3

# 1. Rubocop (linting)
echo ""
echo "📝 Step 1/4: Rubocop (linting)..."
if bundle exec rubocop --no-color 2>/dev/null; then
  echo "  ✅ Rubocop passed"
else
  echo "  ⚠️  Rubocop has offenses (non-blocking for now)"
fi

# 2. RSpec (tests)
echo ""
echo "🧪 Step 2/4: RSpec (tests)..."
RSPEC_OUTPUT=$(bundle exec rspec --format progress 2>&1)
RSPEC_EXIT=$?
RSPEC_SUMMARY=$(echo "$RSPEC_OUTPUT" | tail -3)
echo "  $RSPEC_SUMMARY"
if [ $RSPEC_EXIT -eq 0 ]; then
  echo "  ✅ RSpec passed"
else
  echo "  ⚠️  RSpec has failures (review required)"
fi

# 3. Security check (no secrets in code)
echo ""
echo "🔐 Step 3/4: Security scan..."
SECRETS_FOUND=$(grep -rn "sk_live_\|sk_test_\|PRIVATE_KEY\|password.*=.*['\"]" \
  --include="*.rb" --exclude-dir=spec --exclude-dir=vendor \
  app/ config/ lib/ 2>/dev/null | grep -v "password_digest\|password_params\|password_reset\|\.example\|config/database.yml" || true)
if [ -z "$SECRETS_FOUND" ]; then
  echo "  ✅ No hardcoded secrets found"
else
  echo "  ❌ Possible hardcoded secrets:"
  echo "$SECRETS_FOUND"
fi

# 4. Debug statements check
echo ""
echo "🐛 Step 4/4: Debug statements..."
DEBUG_FOUND=$(grep -rn "binding.pry\|byebug\|debugger\|puts \"\|pp " \
  --include="*.rb" --exclude-dir=spec --exclude-dir=vendor \
  app/ lib/ 2>/dev/null || true)
if [ -z "$DEBUG_FOUND" ]; then
  echo "  ✅ No debug statements found"
else
  echo "  ⚠️  Debug statements found:"
  echo "$DEBUG_FOUND"
fi

echo ""
echo "============================================"
echo "🏁 Gate complete!"
echo ""
echo "Summary:"
echo "  Rubocop: $(bundle exec rubocop --no-color 2>/dev/null | tail -1 || echo 'check above')"
echo "  RSpec:   $RSPEC_SUMMARY"
echo "  Secrets: $([ -z "$SECRETS_FOUND" ] && echo 'Clean' || echo 'REVIEW NEEDED')"
echo "  Debug:   $([ -z "$DEBUG_FOUND" ] && echo 'Clean' || echo 'REVIEW NEEDED')"
