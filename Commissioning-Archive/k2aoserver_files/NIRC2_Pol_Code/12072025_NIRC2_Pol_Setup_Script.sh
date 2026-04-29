# Prompt user for program name
read -p "Please enter your program name: " program_name
echo "Program name entered: $program_name"

cat <<EOF
WARNING: You must have checked with the SA that it's ok to run "configAOforFlats" if running this in the afternoon.
Please disregard if you are taking morning dome flats.
Press ENTER to continue:
EOF

read

############################################
# Check selected instrument
############################################
# TODO: Change this back to NIRC2 once done testing
instrument="NIRC2"
val=$(show -s dcs instrume | awk '{print $3}')

if [ "$val" = "$instrument" ]; then
    echo "CHECK: Instrument selected is $instrument"
else
    echo "EXITING: Instrument selected is not $instrument"
    exit 1
fi


############################################
# AO HATCH
############################################
# Check if AO hatch is already open
val=$(show -s ao ifaostat | awk '{print $3}')

if [ "$val" = "open" ]; then
    echo "CHECK: AO hatch is open"
else
    echo "AO hatch is closed — opening..."
    aohatch open
    sleep 1  # optional, depending on EPICS latency

    # Re-check state
    val=$(show -s ao ifaostat | awk '{print $3}')
    if [ "$val" = "open" ]; then
        echo "CHECK: AO hatch is now open"
    else
        echo "EXITING: AO hatch did not open"
        exit 1
    fi
fi

############################################
# NIRC2 SHUTTER
############################################
# Check if shutter is already open
val=$(show -s nirc2 shrname | awk '{print $3}')

if [ "$val" = "open" ]; then
    echo "CHECK: NIRC2 shutter is open"
else
    echo "NIRC2 shutter is closed — opening..."
    shutter open
    sleep 1  # optional

    # Re-check state
    val=$(show -s nirc2 shrname | awk '{print $3}')
    if [ "$val" = "open" ]; then
        echo "CHECK: NIRC2 shutter is now open"
    else
        echo "EXITING: NIRC2 shutter did not open"
        exit 1
    fi
fi

############################################
# configAOforFlats
############################################
configAOforFlats

# Extra checks for the ISM and DFB that are not necessary
# ############################################
# # ISM
# ############################################
# # Check to make sure the ISM is out of the way
# val=$(show -s ao obimname | awk '{print $3}')
# if [ "$val" = "out" ]; then
#     echo "CHECK: ISM is out of the way"
# else
#     modify -s ao obimname="out"

#     # Re-check state
#     val=$(show -s ao obimname | awk '{print $3}')
#     if [ "$val" = "out" ]; then
#         echo "CHECK: ISM is now out of the way"
#     else
#         echo "EXITING: ISM is not out of the way"
#         exit 1
#     fi
# fi

# ############################################
# # DFB
# ############################################
# # Check to make sure the DFB is out of the way
# val=$(show -s ao obdbname | awk '{print $3}')
# if [ "$val" = "out" ]; then
#     echo "CHECK: DFB is out of the way"
# else
#     modify -s ao obdbname="out"
#     # Re-check state
#     val=$(show -s ao obdbname | awk '{print $3}')
#     if [ "$val" = "out" ]; then
#         echo "CHECK: DFB is now out of the way"
#     else
#         echo "EXITING: DFB is not out of the way"
#         exit 1
#     fi
# fi

# TODO: Need to find a way to test whether the progname is set properly
# ############################################
# # Program Name
# ############################################
# TODO: Not sure whether this works and need to check with FITS files generated with this method
modify -s nirc2plus PROGNAME="$program_name"
val=$(show -s nirc2plus PROGNAME | awk '{print $3}')
if [ "$val" = "$program_name" ]; then
    echo "CHECK: NIRC2 program name is set to $program_name"
else
    echo "EXITING: NIRC2 program name is not set correctly"
    exit 1
fi

############################################
# Test HWP Rotation (relative +1 degree)
############################################

# Setting HWP test variables
TEST_DELTA=1.0
TEST_TOL=0.01
TEST_TIMEOUT=30   # seconds
POLL=0.5 # seconds

echo "---- Testing HWP rotation: reading current PCUPR ----"

# Read current HWP angle
CUR_ANG=$(show -s pcu2 PCUPR 2>/dev/null | awk '{print $3+0}')

if [[ -z "$CUR_ANG" ]]; then
    echo "EXITING: Failed to read current HWP angle (PCUPR empty)"
    exit 1
fi

# Sanity check numeric
if ! awk -v x="$CUR_ANG" 'BEGIN{exit !(x==x)}'; then
    echo "EXITING: Current HWP angle is not numeric: '$CUR_ANG'"
    exit 1
fi

TARGET_ANG=$(awk -v a="$CUR_ANG" -v d="$TEST_DELTA" 'BEGIN{printf "%.6f", a+d}')

echo "Current HWP angle = $CUR_ANG deg"
echo "Commanding HWP to  = $TARGET_ANG deg"

# Command the move
if ! modify -s pcu2 PCUPR="$TARGET_ANG"; then
    echo "EXITING: Failed to command HWP to $TARGET_ANG deg"
    exit 1
fi

# Poll for convergence
start_ts=$(date +%s)

while true; do
    pos=$(show -s pcu2 PCUPR 2>/dev/null | awk '{print $3+0}')

    if [[ -z "$pos" ]]; then
        echo "EXITING: Failed to read HWP position during test move"
        exit 1
    fi

    err=$(awk -v p="$pos" -v t="$TARGET_ANG" 'BEGIN{d=p-t; if(d<0)d=-d; print d}')

    if awk -v e="$err" -v tol="$TEST_TOL" 'BEGIN{exit !(e<=tol)}'; then
        echo "CHECK: HWP moved successfully"
        echo "       Target = $TARGET_ANG deg"
        echo "       Readback = $pos deg (|diff|=$err ≤ $TEST_TOL)"
        break
    fi

    now_ts=$(date +%s)
    elapsed=$((now_ts - start_ts))
    if [ "$elapsed" -ge "$TEST_TIMEOUT" ]; then
        echo "EXITING: HWP did not reach $TARGET_ANG deg within $TEST_TIMEOUT s"
        echo "         Last readback = $pos deg (|diff|=$err)"
        exit 1
    fi

    sleep "$POLL"
done

############################################
# Launch xshow monitor for NIRC2 pol keywords
############################################

if command -v xterm >/dev/null 2>&1; then
    xterm -title "NIRC2 Pol KTL Monitor" \
          -e "xshow -s ao pcupr obrt pcuname -s nirc2 slmname" &
    echo "CHECK: xshow running for NIRC2 pol KTL keywords"
else
    echo "WARNING: xterm not found — cannot launch xshow window"
fi

# TODO: Test the PCU move with poll time and timeout
############################################
# PCU: move to HWP center position (NIRC2)
############################################

PCUNAME="hwp_center"
PCU_TIMEOUT=120        # seconds
PCU_POLL=0.5           # seconds

echo "Setting PCU to HWP center position (timeout=${PCU_TIMEOUT}s)..."

# Command the PCU once
if ! modify -s pcu2 PCUNAME="$PCUNAME"; then
    echo "EXITING: Failed to command PCU to $PCUNAME"
    exit 1
fi

start_time=$(date +%s)

while true; do
    # Read back via NIRC2
    pcu_pos=$(show -s nirc2 pcuname 2>/dev/null | awk '{print $3}')

    if [[ "$pcu_pos" = "$PCUNAME" ]]; then
        echo "CHECK: PCU is in HWP center position (pcuname=$pcu_pos)"
        break
    fi

    now=$(date +%s)
    elapsed=$(( now - start_time ))

    if (( elapsed >= PCU_TIMEOUT )); then
        echo "EXITING: PCU did not reach $PCU_TARGET within ${$PCU_TIMEOUT}s"
        echo "         Last readback: pcuname='$pcu_pos'"
        exit 1
    fi

    sleep "$PCU_POLL"
done


