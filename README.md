# My DNS Blocklist

Automated threat-intelligence DNS blocklist — merged, deduplicated, and published every 48 hours via GitHub Actions.

![Last update](https://img.shields.io/github/last-commit/ChillBill77/dns-blacklist?label=last+update)

## Blocklist URL

Use this URL directly in Technitium, Pi-hole, AdGuard, or any DNS resolver that accepts a flat domain list:

```
https://raw.githubusercontent.com/ChillBill77/dns-blacklist/main/dist/blocklist.txt
```

---

## Sources

| Name | Category | URL |
|------|----------|-----|
| stevenblack_hosts | Ads / Malware / Fakenews | [link](https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts) |
| blp_abuse | Abuse / Spam | [link](https://blocklistproject.github.io/Lists/abuse.txt) |
| blp_phishing | Phishing | [link](https://blocklistproject.github.io/Lists/phishing.txt) |
| blp_malware | Malware C2 | [link](https://blocklistproject.github.io/Lists/malware.txt) |
| blp_ransomware | Ransomware C2 | [link](https://blocklistproject.github.io/Lists/ransomware.txt) |
| blp_scam | Scam / Fraud | [link](https://blocklistproject.github.io/Lists/scam.txt) |
| phishtank | Phishing | [link](https://raw.githubusercontent.com/tg12/pihole-phishtank-list/master/list/phish_domains.txt) |
| bbcan177_ms3 | Malware / Spyware | [link](https://gist.githubusercontent.com/BBcan177/4a8bf37c131be4803cb2/raw) |
| joewein_dombl | Spam / Scam | [link](https://www.joewein.net/dl/bl/dom-bl.txt) |

To add or remove sources, edit [`sources.txt`](sources.txt).

---

## How it works

```
sources.txt
    │
    ▼
merge.sh
    ├── Download each source (with retry + timeout)
    ├── Normalize: hosts format → plain domain, lowercase
    ├── Validate: regex filter on valid FQDN format
    ├── Deduplicate: sort -u across all sources
    └── Write dist/blocklist.txt + dist/stats.json
```

The script handles both input formats automatically:
- **hosts format** — `0.0.0.0 domain.tld` or `127.0.0.1 domain.tld`
- **plain domain list** — `domain.tld` (one per line)

---

## Technitium DNS setup

**Option A — URL (recommended, auto-updates):**

1. **Settings** → **Blocking** → **Block List URLs**
2. Add:
   ```
   https://raw.githubusercontent.com/YOUR_ORG/YOUR_REPO/main/dist/blocklist.txt
   ```
3. Set **Auto Update Interval** to `1` day
4. Click **Update Block Lists Now**

**Option B — Technitium REST API:**

```bash
TECHNITIUM="http://localhost:5380"
TOKEN="your_api_token"

curl -s -X POST "$TECHNITIUM/api/settings/set" \
  -d "token=$TOKEN" \
  --data-urlencode "blockListUrls=https://raw.githubusercontent.com/YOUR_ORG/YOUR_REPO/main/dist/blocklist.txt"

curl -s -X POST "$TECHNITIUM/api/blocklist/forceupdateBlockLists" \
  -d "token=$TOKEN"
```

---

## Running locally

```bash
# Clone
git clone https://github.com/YOUR_ORG/YOUR_REPO
cd YOUR_REPO

# Run (outputs to dist/blocklist.txt)
chmod +x merge.sh
./merge.sh

# Dry run (no output written)
./merge.sh --dry-run

# Custom sources file
./merge.sh --sources my_sources.txt
```

**Dependencies:** `bash`, `curl`, `awk`, `sort`, `grep` — all standard on Linux/macOS.  
No Python, no pip, no containers needed.

---

## GitHub Actions schedule

The workflow runs automatically every **48 hours** (03:00 UTC) and on every push to `sources.txt` or `merge.sh`.

Manual trigger: **Actions** → **Update Blocklist** → **Run workflow**

The bot only commits when the output actually changes — no noise commits.

---

## Stats

After each run, `dist/stats.json` contains a machine-readable build summary:

```json
{
  "generated_at": "2026-03-15T03:00:00Z",
  "git_sha": "a1b2c3d",
  "total_unique_domains": 758009,
  "sources": {
    "blp_abuse": 435153,
    "blp_malware": 435218,
    ...
  },
  "failed_sources": []
}
```

---

*Maintained by [YaWorks](https://yaworks.nl) — IT Infrastructure & Cybersecurity*
