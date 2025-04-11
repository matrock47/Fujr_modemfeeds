#!/bin/sh

source /usr/share/qmodem/generic.sh
debug_subject="quectel_ctrl"

function get_imei(){
    imei=$(at $at_port "ATI" | awk -F': ' '/^IMEI:/ {print $2}' | xargs)
    json_add_string imei $imei
}

function set_imei(){
    imei=$1
    extended="80A$imei"  # 添加 80A 前缀
    formatted=""
    i=0
    while [ $i -lt ${#extended} ]; do
        byte=$(echo "$extended" | cut -c$((i+1))-$((i+2)))  # 获取两个字符
        formatted="$formatted$byte,"
        i=$((i+2))
    done

    # 去除最后的逗号
    formatted=$(echo ${formatted%,}|xargs)
    #echo "$formatted"

    at_command="at^nv=550,9,$formatted"
    res=$(at $at_port \"$at_command\")
    json_select "result"
    json_add_string "set_imei" "$res"
    json_close_object
    get_imei
}

function get_mode(){
    cfg=$(at $at_port "AT^PCIEMODE?")
    config_type=`echo -e "$cfg" | grep -o '[0-9]'`
    if [ "$config_type" = "1" ]; then
        mode="mbim"
    fi
    available_modes=$(uci -q get qmodem.$config_section.modes)
    json_add_object "mode"
    for available_mode in $available_modes; do
        if [ "$mode" = "$available_mode" ]; then
            json_add_string "$available_mode" "1"
        else
            json_add_string "$available_mode" "0"
        fi
    done
    json_close_object
}


function get_network_prefer(){
    res=$(at $at_port "AT^SLMODE?"| grep -o '[0-9]\+' | tr -d '\n' | tr -d ' ')
# (RAT index): 
# 0 Automatically 
# 1 WCDMA Only
# 2 LTE Only 
# 3 WCDMA And LTE 
# 4 NR5G Only 
# 5 WCDMA And NR5G 
# 6 LTE And NR5G 
# 7 WCDMA And LTE And NR5G
    local network_prefer_3g="0"
    local network_prefer_4g="0"
    local network_prefer_5g="0"
   case $res in
        "10")
            network_prefer_3g="1"
            network_prefer_4g="1"
            network_prefer_5g="1"
            ;;
        "11")
            network_prefer_3g="1"
            ;;
        "12")
            network_prefer_4g="1"
            ;;
        "13")
            network_prefer_3g="1"
            network_prefer_4g="1"
            ;;
        "14")
            network_prefer_5g="1"
            ;;
        "15")
            network_prefer_3g="1"
            network_prefer_5g="1"
            ;;
        "16")
            network_prefer_4g="1"
            network_prefer_5g="1"
            ;;
        "17")
            network_prefer_3g="1"
            network_prefer_4g="1"
            network_prefer_5g="1"
            ;;
        *)
            network_prefer_3g="0"
            network_prefer_4g="0"
            network_prefer_5g="0"
            ;;
    esac
    json_add_object network_prefer
    json_add_string 3G $network_prefer_3g
    json_add_string 4G $network_prefer_4g
    json_add_string 5G $network_prefer_5g
    json_close_array
}

function set_network_prefer(){
    local network_prefer_3g=$(echo $1 |jq -r 'contains(["3G"])')
    local network_prefer_4g=$(echo $1 |jq -r 'contains(["4G"])')
    local network_prefer_5g=$(echo $1 |jq -r 'contains(["5G"])')
    count=$(echo $1 | jq -r 'length')
    case "$count" in
        "1")
            if [ "$network_prefer_3g" = "true" ]; then
                code="11"
            elif [ "$network_prefer_4g" = "true" ]; then
                code="12"
            elif [ "$network_prefer_5g" = "true" ]; then
                code="14"
            fi
            ;;
        "2")
            if [ "$network_prefer_3g" = "true" ] && [ "$network_prefer_4g" = "true" ]; then
                code="13"
            elif [ "$network_prefer_4g" = "true" ] && [ "$network_prefer_5g" = "true" ]; then
                code="16"
            elif [ "$network_prefer_3g" = "true" ] && [ "$network_prefer_5g" = "true" ]; then
                code="15"
            fi
            ;;
        "3")
            code="17"
            ;;
        *)
            code="10"
            ;;
    esac
    res=$(at $at_port "AT^SLMODE=$(echo "$code" | awk '{print substr($0,1,1) "," substr($0,2,1)}')")
    json_add_string "code" "$code"
    json_add_string "result" "$res"
}



function get_lockband(){
    json_add_object "lockband"
    case $platform in
        "qualcomm")
            get_lockband_nr
            ;;
    esac
    json_close_object
}

function sim_info()
{
    class="SIM Information"

    #IMEI（国际移动设备识别码）
    imei=$(at $at_port "ATI" | awk -F': ' '/^IMEI:/ {print $2}' | xargs)
    
    at_command="at^switch_slot?"
    sim_slot=$(at $at_port $at_command | grep ENABLE|grep -o 'SIM[0-9]*')

    #SIM Status（SIM状态）
    at_command="AT+CPIN?"
	sim_status=$(at $at_port $at_command | grep "+CPIN:")
    sim_status=${sim_status:7:-1}
    #lowercase
    sim_status=$(echo $sim_status | tr  A-Z a-z)

    if [ "$sim_status" != "ready" ]; then
        return
    fi
    
    at_command="AT+COPS?"
    isp=$(at $at_port $at_command | sed -n '2p' | awk -F'"' '{print $2}')
    if [ "$isp" = "CHN-CMCC" ] || [ "$isp" = "CMCC" ]|| [ "$isp" = "46000" ]; then
         isp="中国移动"
    # # elif [ "$isp" = "CHN-UNICOM" ] || [ "$isp" = "UNICOM" ] || [ "$isp" = "46001" ]; then
    elif [ "$isp" = "CHN-UNICOM" ] || [ "$isp" = "CUCC" ] || [ "$isp" = "46001" ]; then
         isp="中国联通"
    elif [ "$isp" = "CHN-CT" ] || [ "$isp" = "CT" ] || [ "$isp" = "46011" ]; then
    # elif [ "$isp" = "CHN-TELECOM" ] || [ "$isp" = "CTCC" ] || [ "$isp" = "46011" ]; then
         isp="中国电信"
    fi

    at_command="AT+CNUM"
	sim_number=$(at $at_port $at_command | awk -F'"' '{print $2}'|xargs)

    #IMSI（国际移动用户识别码）
    at_command="AT+CIMI"
	imsi=$(at $at_port $at_command | sed -n '2p' | sed 's/\r//g')

    #ICCID（集成电路卡识别码）
    at_command="AT+ICCID"
	iccid=$(at $at_port $at_command | sed -n '2p' | sed 's/\r//g'|sed 's/[^0-9]*//g')
    case "$sim_status" in
        "ready")
            add_plain_info_entry "SIM Status" "$sim_status" "SIM Status" 
            add_plain_info_entry "ISP" "$isp" "Internet Service Provider"
            add_plain_info_entry "SIM Slot" "$sim_slot" "SIM Slot"
            add_plain_info_entry "SIM Number" "$sim_number" "SIM Number"
            add_plain_info_entry "IMEI" "$imei" "International Mobile Equipment Identity" 
            add_plain_info_entry "IMSI" "$imsi" "International Mobile Subscriber Identity" 
            add_plain_info_entry "ICCID" "$iccid" "Integrate Circuit Card Identity" 
        ;;
        "miss")
            add_plain_info_entry "SIM Status" "$sim_status" "SIM Status" 
            add_plain_info_entry "IMEI" "$imei" "International Mobile Equipment Identity" 
        ;;
        "unknown")
            add_plain_info_entry "SIM Status" "$sim_status" "SIM Status" 
        ;;
        *)
            add_plain_info_entry "SIM Status" "$sim_status" "SIM Status" 
            add_plain_info_entry "SIM Slot" "$sim_slot" "SIM Slot" 
            add_plain_info_entry "IMEI" "$imei" "International Mobile Equipment Identity" 
            add_plain_info_entry "IMSI" "$imsi" "International Mobile Subscriber Identity" 
            add_plain_info_entry "ICCID" "$iccid" "Integrate Circuit Card Identity" 
        ;;
    esac
}

function base_info(){
        #Name（名称）
    at_command="ATI"
    baseinfos=$(at $at_port $at_command)
    name=$(echo "$baseinfos"| awk -F': ' '/^Manufacturer:/ {print $2}' |xargs)
    #Manufacturer（制造商）
    manufacturer=$(echo "$baseinfos"|awk -F': ' '/^Manufacturer:/ {print $2}' |xargs)
    #Revision（固件版本）
    revision=$(echo "$baseinfos"|awk -F': ' '/^Revision:/ {print $2}' | xargs)
    class="Base Information"
    add_plain_info_entry "manufacturer" "$manufacturer" "Manufacturer"
    add_plain_info_entry "revision" "$revision" "Revision"
    add_plain_info_entry "at_port" "$at_port" "AT Port"
    get_connect_status
    _get_temperature
    _get_voltage
}

function network_info() {
    class="Network Information"
    [ -z "$network_type" ] && {
        at_command='AT+COPS?'
        local rat_num=$(at ${at_port} ${at_command} | grep "+COPS:" | awk -F',' '{print $4}' | sed 's/\r//g')
        network_type=$(get_rat ${rat_num})
    }
    #at_command='AT^debug?'
    #response=$(at $at_port $at_command)
    #lte_sinr=$(echo "$response"|awk -F'lte_snr:' '{print $2}'|awk '{print $1}|xargs)
    add_plain_info_entry "Network Type" "$network_type" "Network Type"
}

function vendor_get_disabled_features(){
    #json_add_string "" "IMEI"
    json_add_string "" "NeighborCell"
}

get_lockband_nr()
{
    #local at_port="$1"
    m_debug  "Quectel sdx55 get lockband info"
    wcdma_avalible_band="1,2,3,4,5,6,7,8,9,19"
    lte_avalible_band="1,2,3,4,5,7,8,12,13,14,17,18,19,20,25,26,28,29,30,32,34,38,39,40,41,42,66,71"
    sa_nr_avalible_band="1,2,3,5,7,8,12,20,25,28,38,40,41,48,66,71,77,78,79"
    bands_command="AT^BAND_PREF?"
    get_lockbans=$(at $at_port $bands_command)
    gw_band=$(echo "$get_lockbans" | grep "WCDMA,Enable Bands" | cut -d':' -f2 | tr -d ' '|tr ',' ' '|xargs)
    lte_band=$(echo "$get_lockbans" | grep "LTE,Enable Bands" | cut -d':' -f2 | tr -d ' '|tr ',' ' ')
    sa_nr_band=$(echo "$get_lockbans" | grep "NR5G,Enable Bands" | cut -d':' -f2 | tr -d ' '|tr ',' ' ')
    json_add_object "UMTS"
    json_add_array "available_band"
    json_close_array
    json_add_array "lock_band"
    json_close_object
    json_close_object
    json_add_object "LTE"
    json_add_array "available_band"
    json_close_array
    json_add_array "lock_band"
    json_close_array
    json_close_object
    json_add_object "NR"
    json_add_array "available_band"
    json_close_array
    json_add_array "lock_band"
    json_close_array
    json_close_object

    for i in $(echo "$wcdma_avalible_band" | awk -F"," '{for(j=1; j<=NF; j++) print $j}'); do
        json_select "UMTS"
        json_select "available_band"
        add_avalible_band_entry  "$i" "UMTS_$i"
        json_select ..
        json_select ..
    done
    for i in $(echo "$lte_avalible_band" | awk -F"," '{for(j=1; j<=NF; j++) print $j}'); do
        json_select "LTE"
        json_select "available_band"
        add_avalible_band_entry  "$i" "LTE_B$i"
        json_select ..
        json_select ..
    done
    for i in $(echo "$sa_nr_avalible_band" | awk -F"," '{for(j=1; j<=NF; j++) print $j}'); do
        json_select "NR"
        json_select "available_band"
        add_avalible_band_entry  "$i" "NR_N$i"
        json_select ..
        json_select ..
    done
    #+QNWPREFCFG: "nr5g_band",1:3:7:20:28:40:41:71:77:78:79
    for i in $(echo "$gw_band"); do
        if [ -n "$i" ]; then
            json_select "UMTS"
            json_select "lock_band"
            json_add_string "" "$i"
            json_select ..
            json_select ..
        fi
    done
    for i in $(echo "$lte_band" | cut -d, -f2|tr -d '\r' | awk -F":" '{for(j=1; j<=NF; j++) print $j}'); do
        if [ -n "$i" ]; then
            json_select "LTE"
            json_select "lock_band"
            json_add_string "" "$i"
            json_select ..
            json_select ..
        fi
    done
    for i in $(echo "$sa_nr_band" | cut -d, -f2|tr -d '\r' | awk -F":" '{for(j=1; j<=NF; j++) print $j}'); do
        if [ -n "$i" ]; then
            json_select "NR"
            json_select "lock_band"
            json_add_string "" "$i"
            json_select ..
            json_select ..
        fi
    done
    json_close_array
}

set_lockband_nr(){
    #lock_band=$(echo $lock_band | tr ',' ':')
    case "$band_class" in
        "UMTS") 
	    lock_band=$(echo $lock_band)
            at_command="AT^BAND_PREF=WCDMA,2,$lock_band"
            res=$(at $at_port $at_command)
            ;;
        "LTE") 
            at_command="AT^BAND_PREF=LTE,2,$lock_band"
            res=$(at $at_port $at_command)
            ;;
        "NR")
            at_command="AT^BAND_PREF=NR5G,2,$lock_band"
            res=$(at $at_port $at_command)
            ;;
    esac
}

set_lockband()
{
    m_debug  "quectel set lockband info"
    config=$1
    #{"band_class":"NR","lock_band":"41,78,79"}
    band_class=$(echo $config | jq -r '.band_class')
    lock_band=$(echo $config | jq -r '.lock_band')
    case "$platform" in
        *)
            set_lockband_nr
        ;;
    esac
    json_select "result"
    json_add_string "set_lockband" "$res"
    json_add_string "config" "$config"
    json_add_string "band_class" "$band_class"
    json_add_string "lock_band" "$lock_band"
    json_close_object
}

function _get_voltage(){
    voltage=$(at $at_port "AT!PCVOLT?" | grep -o 'Power supply voltage: [0-9]* mV'|grep -o '[0-9]*' )
    [ -n "$voltage" ] && {
        add_plain_info_entry "voltage" "$voltage mV" "Voltage" 
    }
}

function _get_temperature(){
    temperature=$(at $at_port "at^temp?" | sed -n 's/.*TSENS: \([0-9]*\)C.*/\1/p' )
    [ -n "$temperature" ] && {
        add_plain_info_entry "temperature" "$temperature C" "Temperature" 
    }
}

function _add_avalible_band(){
    add_avalible_band_entry $1 $1
}

function _add_lock_band(){
    json_add_string "" $1
}

function _mask_to_band()
{
    func=$1
    low_band=$2
    high_band=$3
    low_band=$(echo "obase=2; ibase=16; $low_band" | bc)
    low_band=$(printf "%064s" $low_band)
    for i in $(seq 1 64); do
        if [ "${low_band: -$i:1}" = "1" ]; then
            band=$i
            $func $band
        fi
    done
    [ -z "$high_band" ] && return
    high_band=$(echo "obase=2; ibase=16; $high_band" | bc)
    high_band=$(printf "%064s" $high_band)
    for i in $(seq 1 64); do
        if [ "${high_band: -$i:1}" = "1" ]; then
            band=$((64+i))
            $func $band
        fi
    done

}

function _band_list_to_mask()
{
    local band_list=$1
    local low=0
    local high=0
    #以逗号分隔
    IFS=","
    for band in $band_list;do
        if [ "$band" -le 64 ]; then
            #使用bc计算2的band次方
            res=$(echo "2^($band-1)" | bc)
            low=$(echo "$low+$res" | bc)

        else
            tmp_band=$((band-64))
            res=$(echo "2^($tmp_band-1)" | bc)
            high=$(echo "$high+$res" | bc)
        fi
    done
    #十六进制输出，padding到16位
    low=$(printf "%016x" $low)
    high=$(printf "%016x" $high)
    echo "$low,$high"
}

cell_info(){
    class="Cell Information"
    at_command='AT^debug?'
    response=$(at $at_port $at_command)
    network_mode=$(echo "$response"|awk -F'RAT:' '{print $2}'|xargs)
    #add_plain_info_entry "network_mode" "$network_mode" "Network Mode"


    case $network_mode in
    "LTE")
    	lte_mcc=$(echo "$response"|awk -F'mcc:' '{print $2}'|awk -F',' '{print $1}'|xargs)
    	lte_mnc=$(echo "$response"|awk -F'mnc:' '{print $2}'|xargs)
    	lte_earfcn=$(echo "$response"|awk -F'channel:' '{print $2}'|awk -F' ' '{print $1}'|xargs)
    	lte_physical_cell_id=$(echo "$response"|awk -F'pci:' '{print $2}'|awk -F' ' '{print $1}'|xargs)
    	lte_cell_id=$(echo "$response"|awk -F'lte_cell_id:' '{print $2}'|xargs)
    	lte_band=$(echo "$response"|awk -F'lte_band:' '{print $2}'|awk -F' ' '{print $1}'|xargs)
    	lte_freq_band_ind=$(echo "$response"|awk -F'lte_band_width:' '{print $2}'|xargs)
    	lte_sinr=$(echo "$response"|awk -F'lte_snr:' '{print $2}'|awk '{print $1}'|sed -n 's/[^0-9.-]*\([+-]*[0-9]*\.[0-9]*\)[^0-9.-]*/\1/p'|xargs)
    	lte_rsrq=$(echo "$response"|awk -F'rsrq:' '{print $2}'|sed -n 's/[^0-9.-]*\([+-]*[0-9]*\.[0-9]*\)[^0-9.-]*/\1/p'|xargs)
    	lte_rssi=$(echo "$response"|awk -F'lte_rssi:' '{print $2}'|awk -F',' '{print $1}'|sed -n 's/[^0-9.-]*\([+-]*[0-9]*\.[0-9]*\)[^0-9.-]*/\1/p'|xargs)
    	#lte_rssnr=$(echo "$response"|
    	lte_tac=$(echo "$response"|awk -F'lte_tac:' '{print $2}'|xargs)
    	lte_tx_power=$(echo "$response"|awk -F'lte_tx_pwr:' '{print $2}'|xargs)

        add_plain_info_entry "MCC" "$lte_mcc" "Mobile Country Code"
        add_plain_info_entry "MNC" "$lte_mnc" "Mobile Network Code"
        #add_plain_info_entry "Duplex Mode" "$lte_duplex_mode" "Duplex Mode"
        add_plain_info_entry "Cell ID" "$lte_cell_id" "Cell ID"
        add_plain_info_entry "Physical Cell ID" "$lte_physical_cell_id" "Physical Cell ID"
        add_plain_info_entry "EARFCN" "$lte_earfcn" "E-UTRA Absolute Radio Frequency Channel Number"
        add_plain_info_entry "Freq band indicator" "$lte_freq_band_ind" "Freq band indicator"
        add_plain_info_entry "Band" "$lte_band" "Band"
        #add_plain_info_entry "UL Bandwidth" "$lte_ul_bandwidth" "UL Bandwidth"
        #add_plain_info_entry "DL Bandwidth" "$lte_dl_bandwidth" "DL Bandwidth"
        add_plain_info_entry "TAC" "$lte_tac" "Tracking area code of cell served by neighbor Enb"
        add_bar_info_entry "RSRQ" "$lte_rsrq" "Reference Signal Received Quality" -20 20 dBm 
        add_bar_info_entry "RSSI" "$lte_rssi" "Received Signal Strength Indicator" -120 -44 dBm
        add_bar_info_entry "SINR" "$lte_sinr" "Signal to Interference plus Noise Ratio Bandwidth" -23 40 dB
        #add_plain_info_entry "RxLev" "$lte_rxlev" "Received Signal Level"
        add_plain_info_entry "RSSNR" "$lte_rssnr" "Radio Signal Strength Noise Ratio"
        #add_plain_info_entry "CQI" "$lte_cql" "Channel Quality Indicator"
        add_plain_info_entry "TX Power" "$lte_tx_power" "TX Power"
        #add_plain_info_entry "Srxlev" "$lte_srxlev" "Serving Cell Receive Level"
        ;;
    "NR5G_SA")
        nr_mcc=$(echo "$response"|awk -F'mcc:' '{print $2}'|awk -F',' '{print $1}'|xargs)
        nr_mnc=$(echo "$response"|awk -F'mnc:' '{print $2}'|xargs)
        nr_earfcn=$(echo "$response"|awk -F'channel:' '{print $2}'|awk -F' ' '{print $1}'|xargs)
        nr_physical_cell_id=$(echo "$response"|awk -F'pci:' '{print $2}'|awk -F' ' '{print $1}'|xargs)
        nr_cell_id=$(echo "$response"|awk -F'nr_cell_id:' '{print $2}'|xargs)
        nr_band=$(echo "$response"|awk -F'nr_band:' '{print $2}'|awk -F' ' '{print $1}'|xargs)
        nr_freq_band_ind=$(echo "$response"|awk -F'lte_band_width:' '{print $2}'|xargs)
        nr_sinr=$(echo "$response"|awk -F'nr_snr:' '{print $2}'|awk '{print $1}'|xargs)
        nr_rsrq=$(echo "$response"|awk -F'rsrq:' '{print $2}'|xargs)
	nr_rsrp=$(echo "$response"|awk -F'rsrp:' '{print $2}'|awk '{print $1}'|xargs)
        lte_rssi=$(echo "$response"|awk -F'nr_rssi:' '{print $2}'|awk -F',' '{print $1}'|xargs)
        #lte_rssnr=$(echo "$response"|
        nr_tac=$(echo "$response"|awk -F'nr_tac:' '{print $2}'|xargs)
        #nr_tx_power=$(echo "$response"|awk -F'lte_tx_pwr:' '{print $2}'|xargs)

        add_plain_info_entry "MCC" "$nr_mcc" "Mobile Country Code"
        add_plain_info_entry "MNC" "$nr_mnc" "Mobile Network Code"
        #add_plain_info_entry "Duplex Mode" "$lte_duplex_mode" "Duplex Mode"
        add_plain_info_entry "Cell ID" "$nr_cell_id" "Cell ID"
        add_plain_info_entry "Physical Cell ID" "$nr_physical_cell_id" "Physical Cell ID"
        add_plain_info_entry "EARFCN" "$nr_earfcn" "E-UTRA Absolute Radio Frequency Channel Number"
        add_plain_info_entry "Freq band indicator" "$nr_freq_band_ind" "Freq band indicator"
        add_plain_info_entry "Band" "$nr_band" "Band"
        #add_plain_info_entry "UL Bandwidth" "$nr_ul_bandwidth" "UL Bandwidth"
        #add_plain_info_entry "DL Bandwidth" "$nr_dl_bandwidth" "DL Bandwidth"
        add_plain_info_entry "TAC" "$nr_tac" "Tracking area code of cell served by neighbor Enb"
        add_bar_info_entry "RSRQ" "$nr_rsrq" "Reference Signal Received Quality" -20 40 dBm
	add_bar_info_entry "RSRP" "$nr_rsrp" "Reference Signal Received Power" -187 -29 dBm
        #add_bar_info_entry "RSSI" "$nr_rssi" "Received Signal Strength Indicator" -140 -44 dBm
        add_bar_info_entry "SINR" "$nr_sinr" "Signal to Interference plus Noise Ratio Bandwidth" -23 40 dB
        #add_plain_info_entry "RxLev" "$nr_rxlev" "Received Signal Level"
        add_plain_info_entry "RSSNR" "$nr_rssnr" "Radio Signal Strength Noise Ratio"
        #add_plain_info_entry "CQI" "$nr_cql" "Channel Quality Indicator"
        add_plain_info_entry "TX Power" "$nr_tx_power" "TX Power"
        #add_plain_info_entry "Srxlev" "$nr_srxlev" "Serving Cell Receive Level"
        ;;
    esac
}



