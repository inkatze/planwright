#!/bin/sh
# tool-discovery.sh — SessionStart hook. Surfaces project-shipped quality
# tooling as additionalContext (Task 6, REQ-K1.3, D-15).
#
# Discovery Rigor and Refactor Instinct (doctrine/discovery-rigor.md,
# doctrine/refactor-instinct.md) ground findings in what the project
# actually runs — linters, formatters, type checkers — rather than vibes.
# This hook does the scan once at session start so the agent sees a short
# list without grepping around; the builder (REQ-G1.2) consumes the same
# summary as its stack-detection seed.
#
# Output: a SessionStart hookSpecificOutput JSON payload with
# `additionalContext` when tooling is detected. Silent no-op (no output,
# exit 0) when: nothing is detected, the scanned dir is outside a git work
# tree, or jq is unavailable (jq guarantees valid JSON encoding; emitting a
# hand-built payload risks breaking SessionStart processing).
#
# Portable POSIX sh (bash 3.2 / BSD compatible, no fish/mise/tmux/Ansible
# dependency, REQ-K1.5).
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -d "$cwd" ] || exit 0
cd "$cwd" 2>/dev/null || exit 0

# Stay silent outside git work trees: tool-grounded discovery is meaningful
# only inside a project.
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

items=""
total=0
add() {
  items="$items
- $1"
  total=$((total + 1))
}

# Hook managers / multi-tool runners
if [ -f lefthook.yml ] || [ -f .lefthook.yml ] || [ -f lefthook.yaml ] || [ -f .lefthook.yaml ]; then
  add "lefthook (run pre-commit hooks: \`lefthook run pre-commit\`)"
fi
[ -f .pre-commit-config.yaml ] && add "pre-commit (\`pre-commit run --all-files\`)"
if [ -f Makefile ] || [ -f makefile ] || [ -f GNUmakefile ]; then
  add "Makefile (\`make\` targets; try \`make help\`)"
fi
if [ -f mise.toml ] || [ -f .mise.toml ]; then
  add "mise tasks (\`mise tasks\` to list)"
fi
[ -f .tool-versions ] && add ".tool-versions (runtime version pins; \`mise current\` to inspect)"

# Ruby
if [ -f .rubocop.yml ] || [ -f .rubocop.yaml ]; then
  add "rubocop (\`bundle exec rubocop\`)"
fi
[ -f sorbet/config ] && add "sorbet (\`bundle exec srb tc\`)"
[ -f .standard.yml ] && add "standardrb (\`bundle exec standardrb\`)"

# Python
if [ -f pyproject.toml ]; then
  py_tools=""
  grep -q '\[tool\.ruff' pyproject.toml 2>/dev/null && py_tools="${py_tools}ruff "
  grep -q '\[tool\.mypy' pyproject.toml 2>/dev/null && py_tools="${py_tools}mypy "
  grep -q '\[tool\.pyright' pyproject.toml 2>/dev/null && py_tools="${py_tools}pyright "
  grep -q '\[tool\.black' pyproject.toml 2>/dev/null && py_tools="${py_tools}black "
  grep -q '\[tool\.isort' pyproject.toml 2>/dev/null && py_tools="${py_tools}isort "
  if [ -n "$py_tools" ]; then
    add "Python (pyproject.toml: ${py_tools% })"
  else
    add "Python (pyproject.toml present; check for ruff/mypy/black/etc.)"
  fi
fi
if [ -f mypy.ini ] || [ -f .mypy.ini ]; then add "mypy (\`mypy .\`)"; fi
[ -f pyrightconfig.json ] && add "pyright (\`pyright\`)"
if [ -f .ruff.toml ] || [ -f ruff.toml ]; then add "ruff (\`ruff check .\`)"; fi

# TypeScript / JavaScript
[ -f tsconfig.json ] && add "tsc (\`tsc --noEmit\`)"
if [ -f .eslintrc.json ] || [ -f .eslintrc.js ] || [ -f .eslintrc.cjs ] \
  || [ -f .eslintrc.yml ] || [ -f .eslintrc.yaml ] || [ -f eslint.config.js ] \
  || [ -f eslint.config.mjs ] || [ -f eslint.config.cjs ]; then
  add "eslint (\`eslint .\`)"
fi
if [ -f biome.json ] || [ -f biome.jsonc ]; then add "biome (\`biome check .\`)"; fi
if [ -f .prettierrc ] || [ -f .prettierrc.json ] || [ -f .prettierrc.js ] \
  || [ -f .prettierrc.yml ] || [ -f .prettierrc.yaml ] || [ -f prettier.config.js ] \
  || [ -f prettier.config.cjs ]; then
  add "prettier (\`prettier --check .\`)"
fi
if [ -f knip.json ] || [ -f .knip.json ] || [ -f knip.config.ts ]; then
  add "knip (dead-code: \`knip\`)"
fi
[ -f package.json ] && add "package.json scripts (\`npm run\` or \`pnpm run\` to list lint/test/typecheck/format)"

# Go
if [ -f go.mod ]; then
  add "go (\`go vet ./...\`, \`gofmt -l .\`)"
  if [ -f .golangci.yml ] || [ -f .golangci.yaml ]; then
    add "golangci-lint (\`golangci-lint run\`)"
  fi
fi

# Rust
[ -f Cargo.toml ] && add "cargo (\`cargo clippy --all-targets\`, \`cargo fmt --check\`)"

# Elixir / Erlang
[ -f mix.exs ] && add "Elixir mix (\`mix format --check-formatted\`; check mix.exs for credo/dialyxir)"
[ -f rebar.config ] && add "rebar3 (\`rebar3 dialyzer\`)"

# Java / Kotlin
if [ -f build.gradle ] || [ -f build.gradle.kts ] || [ -f pom.xml ]; then
  add "JVM build (\`./gradlew check\` or \`mvn verify\`)"
fi

# Shell
[ -f .shellcheckrc ] && add "shellcheck (\`git ls-files -z '*.sh' | xargs -0 shellcheck\`)"

# YAML / Ansible
if [ -f .yamllint ] || [ -f .yamllint.yml ] || [ -f .yamllint.yaml ]; then
  add "yamllint (\`yamllint .\`)"
fi
if [ -f .ansible-lint ] || [ -f .ansible-lint.yml ] || [ -f .ansible-lint.yaml ] \
  || [ -f ansible-lint.yml ] || [ -f ansible-lint.yaml ]; then
  add "ansible-lint (\`ansible-lint\`)"
fi

# Security / supply chain
[ -f .gitleaks.toml ] && add "gitleaks (\`gitleaks detect\`)"
[ -f .trivyignore ] && add "trivy (\`trivy fs .\`)"

# CI workflows (presence often implies more checks the agent should respect)
ci_count=0
for f in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$f" ] && ci_count=$((ci_count + 1))
done
[ "$ci_count" -gt 0 ] && add ".github/workflows ($ci_count file(s); inspect for additional checks)"
[ -f .gitlab-ci.yml ] && add ".gitlab-ci.yml"
[ -f .circleci/config.yml ] && add ".circleci/config.yml"

[ "$total" -eq 0 ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

summary="## Project tooling (auto-detected)

Use these for tool-grounded discovery and refactor decisions (per planwright's Discovery Rigor and Refactor Instinct doctrine). Tool output is grounded; vibes are not.
$items"

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
  "$(printf '%s' "$summary" | jq -Rs .)"

exit 0
