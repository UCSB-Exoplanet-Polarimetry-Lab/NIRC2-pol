#!/usr/bin/env bash
# hwp_rot_seq.sh — HWP (PCU rotator) movement with NIRC2 images

# Point Channel Access at your IOC (non-standard port 8606)
# export EPICS_CA_AUTO_ADDR_LIST=NO
# export EPICS_CA_ADDR_LIST=127.0.0.1:8606
# Only run this after making sure the k1_pcu.scr file is running in a separate screen
# export EPICS_CA_ADDR_LIST=localhost:860



# --- user inputs ---
OBJ="pol_cal_imr_hwp_h"                  # object base name (quotes OK if spaces)
ANGLES="0 10 20 30 40 50 60 70 80 90"       # list of HWP angles (deg)
IMR_ANGLES="0 15 30 45 60 75 90 105 120 135 150"      # list of IMR angles (deg) - user can edit
TOL=0.05                         # degrees tolerance for HWP
IMR_TOL=0.05                      # degrees tolerance for IMR
POLL=0.1                         # seconds between queries
# --------------------

# --- allow terminal call to this script to allow for multiple HWP cycles ---
if [ $# -lt 1 ]; then
  echo "Usage: $0 <num_cycles>"
  echo "Example: $0 3"
  exit 1
fi
NUM_CYCLES=$1
if ! [[ "$NUM_CYCLES" =~ ^[0-9]+$ ]]; then
  echo "Error: num_cycles must be a positive integer."
  exit 1
fi

# Quick reachability check (simple if) - NOT TESTED
if ! cainfo -w 2 k2:ao:pcu:rot:posvalRb >/dev/null 2>&1; then
 echo "PV not reachable: k2:ao:pcu:rot:posvalRb"; exit 1
fi

# Show status, home once
caget -S k2:ao:pcu:rot:statRb ;
caget k2:ao:pcu:rot:posvalRb
# Currently haven’t figured out how to home
# caput k2:ao:pcu:rot:home 1; 

# Loop over IMR angles
for imr_ang in $IMR_ANGLES; do
  echo "==== Moving IMR to $imr_ang deg ===="
  caput k2:ao:ob:rot:goLocUu "$imr_ang"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to set IMR position to $imr_ang degrees."
    continue
  fi
  # Poll IMR position every 0.1s until within tolerance
  while true; do
    imr_pos=$(caget -t k2:ao:ob:rot:actPosLocUu 2>/dev/null)
    if [ $? -ne 0 ]; then
      echo "Error: Failed to read IMR position."
      break
    fi
    echo "IMR Angle =$imr_pos"
    imr_err=$(awk -v p="$imr_pos" -v t="$imr_ang" 'BEGIN{d=p-t; if(d<0)d=-d; print d}')
    if awk -v e="$imr_err" -v tol="$IMR_TOL" 'BEGIN{exit !(e<=tol)}'; then
      break
    fi
    sleep "$POLL"
  done

  # For each IMR angle, run HWP cycles
  for ((cycle=1; cycle<=NUM_CYCLES; cycle++)); do
    echo "==== Starting HWP cycle $cycle of $NUM_CYCLES at IMR $imr_ang deg ===="
    for ang in $ANGLES; do
      echo "---- Moving to HWP $ang deg ----"
      caput k2:ao:pcu:rot:posval "$ang"
      if [ $? -ne 0 ]; then
        echo "Error: Failed to set rotator position to $ang degrees."
        continue
      fi
      # Poll location every 0.1 s, print position each time, stop when within readback tolerance error
      while true; do
        pos=$(caget -t k2:ao:pcu:rot:posvalRb 2>/dev/null)
        if [ $? -ne 0 ]; then
          echo "Error: Failed to read rotator position."
          break
        fi
        echo "HWP rotator posvalRb=$pos"
        err=$(awk -v p="$pos" -v t="$ang" 'BEGIN{d=p-t; if(d<0)d=-d; print d}')
        if awk -v e="$err" -v tol="$TOL" 'BEGIN{exit !(e<=tol)}'; then
          break
        fi
        sleep "$POLL"
      done
  rfloat=$(printf "%.1f" "$ang")
  imrfloat=$(printf "%.1f" "$imr_ang")
  ssh nirc2eng@waikoko-new object "${OBJ}_imr_${imrfloat}_hwp_${rfloat}"
  ssh nirc2eng@waikoko-new goi
    done
  done
done

# Final readback
echo "Final HWP rotator position:"
caget k2:ao:pcu:rot:posvalRb
if [ $? -ne 0 ]; then
  echo "Error: Failed to read final rotator position."
fi
