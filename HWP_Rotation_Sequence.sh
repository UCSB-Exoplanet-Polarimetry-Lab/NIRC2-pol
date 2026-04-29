#!/usr/bin/env bash
# hwp_rot_seq.sh — HWP (PCU rotator) movement with NIRC2 images

# --------------------
# Defaults (override with key=value args)
ANGLES="0 45 22.5 67.5"          # list of HWP angles (deg)
TOL=0.05                         # degrees tolerance
POLL=0.4                         # seconds between queries
NUM_EXPOSURES=1                  # exposures per HWP angle
HWP_CYCLES=1                     # number of HWP cycles
#FILT=""

# Additive offsets (currently unused)
J_ADD=0
H_ADD=0
K_ADD=0

# Dither defaults
DITHER=0                         # 0 = no dither (default), 1 = ABBA dither
XY=""                            # string "dx dy"
DX=""
DY=""

# Test mode (for dithers)
TEST_MODE=0                      # 0 = normal, 1 = test (wait 30s instead of xy)

# Track whether OBJ was set by user
OBJ="test_pcu_rotation"
OBJ_FROM_ARGS=0

print_usage() {
  cat <<EOF
Usage:
  $0 [OBJ="name"] [ANGLES="0 22.5 45 67.5"] [TOL=0.05] [POLL=0.1] [NUM_EXPOSURES=1] [HWP_CYCLES=1] [XY="dx dy"] [TEST=true]

  Example with dither:
    $0 XY="3 0"

  Example with dither in test mode (no actual xy, just 30 s waits):
    $0 XY="3 0" TEST=true
EOF
}

# Parse args
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
        [Tt][Rr][Uu][Ee]|1|[Yy][Ee][Ss])
          TEST_MODE=1
          ;;
        *)
          TEST_MODE=0
          ;;
      esac
      ;;
    # FILT)           FILT="$val" ;;
    *)
      echo "Error: Unknown option '$key'."
      print_usage
      exit 1
      ;;
  esac
done

# Validations
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

apply_offset_to_angles() {
  local angles_str="$1" off="$2" out="" new
  for a in $angles_str; do
    new=$(awk -v x="$a" -v o="$off" 'BEGIN{printf "%.10g", x+o}')
    out+="$new "
  done
  printf '%s\n' "${out% }"
}

# If OBJ was *not* provided by user, pull current NIRC2 OBJECT as default
if [[ "$OBJ_FROM_ARGS" -eq 0 ]]; then
  OBJ_LINE=$(object 2>/dev/null)

  # Expected format: "OBJECT = ao_confirmation" (be tolerant of spacing)
  OBJ_PARSED=$(printf '%s\n' "$OBJ_LINE" | awk -F'=' '/OBJECT/ {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2);  # trim spaces
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

### KTL CHANGE:
if ! show -s pcu2 PCUPR >/dev/null 2>&1; then
  echo "KTL keyword not reachable: PCUPR"
  exit 1
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
  echo "  TEST MODE          = YES (dithers sleep 30 s, no xy)"
else
  echo "  TEST MODE          = NO"
fi
echo "--------------------------------------------------"
read -r -p "Does this look correct? Press Enter to continue, or type anything to cancel: " resp
if [[ -n "$resp" ]]; then
  echo "Aborting."
  exit 1
fi

### KTL CHANGE:
show -s pcu2 PCURSTAT || true
show -s pcu2 PCUPR || true

# ----------------------------------------------------------------------
# Helper: attempt a dither (test mode aware)
# ----------------------------------------------------------------------
attempt_dither() {
  local dx="$1"
  local dy="$2"

  echo "Executing dither: xy $dx $dy"
  xy "$dx" "$dy"

  return 0
}

# ----------------------------------------------------------------------
# Helper: run a given number of HWP cycles at the current telescope position
# ----------------------------------------------------------------------

run_hwp_cycles() {
  local cycles="$1"
  local cycle ang pos err rfloat

  for ((cycle=1; cycle<=cycles; cycle++)); do
    echo "==== Starting HWP cycle $cycle of $cycles ===="
    for ang in $ANGLES; do
      echo "---- Moving to HWP $ang deg ----"

      ### KTL CHANGE:
      if ! modify -s pcu2 PCUPR="$ang"; then
        echo "Error: modify failed ($ang deg)"
        exit 1
      fi

      # Poll for convergence
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

      rfloat=$(printf "%.1f" "$ang")
      label="${BASE_OBJ}_hwp_${rfloat}"

      object "$label" || { echo "object failed ($label)"; break; }
      goi -s "$NUM_EXPOSURES" || { echo "goi failed ($label x$NUM_EXPOSURES)"; break; }
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
  # No dithering: just run the requested number of HWP cycles at the base position
  run_hwp_cycles "$HWP_CYCLES"
else
  echo "Dithering enabled with XY offset: DX=$DX DY=$DY"

  # A: base position, n cycles
  echo "=== Position A: base, running $HWP_CYCLES HWP cycles ==="
  run_hwp_cycles "$HWP_CYCLES"

  # B: dithered position, 2n cycles
  echo "=== Dithering to position B: xy $DX $DY ==="
  attempt_dither "$DX" "$DY"
  echo "=== Position B: running $((2 * HWP_CYCLES)) HWP cycles ==="
  run_hwp_cycles $((2 * HWP_CYCLES))

  # A again: dither back, n cycles
  NEG_DX=$(awk -v x="$DX" 'BEGIN{printf "%.10g", -x}')
  NEG_DY=$(awk -v y="$DY" 'BEGIN{printf "%.10g", -y}')
  echo "=== Dithering back to position A: xy $NEG_DX $NEG_DY ==="
  attempt_dither "$NEG_DX" "$NEG_DY"
  echo "=== Position A (again): running $HWP_CYCLES HWP cycles ==="
  run_hwp_cycles "$HWP_CYCLES"
fi

echo "Final HWP rotator position:"
### KTL CHANGE:
show -s pcu2 PCUPR || echo "Error: Failed to read final rotator position."

# Play script complete sound once at very end
modify -s nirc2plus scriptip =Yes
modify -s nirc2plus scriptip =No
