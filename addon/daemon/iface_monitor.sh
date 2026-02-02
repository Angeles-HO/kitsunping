#!/system/bin/sh
# Network interrogators: get_signal_quality

# Ensure network_utils.sh is sourced for shared functions
if [ -f "$MODDIR/addon/functions/network_utils.sh" ]; then
    . "$MODDIR/addon/functions/network_utils.sh"
fi
# get_signal_quality - Get mobile network signal quality and technology
# Returns JSON with fields:
# - technology: network technology (e.g., LTE, NR, WCDMA, GSM, unknown)
# - rsrp_dbm: RSRP in dBm (or - if unavailable)
# - rssi_dbm: RSSI in dBm (or - if unavailable)
# - sinr_db: SINR in dB (or - if unavailable)
# - asu: ASU value (or - if unavailable)
# - quality_score: 0-100 signal quality score
# - timestamp: Unix timestamp of measurement
get_signal_quality() {
    # Local vars
    local dump tech rsrp="" rssi="" asu="" sinr="" quality_score=0 ts
    local disp_network="" disp_override="" ril_data_tech="" reg_tech=""

    # time stamp
    ts=$(date +%s 2>/dev/null || echo 0)

    # Check dumpsys availability
    if ! command_exists dumpsys; then
        printf '{"error":"dumpsys not available","quality_score":0,"timestamp":%s}\n' "$ts"
        return 1
    fi

    # Get telephony registry dump (for signal strength info, no collective logs/data)
    dump=$(dumpsys telephony.registry 2>/dev/null)
    if [ -z "$dump" ]; then
        printf '{"error":"dumpsys empty","quality_score":0,"timestamp":%s}\n' "$ts"
        return 1
    fi

    # Prefer the phone block that currently has data connected (mDataConnectionState=2)
    local preferred_phone=""
    preferred_phone=$(printf '%s\n' "$dump" | awk '
        match($0,/Phone Id=([0-9]+)/,a){phone=a[1]}
        /mDataConnectionState=2/ {print phone; exit}
    ')

    # MTK/Qualcomm consolidated SignalStrength line (lte fields inline)
    local mtk_line
    mtk_line=$(printf '%s\n' "$dump" | awk -v target="$preferred_phone" '
        match($0,/Phone Id=([0-9]+)/,a){phone=a[1]}
        /mSignalStrength=SignalStrength/ {
            if (target=="" || phone==target) {print; exit}
        }
    ')
    [ -z "$mtk_line" ] && mtk_line=$(printf '%s\n' "$dump" | grep -m1 'mSignalStrength=SignalStrength')

    if [ -n "$mtk_line" ]; then
        rsrp=$(printf '%s\n' "$mtk_line" | awk -F'rsrp=' '{print $2}' | awk '{print $1}')
        rssi=$(printf '%s\n' "$mtk_line" | awk -F'rssi=' '{print $2}' | awk '{print $1}')
        sinr=$(printf '%s\n' "$mtk_line" | awk -F'rssnr=' '{print $2}' | awk '{print $1}')
    fi

    # Better detection (Qualcomm/MTK friendly)
    # In TelephonyDisplayInfo (often present in "local logs")
    # Example: TelephonyDisplayInfo {network=LTE, overrideNetwork=NR_NSA, ...}

    # so, here we extract:
    # Displayed network type
    # Example: network=LTE
    disp_network=$(printf '%s\n' "$dump" | awk '
        match($0,/TelephonyDisplayInfo \{network=([^,}]+),/,a){net=a[1]}
        END{if(net!="") print net}
    ' | tail -n 1)

    # Displayed override network type
    # Example: overrideNetwork=NR_NSA
    disp_override=$(printf '%s\n' "$dump" | awk '
        match($0,/overrideNetwork=([^,}]+)[,}]/,a){ov=a[1]}
        END{if(ov!="") print ov}
    ' | tail -n 1)

    # RIL data radio technology (present in ServiceState)
    # Example: getRilDataRadioTechnology=14(LTE)
    ril_data_tech=$(printf '%s\n' "$dump" | awk '
        match($0,/getRilDataRadioTechnology=[0-9]+\(([^)]+)\)/,a){t=a[1]}
        END{if(t!="") print t}
    ' | tail -n 1)

    # NetworkRegistrationInfo accessNetworkTechnology can be IWLAN/UNKNOWN as well.
    # Prefer WWAN (mobile data) tech, and ignore placeholders.
    # Example lines:
    #   transportType=WWAN ... accessNetworkTechnology=LTE
    #   transportType=WLAN ... accessNetworkTechnology=IWLAN
    reg_tech=$(printf '%s\n' "$dump" | awk '
        /transportType=WWAN/ && match($0,/accessNetworkTechnology=([A-Z0-9_]+)/,a) {
            t=a[1]
            if (t != "UNKNOWN" && t != "IWLAN") { print t; exit }
        }
        match($0,/accessNetworkTechnology=([A-Z0-9_]+)/,a) {
            t=a[1]
            if (t != "UNKNOWN" && t != "IWLAN") last=t
        }
        END{ if (last != "") print last }
    ' | tail -n 1)

    # Decide tech with priority:
    # - If overrideNetwork indicates NR (NR_NSA/NR_SA/NR_ADVANCED), expose NR.
    # - Else use display network if present.
    # - Else use RIL/reg tech.
    tech=""
    case "$disp_override" in
        NR*|*NR*) tech="NR" ;;
    esac
    if [ -z "$tech" ] && [ -n "$disp_network" ] && [ "$disp_network" != "UNKNOWN" ]; then
        tech="$disp_network"
    fi
    if [ -z "$tech" ] && [ -n "$ril_data_tech" ] && [ "$ril_data_tech" != "Unknown" ] && [ "$ril_data_tech" != "UNKNOWN" ]; then
        tech="$ril_data_tech"
    fi
    if [ -z "$tech" ] && [ -n "$reg_tech" ] && [ "$reg_tech" != "UNKNOWN" ] && [ "$reg_tech" != "IWLAN" ]; then
        tech="$reg_tech"
    fi

    # Back-compat: some builds expose mDataConnectionTech
    if [ -z "$tech" ]; then
        tech=$(printf '%s' "$dump" | grep -m1 "mDataConnectionTech" | awk -F'=' '{print $2}' | tr -d '[:space:]')
    fi

    # Normalize UNKNOWN to "unknown" for output consistency
    [ "$tech" = "UNKNOWN" ] && tech="unknown"

    case "$tech" in
        *LTE*|*NR*)
            if [ -z "$rsrp" ] || [ -z "$sinr" ]; then
                local signal_line
                signal_line=$(printf '%s' "$dump" | grep -m1 "mLteSignalStrength")
                if [ -n "$signal_line" ]; then
                    rsrp=$(echo "$signal_line" | awk '{print $(NF-2)}')
                    sinr=$(echo "$signal_line" | awk '{print $(NF-1)}')
                fi
            fi
            ;;
        *WCDMA*|*HSPAP*|*HSDPA*|*HSUPA*)
            if [ -z "$rssi" ]; then
                local signal_line
                signal_line=$(printf '%s' "$dump" | grep -m1 "mSignalStrength")
                if [ -n "$signal_line" ]; then
                    rssi=$(echo "$signal_line" | awk '{print $3}')
                    [ "$rssi" = "-1" ] && rssi=$(echo "$signal_line" | awk '{print $4}')
                fi
            fi
            ;;
        *GSM*|*EDGE*|*GPRS*)
            if [ -z "$rssi" ]; then
                local signal_line
                signal_line=$(printf '%s' "$dump" | grep -m1 "mSignalStrength")
                if [ -n "$signal_line" ]; then
                    asu=$(echo "$signal_line" | awk '{print $2}')
                    if echo "$asu" | grep -Eq '^[0-9]+$' && [ "$asu" -ne 99 ]; then
                        rssi=$(( -113 + (2 * asu) ))
                    fi
                fi
            fi
            ;;
    esac

    # Avoid guessing LTE: if we don't know, keep "unknown".
    # (Previously this forced LTE whenever rsrp/rssi existed, which can hide NR/UNKNOWN states.)

    if [ -n "$rsrp" ] && echo "$rsrp" | grep -Eq '^-?[0-9]+$' && [ "$rsrp" -ne -1 ] && [ "$rsrp" -ne 2147483647 ]; then
        if   [ "$rsrp" -ge -85 ];  then quality_score=100
        elif [ "$rsrp" -ge -95 ];  then quality_score=80
        elif [ "$rsrp" -ge -105 ]; then quality_score=60
        elif [ "$rsrp" -ge -115 ]; then quality_score=40
        else                            quality_score=20
        fi
    elif [ -n "$rssi" ] && echo "$rssi" | grep -Eq '^-?[0-9]+$' && [ "$rssi" -ne -1 ]; then
        if   [ "$rssi" -ge -70 ];  then quality_score=100
        elif [ "$rssi" -ge -85 ];  then quality_score=75
        elif [ "$rssi" -ge -100 ]; then quality_score=50
        elif [ "$rssi" -ge -110 ]; then quality_score=25
        else                             quality_score=10
        fi
    fi

    cat <<EOF
{
  "technology": "${tech:-unknown}",
  "rsrp_dbm": "${rsrp:--}",
  "rssi_dbm": "${rssi:--}",
  "sinr_db": "${sinr:--}",
  "asu": "${asu:--}",
  "quality_score": $quality_score,
  "timestamp": $ts
}
EOF
}
