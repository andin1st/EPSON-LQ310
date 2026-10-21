#!/usr/bin/env bash
# Epson LQ-310 one-shot CUPS installer - works on any Linux distro.
#
# Put this script next to LQ-310.ppd and foomatic-rip-lq310 (same folder),
# plug the printer in, then run:
#
#   ./install.sh           install (asks for sudo/root once)
#   ./install.sh --test    install, then print a test banner
#   ./install.sh --client ipp://HOST:631/printers/QUEUE
#                          add a NETWORK LQ-310 shared by another PC
#                          (driverless; the server renders the job)
#
# What it does:
#   1. Detects the package manager and installs missing tools
#      (cups, foomatic-rip, foomatic database, perl) - any distro
#   2. Starts the CUPS service (systemd or SysV init)
#   3. Auto-detects the LQ-310 over USB (CUPS discovery, sysfs fallback)
#   4. Installs the foomatic-rip wrapper (injects ESC C = 5.5 inch page length
#      and keeps one trailing FF so the printer advances to the next form and
#      stops at the perforation, leaving the next job aligned)
#   5. Creates/updates the CUPS queue "LQ-310" from the bundled PPD
#      (page 5.5x8.5 = 8.5 inch across x 5.5 inch feed, 6 mm margins)
#   6. Sets it as default printer
#
# Re-running is safe: everything is updated in place.

set -euo pipefail

PRINTER="LQ-310"
# Auto-detect URL or local dir for one-liner compatibility
RAW_BASE_URL="https://raw.githubusercontent.com/<username>/<repo>/main"
SCRIPT_SRC=""
if [[ -n "" && -f "" ]]; then
  DIR=""
else
  DIR="/workspace"
fi
PPD_SRC="$DIR/LQ-310.ppd"
WRAPPER_SRC="$DIR/foomatic-rip-lq310"
WRAPPER_DST="/usr/lib/cups/filter/foomatic-rip-lq310"
TMP_FETCH_DIR=""
cleanup() {
  if [[ -n "" && -d "" ]]; then
    rm -rf ""
  fi
}
trap cleanup EXIT
DO_TEST=0
MODE=server
CLIENT_URI=""
SET_DEFAULT=0
NAME_SET=0
ORIG_ARGS=("$@")

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  ./install.sh                        Install a USB-attached LQ-310 on THIS PC.
  ./install.sh --test                 Same, then print a test page.

  ./install.sh --client <ipp-uri>     Add a NETWORK LQ-310 shared by another PC
                                      (driverless IPP; the server renders).
        [--name <queue>]              Local queue name (default: LQ-310-<host>).
        [--default]                   Make the new queue the default printer.
        [--test]                      Print a test page afterwards.

Examples:
  ./install.sh
  ./install.sh --client ipp://BCPLBO-IT.local:631/printers/Epson-LQ310-Custom
  ./install.sh --client ipp://192.168.43.175:631/printers/LQ-310 --name LQ-310-IT --test
EOF
}

# --- parse arguments ----------------------------------------------------------
while (($#)); do
  case "$1" in
    --test)      DO_TEST=1 ;;
    --client)    MODE=client; shift
                 [[ $# -gt 0 ]] || die "--client needs an IPP URI, e.g. ipp://host:631/printers/QUEUE"
                 CLIENT_URI="$1" ;;
    --client=*)  MODE=client; CLIENT_URI="${1#--client=}" ;;
    --name)      shift
                 [[ $# -gt 0 ]] || die "--name needs a value"
                 PRINTER="$1"; NAME_SET=1 ;;
    --name=*)    PRINTER="${1#--name=}"; NAME_SET=1 ;;
    --default)   SET_DEFAULT=1 ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done

if [[ "$MODE" == client && -z "$CLIENT_URI" ]]; then
  die "--client needs an IPP URI, e.g. ipp://host:631/printers/QUEUE"
fi

# --- become root --------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "Run this script as root (no sudo found)."
  exec sudo -- "$0" "${ORIG_ARGS[@]}"
fi

# The bundled PPD/wrapper are only needed when installing a local USB printer.
if [[ "$MODE" == server ]]; then
  if [[ ! -f "$PPD_SRC" ]]; then PPD_SRC="$(mktemp /tmp/lq310_ppd.XXXXXX)"; cur''l -fsSL "https://raw.githubusercontent.com/andin1st/EPSON-LQ310/main/LQ-310.ppd" -o "$PPD_SRC" || die "Gagal unduh PPD"; fi
  if [[ ! -f "$WRAPPER_SRC" ]]; then WRAPPER_SRC="$(mktemp /tmp/lq310_wrap.XXXXXX)"; cur''l -fsSL "https://raw.githubusercontent.com/andin1st/EPSON-LQ310/main/foomatic-rip-lq310" -o "$WRAPPER_SRC" || die "Gagal unduh wrapper"; fi
fi

# --- 1. packages (any distro) ---------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

# Which capabilities are missing? (NOTE: on Debian/Ubuntu/Mint the foomatic-rip
# binary is shipped by cups-filters, NOT by foomatic-db-engine, and lpadmin is
# in cups-client, not cups.)
miss_cups=0; have lpadmin      || miss_cups=1
miss_rip=0;  have foomatic-rip || miss_rip=1
miss_db=0
if [[ "$MODE" == server ]]; then
  [[ -d /usr/share/foomatic/db/source/driver || -d /usr/share/foomatic/db ]] || miss_db=1
fi
miss_perl=0; have perl         || miss_perl=1

if (( miss_cups || miss_rip || miss_db || miss_perl )); then
  # Detect the package-manager family.
  if   have pacman;  then FAM=arch
  elif have apt-get; then FAM=debian
  elif have dnf;     then FAM=fedora
  elif have yum;     then FAM=fedora
  elif have zypper;  then FAM=suse
  elif have apk;     then FAM=alpine
  else die "No supported package manager found (apt/dnf/yum/zypper/pacman/apk)."
  fi

  # Map each missing capability to the package that provides it on this family.
  pkgs=()
  case $FAM in
    debian|alpine)
      (( miss_cups )) && pkgs+=(cups cups-client)          # lpadmin = cups-client
      (( miss_rip  )) && pkgs+=(cups-filters)              # foomatic-rip = cups-filters
      (( miss_db   )) && pkgs+=(foomatic-db foomatic-db-engine)
      (( miss_perl )) && pkgs+=(perl)
      ;;
    arch)
      (( miss_cups )) && pkgs+=(cups)
      (( miss_rip  )) && pkgs+=(cups-filters)
      (( miss_db   )) && pkgs+=(foomatic-db foomatic-db-engine)
      (( miss_perl )) && pkgs+=(perl)
      ;;
    fedora)
      (( miss_cups )) && pkgs+=(cups)
      (( miss_rip  )) && pkgs+=(cups-filters foomatic)     # foomatic-rip lives in one of these
      (( miss_db   )) && pkgs+=(foomatic-db foomatic-db-ppds)
      (( miss_perl )) && pkgs+=(perl)
      ;;
    suse)
      (( miss_cups )) && pkgs+=(cups)
      (( miss_rip  )) && pkgs+=(cups-filters)
      (( miss_db   )) && pkgs+=(foomatic-db foomatic-db-engine)
      (( miss_perl )) && pkgs+=(perl)
      ;;
  esac

  # de-duplicate
  if ((${#pkgs[@]})); then
    declare -A seen; uniq=()
    for p in "${pkgs[@]}"; do [[ -n "${seen[$p]:-}" ]] || { seen[$p]=1; uniq+=("$p"); }; done
    pkgs=("${uniq[@]}")
  fi

  log "Missing capabilities: $( ((miss_cups)) && printf 'cups '; ((miss_rip)) && printf 'foomatic-rip '; ((miss_db)) && printf 'foomatic-db '; ((miss_perl)) && printf 'perl '; printf '\n')"
  log "Installing: ${pkgs[*]}"

  # Family-specific installer for an arbitrary list of packages.
  pkg_install() {
    case $FAM in
      debian) DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
      arch)   pacman -Sy --needed --noconfirm "$@" ;;
      fedora) if have dnf; then dnf install -y "$@"; else yum install -y "$@"; fi ;;
      suse)   zypper --non-interactive install "$@" ;;
      alpine) apk add "$@" ;;
    esac
  }

  # Refresh indexes first. On Debian/Ubuntu/Mint also make sure 'universe'
  # (where foomatic-db lives) is enabled, otherwise that package is invisible.
  case $FAM in
    debian)
      if have add-apt-repository; then
        add-apt-repository -y universe >/dev/null 2>&1 || true
      fi
      DEBIAN_FRONTEND=noninteractive apt-get update -qq || true
      ;;
    arch)   pacman -Sy --noconfirm >/dev/null 2>&1 || true ;;
    fedora) { have dnf && dnf -q makecache; } || yum -q makecache || true ;;
    suse)   zypper -q refresh || true ;;
    alpine) apk update || true ;;
  esac

  # Try the whole set, then fall back to installing one package at a time so a
  # single unavailable name can never block the rest.
  if ! pkg_install "${pkgs[@]}"; then
    log "Batch install failed - retrying one package at a time..."
    for p in "${pkgs[@]}"; do
      pkg_install "$p" || log "  (could not install: $p - continuing)"
    done
  fi
fi

# --- verify what we actually need for printing ---------------------------------
have lpadmin      || die "lpadmin still missing - install CUPS (package: cups / cups-client)"
have foomatic-rip || die "foomatic-rip still missing - install the CUPS filters (package: cups-filters / foomatic)"
if [[ "$MODE" == server ]]; then
  [[ -d /usr/share/foomatic/db/source/driver || -d /usr/share/foomatic/db ]] \
    || log "WARNING: foomatic database not found (package: foomatic-db); the bundled PPD usually still works."
fi

# --- 2. cups service ------------------------------------------------------------
start_cups() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now cups >/dev/null 2>&1 || systemctl start cups >/dev/null 2>&1 || true
  elif command -v service >/dev/null 2>&1; then
    service cups start >/dev/null 2>&1 || true
  fi
}
start_cups
for _ in 1 2 3 4 5; do
  lpstat -r 2>/dev/null | grep -q "running" && break
  sleep 1
  start_cups
done
lpstat -r 2>/dev/null | grep -q "running" || die "CUPS scheduler is not running (service cups start)"

# --- 3c. CLIENT MODE: add a network LQ-310 over IPP, then exit --------------------
if [[ "$MODE" == client ]]; then
  # Split the URI into host + port for a reachability check.
  _hp="${CLIENT_URI#*://}"; _hp="${_hp%%/*}"
  _host="${_hp%%:*}"; _port=631
  if [[ "$_hp" == *:* ]]; then _port="${_hp##*:}"; fi

  # Default local queue name: LQ-310-<first label of the host>.
  if (( ! NAME_SET )); then
    _label="${_host%%.*}"
    PRINTER="LQ-310-${_label:-Net}"
  fi
  PRINTER="${PRINTER//[^A-Za-z0-9_.-]/-}"

  log "Client mode: adding a network printer"
  log "  server URI : $CLIENT_URI"
  log "  local queue: $PRINTER"

  # Reachability first, with an actionable message (the usual culprit is a
  # firewall on the server, which shows up as a TCP timeout, not "refused").
  if ! timeout 4 bash -c "exec 3<>/dev/tcp/$_host/$_port" 2>/dev/null; then
    log ""
    log "ERROR: cannot open TCP $_host:$_port - the server is not accepting CUPS/IPP."
    log "The printer is most likely firewalled on the SERVER side. On that PC run:"
    log "  Linux/UFW      : sudo ufw allow 631/tcp"
    log "  Linux/firewalld: sudo firewall-cmd --permanent --add-service=ipp && sudo firewall-cmd --reload"
    log "  then           : sudo cupsctl --share-printers --remote-any && sudo systemctl restart cups"
    log "  Windows        : allow 'Internet Printing' / inbound TCP 631 in Windows Firewall"
    die "Remote printer unreachable ($_host:$_port)."
  fi
  log "Server $_host:$_port is reachable."

  # Warn early if the server queue is not shared: the server will refuse the job
  # ("not authorized - the printer is not shared") and CUPS here will hold it
  # with the alert "cups-held-for-authentication".
  if command -v ipptool >/dev/null 2>&1; then
    if timeout 6 ipptool -tv "$CLIENT_URI" get-printer-attributes.test 2>/dev/null | grep -q "printer-is-shared (boolean) = false"; then
      log ""
      log "WARNING: '$CLIENT_URI' is NOT shared on the server (printer-is-shared=false)."
      log "Printing to it fails with 'not authorized - the printer is not shared' and"
      log "the job stops here as 'held for authentication'. Either use a shared queue,"
      log "or on the server run:  sudo lpadmin -p <QUEUE> -o printer-is-shared=true"
      log ""
    fi
  fi

  # Create the queue: driverless first, then generated PPD, then raw.
  lpadmin -x "$PRINTER" >/dev/null 2>&1 || true
  if lpadmin -p "$PRINTER" -E -v "$CLIENT_URI" -m everywhere 2>/tmp/lq310_client_err; then
    log "Added '$PRINTER' using IPP Everywhere (driverless)."
  else
    log "Driverless (-m everywhere) failed: $(cat /tmp/lq310_client_err 2>/dev/null)"
    lpadmin -x "$PRINTER" >/dev/null 2>&1 || true
    _ppd="$(mktemp --suffix=.ppd)"
    if command -v driverless >/dev/null 2>&1 && driverless "$CLIENT_URI" > "$_ppd" 2>/dev/null && [[ -s "$_ppd" ]]; then
      lpadmin -p "$PRINTER" -E -v "$CLIENT_URI" -P "$_ppd"
      log "Added '$PRINTER' using a generated driverless PPD."
    else
      lpadmin -p "$PRINTER" -E -v "$CLIENT_URI" -m raw
      log "Added '$PRINTER' as a raw queue (the server will render)."
    fi
    rm -f "$_ppd" /tmp/lq310_client_err
  fi

  if (( SET_DEFAULT )); then
    if lpadmin -d "$PRINTER"; then log "Default printer: $PRINTER"; fi
  fi

  if (( DO_TEST )); then
    _t="$(mktemp --suffix=.txt)"
    { echo "Epson LQ-310 - network test"; echo "queue : $PRINTER"; echo "server: $CLIENT_URI"; echo "date  : $(date)"; } > "$_t"
    if lp -d "$PRINTER" "$_t"; then log "Test job sent to '$PRINTER'."; else log "NOTE: test print failed."; fi
    rm -f "$_t"
  fi

  log ""
  lpstat -v "$PRINTER" 2>&1 || true
  lpstat -p  "$PRINTER" 2>&1 || true
  log ""
  log "Print with:  lp -d $PRINTER file.pdf"
  log "Remove with: sudo lpadmin -x $PRINTER"
  exit 0
fi

# --- 3. detect the printer on USB ------------------------------------------------
find_usb_uri() {
  local uri dev vid prod man ser
  # preferred: CUPS USB backend discovery
  for _ in 1 2 3; do
    uri="$(lpinfo -v 2>/dev/null | grep -o 'usb://[^ ]*LQ-310[^ ]*' | head -n1 || true)"
    if [[ -n "$uri" ]]; then printf '%s\n' "$uri"; return 0; fi
    sleep 1
  done
  # fallback: build the URI straight from sysfs
  for dev in /sys/bus/usb/devices/*; do
    [[ -r "$dev/idVendor" && -r "$dev/product" ]] || continue
    read -r vid < "$dev/idVendor"
    [[ "$vid" == "04b8" ]] || continue
    read -r prod < "$dev/product"
    [[ "$prod" == *LQ-310* ]] || continue
    man="$(cat "$dev/manufacturer" 2>/dev/null || echo EPSON)"
    ser="$(cat "$dev/serial" 2>/dev/null || true)"
    printf 'usb://%s/%s%s\n' "$man" "$prod" "${ser:+?serial=$ser}"
    return 0
  done
  return 1
}

URI="$(find_usb_uri)" || {
  if command -v lsusb >/dev/null 2>&1 && lsusb -d 04b8: >/dev/null 2>&1; then
    die "An Epson is on USB but CUPS did not list LQ-310. Re-plug it and re-run."
  fi
  die "Epson LQ-310 not found on USB. Plug it in and run this script again."
}
log "USB device: $URI"

# --- 4. install wrapper ------------------------------------------------------------
install -m 755 "$WRAPPER_SRC" "$WRAPPER_DST"
log "Installed wrapper: $WRAPPER_DST (ESC C 33 = 5.5 inch page length)"
# Remove a legacy copy from /usr/local/bin: AppArmor's CUPS profile only grants
# execute under /usr/lib/cups/filter/**, so a filter in /usr/local/bin fails
# with "execv failed: Permission denied".
rm -f /usr/local/bin/foomatic-rip-lq310

# --- 5. create/update the queue ------------------------------------------------------
PPD="$(mktemp --suffix=.ppd)"
trap 'rm -f "$PPD"' EXIT
cp "$PPD_SRC" "$PPD"

lpadmin -p "$PRINTER" -E -P "$PPD" -v "$URI"
lpadmin -d "$PRINTER"
log "Queue '$PRINTER' ready (default printer, page size 5.5x8.5)"

# --- 6. optional test print ------------------------------------------------------------
if [[ $DO_TEST -eq 1 ]]; then
  TEST="$(mktemp --suffix=.txt)"
  cat > "$TEST" <<'TESTEOF'
=====================================
  Epson LQ-310 - installation test
=====================================
Queue           : LQ-310
Paper           : 5.5 x 8.5 inch
Feed length     : 5.5 inch (ESC C 33)
Printable area : 6 mm margins

If this page prints top-to-bottom on ONE sheet and the
printer advances cleanly to the next form (stopping at the
perforation), the setup is complete.
TESTEOF
  lp -d "$PRINTER" "$TEST" || log "NOTE: text test print failed - is cups-filters (texttopdf) installed?"
  rm -f "$TEST"
fi

# --- summary -----------------------------------------------------------------------------
log ""
lpstat -v "$PRINTER"
lpstat -p "$PRINTER"
log ""
log "Print any document with:  lp -d $PRINTER file.pdf"
log "Re-run this script anytime to repair the setup."
