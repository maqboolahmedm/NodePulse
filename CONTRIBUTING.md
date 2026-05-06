# Contributing to NodePulse

NodePulse is built by the DeNet community, for the DeNet community. Whether you run nodes yourself, found a bug, or want to improve documentation — you're welcome here.

---

## Ways to Contribute

### 🐛 Report a Bug
Open a GitHub Issue and include:
- Your platform (Linux / Windows / macOS)
- Single Wallet or Multi Wallet setup
- What you expected vs what actually happened
- Relevant log output (redact your bot token and wallet password)

### 💡 Suggest a Feature
Open a GitHub Issue with the `enhancement` label. Describe:
- The problem you're trying to solve
- How your idea would work
- Which platform it applies to

### 🔧 Submit a Fix or Feature
1. Fork the repository
2. Create a branch: `git checkout -b fix/your-fix-name`
3. Make your changes
4. Test on your own node setup if possible
5. Open a Pull Request with a clear description of what changed and why

### 📝 Improve Documentation
Documentation PRs are especially welcome. If something was unclear when you set up NodePulse, fixing it helps every future user. Edit the relevant `README.md` and open a PR.

### 🪟 Improve Windows / macOS Support
The Linux version is the most feature-complete. The Windows and macOS versions are maintained by the community and have room for improvement:
- Bot command support
- Guard health scoring
- Auto-setup scripts
- Dashboard integration

---

## Ground Rules

- Be respectful. This is a community project.
- Keep changes focused — one fix or feature per PR.
- Don't commit credentials, passwords, wallet addresses, or bot tokens.
- Scripts should work on a clean install — avoid assuming non-standard tools.
- New scripts must follow the `nodepulse-` prefix naming convention.

---

## Code Style

**Bash scripts:**
- Variables in `UPPER_CASE`
- Functions in `snake_case`
- `set -euo pipefail` at the top where appropriate
- Comments on non-obvious logic
- All user-facing output through Telegram or echo — no silent failures

**Python:**
- PEP 8 style
- No external dependencies beyond the Python standard library unless truly necessary
- Minimal and readable — these scripts run 24/7 on production node machines

---

## File Naming

| Type | Convention | Example |
|---|---|---|
| Community scripts | `nodepulse-` prefix | `nodepulse-guard.sh` |
| systemd services | `nodepulse-` prefix | `nodepulse-proxy.service` |
| Documentation | Standard names | `README.md`, `CONTRIBUTING.md` |

---

## Repo Structure

```
NodePulse/
├── Linux-Single-Wallet/    ← scripts for single wallet on Linux
├── Linux-Multi-Wallet/     ← scripts for multi-wallet on Linux
├── Windows/                ← PowerShell scripts
├── macOS/                  ← bash scripts with launchd setup
├── docs/                   ← community guides and submission docs
├── nodepulse.html          ← PWA dashboard
├── nodepulse-wizard.html   ← setup wizard
└── README.md
```

Scripts in `Linux-Single-Wallet/` and `Linux-Multi-Wallet/` are the primary supported versions. Changes that affect logic should be applied to both.

---

## Testing Your Changes

Before submitting a PR, test manually on your node machine:

```bash
# Run the monitor directly
bash ~/NodePulse/nodepulse-monitor.sh

# Run the guard
bash ~/NodePulse/nodepulse-guard.sh

# Test bot listener response
echo "/status" > ~/.denode/.bot_trigger && sleep 5

# Check proxy
curl "http://localhost:8765/cmd?text=/status"
```

If you can't test on a live node, note that in your PR so others can validate.

---

## Questions?

Open a GitHub Issue or reach out in the DeNet community Discord/Telegram.

*Thank you for contributing to NodePulse.*
