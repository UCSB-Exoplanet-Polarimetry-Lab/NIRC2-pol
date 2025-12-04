#!/usr/bin/env bash
# hwp_rot_seq.sh — HWP (PCU rotator) movement with NIRC2 images

# --------------------
# Defaults (override with key=value args)
OBJ="test_pcu_rotation"
ANGLES="0 45 22.5 67.5"
TOL=0.05
POLL=0.4
NUM_EXPOSURES=1
HWP_CYCLES=1
#FILT=""

# Additive offsets
J_ADD=0
H_ADD=0
K_ADD=0

print_usage() {
  cat <<EOF
Usage:
  $0 [OBJ="name"] [ANGLES="0 22.5 45 67.5"] [TOL=0.05] [POLL=0.1] [NUM_EXPOSURES=1] [HWP_CYCLES=1]
EOF
}

# Parse args
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
    # FILT)           FILT="$val" ;;
    *)
      echo "Error: Unknown option '$key'."; print_usage; exit 1 ;;
  esac
done

# Validations
re_int='^[0-9]+$'
re_num='^([0-9]*\.?[0-9]+)$'

# if [[ -z "$FILT" ]]; then echo "Error: FILT required"; exit 1; fi
# if [[ "$FILT" =~ ^[jhk]$ ]]; then echo "Error: FILT must be uppercase"; exit 1; fi
# if [[ ! "$FILT" =~ ^[JHK]$ ]]; then echo "Error: FILT must be J/H/K"; exit 1; fi

if ! [[ "$NUM_EXPOSURES" =~ $re_int ]] || [ "$NUM_EXPOSURES" -le 0 ]; then echo "Error: NUM_EXPOSURES must be positive int"; exit 1; fi
if ! [[ "$HWP_CYCLES" =~ $re_int ]] || [ "$HWP_CYCLES" -le 0 ]; then echo "Error: HWP_CYCLES must be positive int"; exit 1; fi
if ! [[ "$TOL" =~ $re_num ]]; then echo "Error: TOL must be numeric"; exit 1; fi
if ! [[ "$POLL" =~ $re_num ]]; then echo "Error: POLL must be numeric"; exit 1; fi

absdiff() { awk -v a="$1" -v b="$2" 'BEGIN{d=a-b; if(d<0)d=-d; print d}'; }

apply_offset_to_angles() {
  local angles_str="$1" off="$2" out="" new
  for a in $angles_str; do
    new=$(awk -v x="$a" -v o="$off" 'BEGIN{printf "%.10g", x+o}')
    out+="$new "
  done
  printf '%s\n' "${out% }"
}

# case "$FILT" in
#   J) ANGLES=$(apply_offset_to_angles "$ANGLES" "$J_ADD") ;;
#   H) ANGLES=$(apply_offset_to_angles "$ANGLES" "$H_ADD") ;;
#   K) ANGLES=$(apply_offset_to_angles "$ANGLES" "$K_ADD") ;;
# esac

# read -r -p "Does this look correct? Press Enter to continue, or type anything to cancel: " resp
# if [[ -n "$resp" ]]; then echo "Aborting"; exit 1; fi

# ----------------------------------------------------------------------
# REACHABILITY CHECK — replace EPICS cainfo with KTL
# ----------------------------------------------------------------------

### KTL CHANGE:
if ! show -s pcu2 PCUPR >/dev/null 2>&1; then
  echo "KTL keyword not reachable: PCUPR"
  exit 1
fi

### KTL CHANGE:
show -s pcu2 PCURSTAT || true
show -s pcu2 PCUPR || true

# ----------------------------------------------------------------------
# Main loop
# ----------------------------------------------------------------------

for ((cycle=1; cycle<=HWP_CYCLES; cycle++)); do
  echo "==== Starting HWP cycle $cycle of $HWP_CYCLES ===="
  for ang in $ANGLES; do
    echo "---- Moving to HWP $ang deg ----"

    ### KTL CHANGE:
    if ! modify -s pcu2 PCUPR="$ang"; then
      echo "Error: modify failed ($ang deg)"
      exit 1
    fi

    # Poll for convergence
    while true; do
      pos=$(show -s pcu2 PCUPR 2>/dev/null | awk '{print $3+0}')\
        || { echo "Error: failed reading position"; break; }
      echo "HWP angle readback = $pos deg"
    
      err=$(absdiff "$pos" "$ang")
      if awk -v e="$err" -v tol="$TOL" 'BEGIN{exit !(e<=tol)}'; then
        break
      fi
      sleep "$POLL"
    done

    rfloat=$(printf "%.1f" "$ang")
    label="${OBJ}_hwp_${rfloat}_cyc_${cycle}"

    object "$label" || { echo "object failed ($label)"; break; }
    goi -s "$NUM_EXPOSURES" || { echo "goi failed ($label x$NUM_EXPOSURES)"; break; }
  done
done

echo "Final HWP rotator position:"
### KTL CHANGE:
show -s pcu2 PCUPR || echo "Error: Failed to read final rotator position."
