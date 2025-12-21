#!/usr/bin/env bash
# hwp_rot_seq.sh — HWP (PCU rotator) movement with NIRC2 images
set -u

# --------------------
# Defaults (override with key=value args)
ANGLES="0 45 22.5 67.5"          # list of HWP angles (deg)
TOL=0.05                         # degrees tolerance
POLL=0.4                         # seconds between HWP position queries
NUM_EXPOSURES=1                  # exposures per HWP angle
HWP_CYCLES=1                     # number of HWP cycles

# Dither defaults
DITHER=0                         # 0 = no dither (default), 1 = ABBA dither
XY=""                            # string "dx dy"
DX=""
DY=""

# Test mode (for dithers) — currently not used in attempt_dither (kept as-is)
TEST_MODE=0                      # 0 = normal, 1 = test

# Pipelining: move HWP during Filewait (safe overlap)
PIPELINE=1                       # 1 = enable (default), 0 = disable
FILEWAIT_POLL=0.1                # seconds between expstate polls
FILEWAIT_TIMEOUT=600             # seconds before giving up moving-next-angle

# Track whether OBJ was set by user
OBJ="test_pcu_rotation"
OBJ_FROM_ARGS=0

print_usage() {
  cat <<EOF
Usage:
  $0 [OBJ="name"] [ANGLES="0 22.5 45 67.5"] [TOL=0.05] [POLL=0.4] [NUM_EXPOSURES=1] [HWP_CYCLES=1] [XY="dx dy"] [TEST=true] [PIPELINE=true]

  Example with dither:
    $0 XY="3 0"

  Example enabling/disabling pipeline explicitly:
    $0 PIPELINE=true
    $0 PIPELINE=false
EOF
}

# --- parse key=value args (case-insensitive keys, safe: no eval) ---
for arg in "$@"; do
  if [[ "$arg" != *=* ]]; then
    echo "Error: Arguments must be key=value. Got: $arg"
    print_usage
    exit 1
  fi
  key="${arg%%=*}"
  val="${arg#*=}"
  key_upper=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')

  case "$key_upper" in
    OBJ)
      OBJ="$val"
      OBJ_FROM_ARGS=1
      ;;
    ANGLES)         ANGLES="$val" ;;
    TOL)            TOL="$val" ;;
    POLL)           POLL="$val" ;;
    NUM_EXPOSURES)  NUM_EXPOSURES="$val" ;;
    HWP_CYCLES)     HWP_CYCLES="$val" ;;
    XY)
      XY="$val"
      DITHER=1
      ;;
    TEST)
      case "$val" in
        [Tt][Rr][Uu][Ee]|1|[Yy][Ee][Ss]) TEST_MODE=1 ;;
        *)                               TEST_MODE=0 ;;
      esac
      ;;
    PIPELINE)
      case "$val" in
        [Tt][Rr][Uu][Ee]|1|[Yy][Ee][Ss]) PIPELINE=1 ;;
        *)                               PIPELINE=0 ;;
      esac
      ;;
    -H|--HELP)      print_usage; exit 0 ;;
    *)
      echo "Error: Unknown option '$key'."
      print_usage
      exit 1
      ;;
  esac
done

# --- validations ---
re_int='^[0-9]+$'
# allow optional + or - sign for floats
re_num='^[+-]?[0-9]*\.?[0-9]+$'

if ! [[ "$NUM_EXPOSURES" =~ $re_int ]] || [ "$NUM_EXPOSURES" -le 0 ]; then
  echo "Error: NUM_EXPOSURES must be positive int"
  exit 1
fi
if ! [[ "$HWP_CYCLES" =~ $re_int ]] || [ "$HWP_CYCLES" -le 0 ]; then
  echo "Error: HWP_CYCLES must be positive int"
  exit 1
fi
if ! [[ "$TOL" =~ $re_num ]]; then
  echo "Error: TOL must be numeric"
  exit 1
fi
if ! [[ "$POLL" =~ $re_num ]]; then
  echo "Error: POLL must be numeric"
  exit 1
fi

# Parse XY if given (dx dy)
if [[ "$DITHER" -eq 1 ]]; then
  # Expect XY to be something like "3 0" or "-3 1.5"
  read -r DX DY <<< "$XY"
  if [[ -z "$DX" || -z "$DY" ]]; then
    echo "Error: XY must contain two numbers, e.g. XY=\"3 0\""
    exit 1
  fi
  if ! [[ "$DX" =~ $re_num ]] || ! [[ "$DY" =~ $re_num ]]; then
    echo "Error: XY components must be numeric. Got: DX='$DX' DY='$DY'"
    exit 1
  fi
fi

absdiff() { awk -v a="$1" -v b="$2" 'BEGIN{d=a-b; if(d<0)d=-d; print d}'; }

# If OBJ was *not* provided by user, pull current NIRC2 OBJECT as default
if [[ "$OBJ_FROM_ARGS" -eq 0 ]]; then
  OBJ_LINE=$(object 2>/dev/null)

  # Expected format: "OBJECT = ao_confirmation" (be tolerant of spacing)
  OBJ_PARSED=$(printf '%s\n' "$OBJ_LINE" | awk -F'=' '/OBJECT/ {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2);
    print $2
  }')

  if [[ -n "$OBJ_PARSED" ]]; then
    OBJ="$OBJ_PARSED"
    echo "Using NIRC2 OBJECT base name: $OBJ"
  else
    echo "Warning: Could not parse NIRC2 OBJECT from: '$OBJ_LINE'"
    echo "         Using fallback OBJ='$OBJ'."
  fi
else
  echo "Using user-specified OBJ: $OBJ"
fi

# get base name of object (strip any trailing _hwp...)
if [[ "$OBJ" == *_hwp* ]]; then
  BASE_OBJ="${OBJ%%_hwp*}"
else
  BASE_OBJ="$OBJ"
fi

# ----------------------------------------------------------------------
# REACHABILITY CHECK — KTL keywords
# ----------------------------------------------------------------------
if ! show -s pcu2 PCUPR >/dev/null 2>&1; then
  echo "KTL keyword not reachable: PCUPR"
  exit 1
fi

# Pipeline needs alad expstate; if unreachable, disable pipeline safely
if [[ "$PIPELINE" -eq 1 ]]; then
  if ! show -s alad expstate >/dev/null 2>&1; then
    echo "Warning: KTL keyword not reachable: alad expstate"
    echo "         Disabling PIPELINE mode."
    PIPELINE=0
  fi
fi

# ----------------------------------------------------------------------
# SUMMARY & CONFIRMATION
# ----------------------------------------------------------------------
echo "--------------------------------------------------"
echo "NIRC2 HWP sequence will run with:"
echo "  BASE OBJECT NAME   = $BASE_OBJ"
echo "  ORIGINAL OBJ NAME  = $OBJ"
echo "  HWP ANGLES         = $ANGLES"
echo "  HWP CYCLES         = $HWP_CYCLES"
echo "  NUM EXPOSURES      = $NUM_EXPOSURES"
echo "  TOLERANCE          = $TOL deg"
echo "  POLL INTERVAL      = $POLL s"
if [[ "$DITHER" -eq 1 ]]; then
  echo "  DITHERING          = YES (ABBA)"
  echo "  DITHER OFFSETS     = DX=$DX  DY=$DY"
else
  echo "  DITHERING          = NO"
fi
if [[ "$TEST_MODE" -eq 1 ]]; then
  echo "  TEST MODE          = YES"
else
  echo "  TEST MODE          = NO"
fi
if [[ "$PIPELINE" -eq 1 ]]; then
  echo "  PIPELINE           = YES (move HWP during Filewait)"
  echo "  FILEWAIT_POLL      = $FILEWAIT_POLL s"
  echo "  FILEWAIT_TIMEOUT   = $FILEWAIT_TIMEOUT s"
else
  echo "  PIPELINE           = NO"
fi
echo "--------------------------------------------------"
read -r -p "Does this look correct? Press Enter to continue, or type anything to cancel: " resp
if [[ -n "$resp" ]]; then
  echo "Aborting."
  exit 1
fi

show -s pcu2 PCURSTAT || true
show -s pcu2 PCUPR || true

# ----------------------------------------------------------------------
# Helper: attempt a dither (as currently implemented)
# ----------------------------------------------------------------------
attempt_dither() {
  local dx="$1"
  local dy="$2"
  echo "Executing dither: xy $dx $dy"
  xy "$dx" "$dy"
  return 0
}

# ----------------------------------------------------------------------
# Helper: start a background watcher that moves to next HWP angle at Filewait
#   - Arms only after seeing a non-Filewait state (prevents immediate trigger)
#   - Times out and exits without moving if Filewait never appears
#   - Echoes PID
# ----------------------------------------------------------------------
start_filewait_watcher() {
  local next_ang="$1"

  (
    local armed=0
    local start=$SECONDS

    while true; do
      local state
      state=$(show -s alad expstate 2>/dev/null | awk '{print $3}')

      # Arm once we see something other than Filewait
      if [[ "$state" != "Filewait" && -n "$state" ]]; then
        armed=1
      fi

      # Only trigger once armed
      if [[ "$armed" -eq 1 && "$state" == "Filewait" ]]; then
        echo "PIPELINE: detected Filewait → moving HWP to $next_ang deg"
        modify -s pcu2 PCUPR="$next_ang" >/dev/null 2>&1 || {
          echo "PIPELINE: Warning: modify failed for next HWP angle ($next_ang deg)"
        }
        exit 0
      fi

      # Timeout
      if (( SECONDS - start >= FILEWAIT_TIMEOUT )); then
        echo "PIPELINE: Warning: timeout waiting for Filewait (no pre-move to $next_ang deg)"
        exit 0
      fi

      sleep "$FILEWAIT_POLL"
    done
  ) &

  echo $!
}

# ----------------------------------------------------------------------
# Helper: move HWP to a target and wait for convergence (existing behavior)
# ----------------------------------------------------------------------
move_hwp_and_wait() {
  local ang="$1"
  local pos err

  echo "---- Moving to HWP $ang deg ----"

  if ! modify -s pcu2 PCUPR="$ang"; then
    echo "Error: modify failed ($ang deg)"
    exit 1
  fi

  while true; do
    pos=$(show -s pcu2 PCUPR 2>/dev/null | awk '{print $3+0}') \
      || { echo "Error: failed reading position"; break; }

    echo "HWP angle readback = $pos deg"

    err=$(absdiff "$pos" "$ang")
    if awk -v e="$err" -v tol="$TOL" 'BEGIN{exit !(e<=tol)}'; then
      break
    fi
    sleep "$POLL"
  done
}

# ----------------------------------------------------------------------
# Helper: run a given number of HWP cycles at the current telescope position
#   - Integrated safe overlap: pipeline HWP move during Filewait
# ----------------------------------------------------------------------
run_hwp_cycles() {
  local cycles="$1"
  local cycle i ang next_ang pos err rfloat label watcher_pid angles_arr

  # Convert ANGLES string to array once
  angles_arr=($ANGLES)

  for ((cycle=1; cycle<=cycles; cycle++)); do
    echo "==== Starting HWP cycle $cycle of $cycles ===="

    for ((i=0; i<${#angles_arr[@]}; i++)); do
      ang="${angles_arr[$i]}"

      # In non-pipeline mode, we always move here.
      # In pipeline mode, we ALSO do it here (safe), even if pre-move already happened.
      move_hwp_and_wait "$ang"

      rfloat=$(printf "%.1f" "$ang")
      label="${BASE_OBJ}_hwp_${rfloat}"

      # Determine next angle for pipelining (only within this cycle)
      next_ang=""
      if [[ "$PIPELINE" -eq 1 && $i -lt $((${#angles_arr[@]} - 1)) ]]; then
        next_ang="${angles_arr[$((i+1))]}"
      fi

      watcher_pid=""
      if [[ -n "$next_ang" ]]; then
        echo "PIPELINE: will pre-move next HWP angle ($next_ang deg) during Filewait"
        watcher_pid=$(start_filewait_watcher "$next_ang")
      fi

      object "$label" || { echo "object failed ($label)"; exit 1; }
      goi -s "$NUM_EXPOSURES" || { echo "goi failed ($label x$NUM_EXPOSURES)"; exit 1; }

      # Ensure watcher is done before we proceed (prevents racing PCUPR)
      if [[ -n "$watcher_pid" ]]; then
        if kill -0 "$watcher_pid" >/dev/null 2>&1; then
          wait "$watcher_pid" >/dev/null 2>&1 || true
        fi
      fi
    done

    # Play end-of-sequence sound AFTER EACH HWP CYCLE
    modify -s nirc2plus sequenceip =Yes
    modify -s nirc2plus sequenceip =No
  done
}

# ----------------------------------------------------------------------
# Main loop with optional ABBA dither
# ----------------------------------------------------------------------
if [[ "$DITHER" -eq 0 ]]; then
  run_hwp_cycles "$HWP_CYCLES"
else
  echo "Dithering enabled with XY offset: DX=$DX DY=$DY"

  echo "=== Position A: base, running $HWP_CYCLES HWP cycles ==="
  run_hwp_cycles "$HWP_CYCLES"

  echo "=== Dithering to position B: xy $DX $DY ==="
  attempt_dither "$DX" "$DY"
  echo "=== Position B: running $((2 * HWP_CYCLES)) HWP cycles ==="
  run_hwp_cycles $((2 * HWP_CYCLES))

  NEG_DX=$(awk -v x="$DX" 'BEGIN{printf "%.10g", -x}')
  NEG_DY=$(awk -v y="$DY" 'BEGIN{printf "%.10g", -y}')
  echo "=== Dithering back to position A: xy $NEG_DX $NEG_DY ==="
  attempt_dither "$NEG_DX" "$NEG_DY"
  echo "=== Position A (again): running $HWP_CYCLES HWP cycles ==="
  run_hwp_cycles "$HWP_CYCLES"
fi

echo "Final HWP rotator position:"
show -s pcu2 PCUPR || echo "Error: Failed to read final rotator position."

# Play script complete sound once at very end
modify -s nirc2plus scriptip =Yes
modify -s nirc2plus scriptip =No
