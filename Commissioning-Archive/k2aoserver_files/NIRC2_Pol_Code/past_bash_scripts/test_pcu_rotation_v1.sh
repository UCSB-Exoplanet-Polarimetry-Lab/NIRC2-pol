#!/usr/bin/env bash
# hwp_rot_seq.sh — HWP (PCU rotator) movement with NIRC2 images

# Point Channel Access at your IOC (non-standard port 8606)
# export EPICS_CA_AUTO_ADDR_LIST=NO
# export EPICS_CA_ADDR_LIST=127.0.0.1:8606
# Only run this after making sure the k1_pcu.scr file is running in a separate screen
# export EPICS_CA_ADDR_LIST=localhost:860

# --- user inputs ---
OBJ="test_pcu_rotation_v1"                  # object base name (quotes OK if spaces)
ANGLES="0 22.5 45 67.5"       # list of HWP angles (deg)
TOL=0.05                         # degrees tolerance
POLL=0.1                         # seconds between queries
# --------------------

# Quick reachability check (simple if) - NOT TESTED
if ! cainfo -w 2 k2:ao:pcu:rot:posvalRb >/dev/null 2>&1; then
 echo "PV not reachable: k2:ao:pcu:rot:posvalRb"; exit 1
fi

# Show status, home once
caget -S k2:ao:pcu:rot:statRb ;
caget k2:ao:pcu:rot:posvalRb
# Currently haven’t figured out how to home
# caput k2:ao:pcu:rot:home 1; 

# Loop over angles
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
  rint=$(printf "%.0f" "$ang")
  ssh nirc2eng@waikoko-new object "${OBJ}_hwp_${rint}"
  ssh nirc2eng@waikoko-new goi
done

# Final readback
echo "Final HWP rotator position:"
caget k2:ao:pcu:rot:posvalRb
if [ $? -ne 0 ]; then
  echo "Error: Failed to read final rotator position."
fi
