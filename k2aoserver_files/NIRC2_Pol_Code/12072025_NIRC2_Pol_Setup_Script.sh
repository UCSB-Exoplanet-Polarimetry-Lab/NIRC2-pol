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
instrument="NIRES"
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

# ############################################
# # Adding script paths
# ############################################
user maxmb 
# TODO: Parse the print statement from adding the user path to make sure it's correctly added
echo "Adding polarimetric scripts from path /home/maxmb/pol_scripts"

# ############################################
# # Test HWP Rotation
# ############################################
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