#!/usr/bin/env bash
# hwp_rot_seq.sh — HWP (PCU rotator) movement with NIRC2 images

# Point Channel Access at your IOC (non-standard port 8606)
# export EPICS_CA_AUTO_ADDR_LIST=NO
# export EPICS_CA_ADDR_LIST=127.0.0.1:8606
# Only run this after making sure the k1_pcu.scr file is running in a separate screen
# export EPICS_CA_ADDR_LIST=localhost:860

# --------------------
# Defaults (override with key=value args)
OBJ="test_pcu_rotation_v2"          # object base name (quotes OK if spaces)
ANGLES="0 22.5 45 67.5"             # list of HWP angles (deg)
TOL=0.05                            # degrees tolerance
POLL=0.1                            # seconds between queries
NUM_EXPOSURES=1                     # exposures per HWP angle
HWP_CYCLES=1                        # number of HWP cycles
# --------------------

print_usage() {
  cat <<EOF
Usage:
  $0 [OBJ="name"] [ANGLES="0 22.5 45 67.5"] [TOL=0.05] [POLL=0.1] [NUM_EXPOSURES=1] [HWP_CYCLES=1]

Examples:
  $0
  $0 NUM_EXPOSURES=3 HWP_CYCLES=2
  $0 OBJ="hd183143" ANGLES="0 45 90 135" NUM_EXPOSURES=5

Valid keys (case-insensitive): OBJ, ANGLES, TOL, POLL, NUM_EXPOSURES, HWP_CYCLES
EOF
}

# --- parse optional key=value args (case-insensitive keys, safe: no eval) ---
for arg in "$@"; do
  if [[ "$arg" != *=* ]]; then
    echo "Error: Arguments must be key=value. Got: $arg"
    print_usage
    exit 1
  fi
  key="${arg%%=*}"
  val="${arg#*=}"
  # Portable uppercase (works on Bash 3.2)
  key_upper=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')

  case "$key_upper" in
    OBJ)            OBJ="$val" ;;
    ANGLES)         ANGLES="$val" ;;
    TOL)            TOL="$val" ;;
    POLL)           POLL="$val" ;;
    NUM_EXPOSURES)  NUM_EXPOSURES="$val" ;;
    HWP_CYCLES)     HWP_CYCLES="$val" ;;
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
re_num='^([0-9]*\.?[0-9]+)$'

if ! [[ "$NUM_EXPOSURES" =~ $re_int ]] || [ "$NUM_EXPOSURES" -le 0 ]; then
  echo "Error: NUM_EXPOSURES must be a positive integer. Got: '$NUM_EXPOSURES'"; exit 1
fi
if ! [[ "$HWP_CYCLES" =~ $re_int ]] || [ "$HWP_CYCLES" -le 0 ]; then
  echo "Error: HWP_CYCLES must be a positive integer. Got: '$HWP_CYCLES'"; exit 1
fi
if ! [[ "$TOL" =~ $re_num ]]; then
  echo "Error: TOL must be numeric. Got: '$TOL'"; exit 1
fi
if ! [[ "$POLL" =~ $re_num ]]; then
  echo "Error: POLL must be numeric. Got: '$POLL'"; exit 1
fi

echo "Running with:"
echo "  OBJ           = $OBJ"
echo "  ANGLES        = $ANGLES"
echo "  TOL           = $TOL"
echo "  POLL          = $POLL"
echo "  NUM_EXPOSURES = $NUM_EXPOSURES"
echo "  HWP_CYCLES    = $HWP_CYCLES"

# --- Quick reachability check ---
# if ! cainfo -w 2 k2:ao:pcu:rot:posvalRb >/dev/null 2>&1; then
#   echo "PV not reachable: k2:ao:pcu:rot:posvalRb"; exit 1
# fi

# # --- status / (optional) home ---
# caget -S k2:ao:pcu:rot:statRb || true
# caget    k2:ao:pcu:rot:posvalRb || true
# # caput k2:ao:pcu:rot:home 1

# # --- helper: absolute difference ---
# absdiff() {
#   awk -v a="$1" -v b="$2" 'BEGIN{d=a-b; if(d<0)d=-d; print d}'
# }

# # --- Main loop: cycles × angles ---
# for ((cycle=1; cycle<=HWP_CYCLES; cycle++)); do
#   echo "==== Starting HWP cycle $cycle of $HWP_CYCLES ===="
#   for ang in $ANGLES; do
#     echo "---- Moving to HWP $ang deg ----"
#     if ! caput k2:ao:pcu:rot:posval "$ang"; then
#       echo "Error: Failed to set rotator position to $ang degrees."
#       continue
#     fi

#     # Poll until within tolerance
#     while true; do
#       pos=$(caget -t k2:ao:pcu:rot:posvalRb 2>/dev/null) || { echo "Error: Failed to read rotator position."; break; }
#       echo "HWP rotator posvalRb=$pos"
#       err=$(absdiff "$pos" "$ang")
#       if awk -v e="$err" -v tol="$TOL" 'BEGIN{exit !(e<=tol)}'; then
#         break
#       fi
#       sleep "$POLL"
#     done

#     rfloat=$(printf "%.1f" "$ang")
#     # Take NUM_EXPOSURES images, label with cycle & exposure index
#     for ((i=1; i<=NUM_EXPOSURES; i++)); do
#       label="${OBJ}_hwp_${rfloat}_cyc_${cycle}_exp_${i}"
#       ssh nirc2eng@waikoko-new object "$label" || { echo "Error: object cmd failed ($label)"; break; }
#       ssh nirc2eng@waikoko-new goi || { echo "Error: goi failed ($label)"; break; }
#     done
#   done
# done

# # Final readback
# echo "Final HWP rotator position:"
# caget k2:ao:pcu:rot:posvalRb || echo "Error: Failed to read final rotator position."
