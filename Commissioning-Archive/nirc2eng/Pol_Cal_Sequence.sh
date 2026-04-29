#!/usr/bin/env bash
# Script to move the NIRC2 HWP (PCU rotator) through a sequence of angles,
# as well as the image rotator (IMR) using KTL keywords accessible on
# waikoko-new and NIRC2
# Rebecca Zhang, Dec 03, 2025

# --- user inputs ---
OBJ="test_full_polarimetric_calibration"   # object base name (quotes OK if spaces)
ANGLES="0 10 20 30 40 50 60 70 80 90"                    # list of HWP angles (deg)
IMR_ANGLES="0 15 30 45 60 75 90 105 120 135 150"                         # list of IMR angles (deg)
TOL=0.05                                   # degrees tolerance for HWP
IMR_TOL=0.05                               # degrees tolerance for IMR
POLL=0.4                                   # seconds between queries
NUM_EXPOSURES=1                            # number of exposures per position
HWP_CYCLES=1                               # fixed number of HWP cycles (no user input)
# --------------------

# Test insertion

echo "--------------------------------------------------"
echo "NIRC2 HWP/IMR sequence starting with:"
echo "  OBJ          = $OBJ"
echo "  HWP ANGLES   = $ANGLES"
echo "  IMR ANGLES   = $IMR_ANGLES"
echo "  HWP TOL      = $TOL deg"
echo "  IMR TOL      = $IMR_TOL deg"
echo "  POLL         = $POLL s"
echo "  HWP CYCLES   = $HWP_CYCLES"
echo "  NUM_EXPOSURES (per HWP angle) = $NUM_EXPOSURES"
echo "--------------------------------------------------"
read -r -p "Does this look correct? Press Enter to continue, or type anything to cancel: " resp
[ -n "$resp" ] && echo "Aborting." && exit 1

# Show status of PCU rotator
echo -n "HWP status: "; show -s pcu2 PCURSTAT
echo -n "HWP angle:  "; show -s pcu2 PCUPR

# Loop over IMR angles
for imr_ang in $IMR_ANGLES; do
  echo "==== Moving IMR to $imr_ang deg ===="
  modify -s ao obrt="$imr_ang"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to set IMR position to $imr_ang degrees."
    exit 1
  fi

  # Poll IMR position every POLL seconds until within tolerance
  while true; do
    # Extract numeric angle from KTL output
    imr_pos=$(show -s ao obrt 2>/dev/null | awk '{print $3+0}')
    if [ $? -ne 0 ] || [ -z "$imr_pos" ]; then
      echo "Error: Failed to read IMR position."
      exit 1
    fi
    echo "IMR angle readback = $imr_pos deg"

    imr_err=$(awk -v p="$imr_pos" -v t="$imr_ang" 'BEGIN{d=p-t; if(d<0)d=-d; print d}')
    if awk -v e="$imr_err" -v tol="$IMR_TOL" 'BEGIN{exit !(e<=tol)}'; then
      break
    fi
    sleep "$POLL"
  done

  # For each IMR angle, run HWP cycles (fixed HWP_CYCLES)
  for ((cycle=1; cycle<=HWP_CYCLES; cycle++)); do
    echo "==== Starting HWP cycle $cycle of $HWP_CYCLES at IMR $imr_ang deg ===="
    for ang in $ANGLES; do
      echo "---- Moving to HWP $ang deg ----"
      modify -s pcu2 PCUPR="$ang"
      if [ $? -ne 0 ]; then
        echo "Error: Failed to set HWP position to $ang degrees."
        exit 1
      fi

      # Poll HWP location, print position each time, stop when within tolerance
      while true; do
        # Extract numeric angle from KTL output
        pos=$(show -s pcu2 PCUPR 2>/dev/null | awk '{print $3+0}')
        if [ $? -ne 0 ] || [ -z "$pos" ]; then
          echo "Error: Failed to read HWP position."
          exit 1
        fi
        echo "HWP angle readback = $pos deg"

        err=$(awk -v p="$pos" -v t="$ang" 'BEGIN{d=p-t; if(d<0)d=-d; print d}')
        if awk -v e="$err" -v tol="$TOL" 'BEGIN{exit !(e<=tol)}'; then
          break
        fi
        sleep "$POLL"
      done

      rfloat=$(printf "%.1f" "$ang")
      imrfloat=$(printf "%.1f" "$imr_ang")
      object "${OBJ}_imr_${imrfloat}_hwp_${rfloat}"
      goi -s "$NUM_EXPOSURES"
    done
  done
done

# Final readback
echo "Final HWP rotator position:"
show -s pcu2 PCUPR
if [ $? -ne 0 ]; then
  echo "Error: Failed to read final rotator position."
fi
