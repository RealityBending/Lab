#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# audit.sh -- READ-ONLY storage audit of an Artemis account.
#
#   bash hpc/scripts/audit.sh [--alias artemis] [--days 30] [--save]
#
# Opens ONE ssh connection (sshd rate-limits bursts), walks the account's
# Lustre users + scratch dirs and ~/.cmdstan, and prints a report. It deletes
# nothing. What to do with the findings is in hpc/housekeeping.md.
#
#   --alias  ssh host alias (default: artemis, from scripts/setup-ssh.sh)
#   --days   age threshold for "old" scratch files and logs (default: 30)
#   --save   also write the report to hpc/private/audits/<date>_<alias>.txt
#
# Needs the GlobalProtect VPN. On a large account the walk takes a minute or two.
# ---------------------------------------------------------------------------
set -euo pipefail

ALIAS=artemis
DAYS=30
SAVE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --alias) ALIAS="$2"; shift 2 ;;
    --days)  DAYS="$2"; shift 2 ;;
    --save)  SAVE=1; shift ;;
    -h|--help) sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done
case "$DAYS" in ''|*[!0-9]*) echo "--days must be a whole number" >&2; exit 1 ;; esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prefer Windows OpenSSH when present, like the project drivers.
if [ -x /c/Windows/System32/OpenSSH/ssh.exe ]; then SSH=/c/Windows/System32/OpenSSH/ssh.exe; else SSH=ssh; fi

run_remote() {
# A login ~/.bashrc with stale `module load` lines is sourced by sshd and
# prints noise on stderr; drop just that, keep real errors (e.g. VPN down).
"$SSH" "$ALIAS" bash -s -- "$DAYS" 2> >(grep -v 'module: command not found' >&2) <<'REMOTE'
DAYS="$1"
NOW="$(date +%s)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# awk helper: bytes -> human
# (explicit " " separator: the callers set FS to tab, which split() would use)
H='function h(b,   u, i, f){ split("B KB MB GB TB", u, " "); i = 1; while (b >= 1024 && i < 5) { b /= 1024; i++ }; f = (i == 1) ? "%d %s" : "%.1f %s"; return sprintf(f, b, u[i]) }'

USERS_DIR="$(ls -d /mnt/lustre/users/*/"$USER" 2>/dev/null | head -1)"
SCRATCH_DIR="$(ls -d /mnt/lustre/scratch/*/"$USER" 2>/dev/null | head -1)"

echo "# Artemis storage audit"
echo
echo "- account: $USER ($(id -Gn | tr ' ' ','))"
echo "- run on:  $(hostname), $(date '+%Y-%m-%d %H:%M %Z')"
echo "- users:   ${USERS_DIR:-NOT FOUND}"
echo "- scratch: ${SCRATCH_DIR:-NOT FOUND}"
echo "- home:    $HOME"
echo "- 'old' means not modified for more than $DAYS days"

echo
echo "## 1. Quota (Lustre users: 2 TB and ~4 M files per user; not backed up)"
echo
echo '```'
lfs quota -h -u "$USER" /mnt/lustre 2>/dev/null || echo "(lfs quota unavailable)"
echo "home ($(readlink -f "$HOME")): $(du -sh "$HOME/" 2>/dev/null | cut -f1)"
echo '```'

# One walk per tree: size <TAB> mtime <TAB> path
walk() { [ -n "$1" ] && [ -d "$1" ] && find "$1" -xdev -type f -printf '%s\t%T@\t%p\n' 2>/dev/null; }
walk "$USERS_DIR"   > "$TMP/users.tsv"   || true
walk "$SCRATCH_DIR" > "$TMP/scratch.tsv" || true

per_top() {  # $1 = tsv, $2 = root
  awk -F'\t' -v root="$2/" -v now="$NOW" "$H"'
    { rel = substr($3, length(root)+1); n = index(rel, "/");
      top = (n ? substr(rel, 1, n-1) "/" : rel);
      s[top] += $1; c[top]++; if ($2 > m[top]) m[top] = $2; S += $1; C++ }
    END {
      for (t in s) printf "%d\t| %-40s | %10s | %9d | %-10s | %d |\n", s[t], t, h(s[t]), c[t], strftime("%Y-%m-%d", m[t]), (now - m[t]) / 86400;
      printf "-1\t| %-40s | %10s | %9d | | |\n", "**total**", h(S), C }' "$1" > "$TMP/top.tsv"
  printf "| %-40s | %10s | %9s | %-10s | %s |\n" "entry" "size" "files" "last change" "idle (days)"
  printf "| --- | ---: | ---: | --- | ---: |\n"
  sort -t"$(printf '\t')" -k1,1 -n -r "$TMP/top.tsv" | awk -F'\t' '$1 >= 0 { print $2 }'
  awk -F'\t' '$1 == -1 { print $2 }' "$TMP/top.tsv"
}

echo
echo "## 2. Lustre users, by top-level entry"
echo
[ -s "$TMP/users.tsv" ] && per_top "$TMP/users.tsv" "$USERS_DIR" || echo "(empty)"

echo
echo "## 3. Scratch, by top-level entry (purgeable: docs say 21-90 days)"
echo
[ -s "$TMP/scratch.tsv" ] && per_top "$TMP/scratch.tsv" "$SCRATCH_DIR" || echo "(empty)"

echo
echo "### 3a. Scratch files older than $DAYS days"
echo
awk -F'\t' -v cut="$((NOW - DAYS * 86400))" "$H"'
  $2 < cut { s += $1; c++; if ($3 ~ /\.(out|err)$/) { ls += $1; lc++ } else if ($3 ~ /\.rds$/) { rs += $1; rc++ } }
  END { printf "- all: %d files, %s\n- of which logs (.out/.err): %d, %s\n- of which .rds (results in scratch!): %d, %s\n", c, h(s), lc, h(ls), rc, h(rs) }' "$TMP/scratch.tsv"

echo
echo "### 3b. .rds files anywhere in scratch (results should not live here)"
echo
awk -F'\t' "$H"'$3 ~ /\.rds$/ { n = $3; sub(/\/[^\/]*$/, "", n); s[n] += $1; c[n]++ }
  END { for (d in s) printf "- %s: %d files, %s\n", d, c[d], h(s[d]) }' "$TMP/scratch.tsv" | sort | head -40
awk -F'\t' '$3 ~ /\.rds$/' "$TMP/scratch.tsv" | grep -q . || echo "(none)"

echo
echo "## 4. Home: CmdStan and precompiled headers"
echo
echo '```'
du -sh "$HOME"/.cmdstan/* 2>/dev/null || echo "(no ~/.cmdstan)"
for g in "$HOME"/.cmdstan/*/stan/src/stan/model/model_header.hpp.gch; do
  [ -d "$g" ] || continue
  echo "gch variants in ${g#$HOME/}:"
  du -sh "$g"/* 2>/dev/null | sed 's/^/  /'
done
echo '```'

echo
echo "## 5. R libraries"
echo
echo '```'
for d in "$USERS_DIR"/cluster_R_libs/*/*; do [ -d "$d" ] && echo "$(du -sh "$d" | cut -f1)  $d  ($(ls "$d" | wc -l) packages)"; done
echo '```'

echo
echo "## 6. Largest files (> 1 GB) in Lustre users"
echo
awk -F'\t' "$H"'$1 > 1073741824 { printf "%s\t%s\t%s\n", $1, h($1), $3 }' "$TMP/users.tsv" \
  | sort -n -r | head -20 | awk -F'\t' '{ printf "- %s  %s\n", $2, $3 }'
awk -F'\t' '$1 > 1073741824' "$TMP/users.tsv" | grep -q . || echo "(none)"

echo
echo "## 7. Throwaway-named or parked directories (smoke/test/probe/tmp/old/superseded)"
echo
for root in "$USERS_DIR" "$SCRATCH_DIR"; do
  [ -d "$root" ] || continue
  find "$root" -xdev -maxdepth 4 -type d \( -iname 'smoke*' -o -iname 'test*' -o -iname 'probe*' \
       -o -iname 'tmp*' -o -iname 'old' -o -iname 'old_*' -o -iname 'superseded*' \) -prune -print 2>/dev/null
done | while read -r d; do echo "- $(du -sh "$d" 2>/dev/null | cut -f1)  $d  (last change $(date -d @"$(find "$d" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 | cut -d. -f1)" +%F 2>/dev/null || echo '?'))"; done
echo "(end of list)"

echo
echo "## 8. Zero-byte .rds files (failed writes)"
echo
awk -F'\t' '$1 == 0 && $3 ~ /\.rds$/ { print "- " $3 }' "$TMP/users.tsv" "$TMP/scratch.tsv"
awk -F'\t' '$1 == 0 && $3 ~ /\.rds$/' "$TMP/users.tsv" "$TMP/scratch.tsv" | grep -q . || echo "(none)"

echo
echo "## 9. Shards kept next to a combined fit"
echo
echo "For each combined/<name>.rds, the sibling <name>_*.rds shards one level up."
echo
found=0
while IFS= read -r c; do
  base="$(basename "$c" .rds)"; parent="$(dirname "$(dirname "$c")")"
  line="$(awk -F'\t' -v p="$parent/" -v b="$base" "$H"'
    index($3, p) == 1 { rel = substr($3, length(p)+1);
      if (rel !~ /\// && index(rel, b "_") == 1 && rel ~ /\.rds$/) { s += $1; c++ } }
    END { if (c) printf "%d shards, %s", c, h(s) }' "$TMP/users.tsv")"
  if [ -n "$line" ]; then echo "- ${parent#$USERS_DIR/}/ $base: $line"; found=1; fi
done < <(awk -F'\t' '$3 ~ /\/combined\/[^\/]+\.rds$/ { print $3 }' "$TMP/users.tsv" | sort)
[ "$found" = 1 ] || echo "(none)"

echo
echo "---"
echo "Read-only: nothing was changed. Classify with hpc/housekeeping.md, get approval, then act."
REMOTE
}

if [ "$SAVE" = 1 ]; then
  mkdir -p "${HERE}/../private/audits"
  out="${HERE}/../private/audits/$(date +%Y-%m-%d)_${ALIAS}.txt"
  run_remote | tee "$out"
  echo
  echo "saved: $out"
else
  run_remote
fi
