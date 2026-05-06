# NodePulse Changelog

All notable changes to NodePulse are documented here.

---

## [NodePulse Final] — 2025

### Added
- **NodePulse Guard** — per-node health scoring engine (0–100), replaces basic alert-only monitoring
- **NodePulse IP Watch** — DuckDNS dynamic IP updater with Telegram notifications on IP change
- **nodepulse-cleanup.sh** — lightweight RAM/cache cleaner, no alerts, no Telegram dependency
- **Setup Wizard** (`nodepulse-wizard.html`) — browser-based install command generator with Single/Multi Wallet toggle
- **PWA Dashboard** (`nodepulse.html`) — mobile-friendly Progressive Web App, add to home screen
- **Command proxy architecture** — Telegram commands routed via local proxy (`nodepulse-proxy.py`) → trigger file (`~/.denode/.bot_trigger`) → bot listener; eliminates Telegram API polling loop for command execution
- **RC14 support** in `nodepulse-denet-update.sh` — handles per-node config files at `~/.denode/<wallet>/config-<license>.json`
- **Linux Multi-Wallet** variant — supports up to 4 wallets with independent passwords
- **Guard cooldown system** — 30-minute per-node alert cooldown to prevent Telegram spam
- **Guard hourly report** — aggregated health summary sent to Telegram every hour
- **Pool Occupancy** metric support — parsed from RC14+ node logs

### Changed
- Community intelligence agent renamed from NEXUS to **NodePulse Guard**
- Community IP monitor renamed from NEXUS IP Watch to **NodePulse IP Watch**
- All community scripts standardised to `nodepulse-` prefix naming convention
- Bot listener now polls trigger file instead of Telegram API — more reliable command execution
- Proxy now writes commands to trigger file — decouples dashboard from Telegram API dependency

### Removed
- NEXUS.sh and `~/.nexus/` — fully replaced by `nodepulse-guard.sh`
- Direct Telegram API polling in bot listener for command routing

---

## Scoring Reference

| Condition | Score Change |
|---|---|
| HEALTHY | +2 |
| PENDING | −3 |
| STALE | −10 |
| PROOF_FAIL ×2 | −8 |
| RPC_ERROR ×2 | −8 |
| RPC_TIMEOUT ×3 | −8 |
| TX_NOT_MINED ×3 | −8 |
| LOW_GAS ×3 | −3 |
| NO_FUNDS | −20 |

---

## DeNet RC Compatibility

| NodePulse Version | RC Supported |
|---|---|
| NodePulse Final | RC13, RC14-dev1+ |

---

*For the full file list and architecture, see the root README.md.*
