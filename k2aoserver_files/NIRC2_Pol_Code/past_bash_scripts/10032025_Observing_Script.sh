#!/usr/bin/env bash
# hwp_rot_seq.sh — HWP (PCU rotator) movement with NIRC2 images

# --------------------
# Defaults (override with key=value args)
OBJ="test_pcu_rotation_v2"          # object base name (quotes OK if spaces)
ANGLES="0 22.5 45 67.5"             # list of HWP angles (deg)
TOL=0.05                            # degrees tolerance
POLL=0.1                            # seconds between queries
NUM_EXPOSURES=1                     # exposures per HWP angle
HWP_CYCLES=1                        # number of HWP cycles
FILT=""                             # REQUIRED: J/H/K (uppercase only)
# --------------------

# Hard-coded per-filter additive offsets (deg) applied to EVERY ANGLES element.
# >>> EDIT THESE to your calibrated fast-axis values <<<
# From 09/15/2025 HWP modulation data for J and K and 10/02/2025 for H
J_ADD=0
H_ADD=0
K_ADD=0

print_usage() {
  cat <<EOF
Usage:
  $0 FILT=J|H|K [OBJ="name"] [ANGLES="0 22.5 45 67.5"] [TOL=0.05] [POLL=0.1] [NUM_EXPOSURES=1] [HWP_CYCLES=1]

Examples:
  $0 FILT=H
  $0 FILT=K NUM_EXPOSURES=5 HWP_CYCLES=2
  $0 FILT=J OBJ="hd183143" ANGLES="0 45 90 135" TOL=0.1 POLL=0.2
EOF
}

# --- parse optional key=value args (case-insensitive keys, safe: no eval) ---
for arg in "$@"; do
  if [[ "$arg" != *=* ]]; then
    echo "Error: Arguments must be key=value. Got: $arg"; print_usage; exit 1
  fi
  key="${arg%%=*}"
  val="${arg#*=}"
  key_upper=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')

  case "$key_upper" in
    OBJ)            OBJ="$val" ;;
    ANGLES)         ANGLES="$val" ;;
    TOL)            TOL="$val" ;;
    POLL)           POLL="$val" ;;
    NUM_EXPOSURES)  NUM_EXPOSURES="$val" ;;
    HWP_CYCLES)     HWP_CYCLES="$val" ;;
    FILT)           FILT="$val" ;;
    -H|--HELP)      print_usage; exit 0 ;;
    *)
      echo "Error: Unknown option '$key'."; print_usage; exit 1 ;;
  esac
done

# --- validations ---
re_int='^[0-9]+$'
re_num='^([0-9]*\.?[0-9]+)$'

if [[ -z "$FILT" ]]; then
  echo "Error: FILT is required (must be uppercase J, H, or K)."; print_usage; exit 1
fi
# Enforce uppercase only
if [[ "$FILT" =~ ^[jhk]$ ]]; then
  echo "Error: FILT must be uppercase (J, H, or K). You provided '$FILT'."; exit 1
fi
if [[ ! "$FILT" =~ ^[JHK]$ ]]; then
  echo "Error: FILT must be exactly one of J, H, or K (uppercase). Got '$FILT'."; exit 1
fi

if ! [[ "$NUM_EXPOSURES" =~ $re_int ]] || [ "$NUM_EXPOSURES" -le 0 ]; then
  echo "Error: NUM_EXPOSURES must be a positive integer. Got: '$NUM_EXPOSURES'"; exit 1; fi
if ! [[ "$HWP_CYCLES" =~ $re_int ]] || [ "$HWP_CYCLES" -le 0 ]; then
  echo "Error: HWP_CYCLES must be a positive integer. Got: '$HWP_CYCLES'"; exit 1; fi
if ! [[ "$TOL" =~ $re_num ]];  then echo "Error: TOL must be numeric. Got: '$TOL'"; exit 1; fi
if ! [[ "$POLL" =~ $re_num ]]; then echo "Error: POLL must be numeric. Got: '$POLL'"; exit 1; fi

# --- helper: absolute difference ---
absdiff() { awk -v a="$1" -v b="$2" 'BEGIN{d=a-b; if(d<0)d=-d; print d}'; }

# --- helper: apply additive offset (deg) to every ANGLES element ---
apply_offset_to_angles() {
  local angles_str="$1" off="$2" out="" new
  for a in $angles_str; do
    new=$(awk -v x="$a" -v o="$off" 'BEGIN{printf "%.10g", x+o}')
    out+="$new "
  done
  printf '%s\n' "${out% }"
}

# --- choose offset by FILT and transform ANGLES ---
case "$FILT" in
  J) ANGLES=$(apply_offset_to_angles "$ANGLES" "$J_ADD") ;;
  H) ANGLES=$(apply_offset_to_angles "$ANGLES" "$H_ADD") ;;
  K) ANGLES=$(apply_offset_to_angles "$ANGLES" "$K_ADD") ;;
esac

echo "Running with:"
echo "  FILT          = $FILT"
echo "  OBJ           = $OBJ"
echo "  ANGLES        = $ANGLES"
echo "  TOL           = $TOL"
echo "  POLL          = $POLL"
echo "  NUM_EXPOSURES = $NUM_EXPOSURES"
echo "  HWP_CYCLES    = $HWP_CYCLES"

read -r -p "Does this look correct? Press Enter to continue, or type anything to cancel: " resp
if [[ -n "$resp" ]]; then
  echo "Aborting"
  break   # or 'exit 1' if you want to abort the whole script
fi

# --- Quick reachability check ---
if ! cainfo -w 2 k2:ao:pcu:rot:posvalRb >/dev/null 2>&1; then
  echo "PV not reachable: k2:ao:pcu:rot:posvalRb"; exit 1
fi

# --- status / (optional) home ---
caget -S k2:ao:pcu:rot:statRb || true
caget    k2:ao:pcu:rot:posvalRb || true

# --- Main loop: cycles × angles ---
for ((cycle=1; cycle<=HWP_CYCLES; cycle++)); do
  echo "==== Starting HWP cycle $cycle of $HWP_CYCLES ===="
  for ang in $ANGLES; do
    echo "---- Moving to HWP $ang deg ----"
    if ! caput k2:ao:pcu:rot:posval "$ang"; then
      echo "Error: Failed to set rotator position to $ang degrees."
      continue
    fi

    # Poll until within tolerance
    while true; do
      pos=$(caget -t k2:ao:pcu:rot:posvalRb 2>/dev/null) || { echo "Error: Failed to read rotator position."; break; }
      echo "HWP rotator posvalRb=$pos"
      err=$(absdiff "$pos" "$ang")
      if awk -v e="$err" -v tol="$TOL" 'BEGIN{exit !(e<=tol)}'; then
        break
      fi
      sleep "$POLL"
    done

    rfloat=$(printf "%.1f" "$ang")
    label="${OBJ}_filt_${FILT}_hwp_${rfloat}_cyc_${cycle}"
    
    # Two separate SSH calls, concise failure handling like before
    ssh nirc2eng@waikoko-new object "$label" \
      || { echo "Error: object cmd failed ($label)"; break; }
    ssh nirc2eng@waikoko-new goi "$NUM_EXPOSURES" \
      || { echo "Error: goi failed ($label x$NUM_EXPOSURES)"; break; }
  done
done

# Final readback
echo "Final HWP rotator position:"
caget k2:ao:pcu:rot:posvalRb || echo "Error: Failed to read final rotator position."
