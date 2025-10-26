#!/bin/bash
set -e

CACHE_DIR="$HOME/.cache/crosdl"
CROS_RELEASE_DATA="https://cdn.jsdelivr.net/gh/MercuryWorkshop/chromeos-releases-data/data.json"
BOARDS_CACHE="$CACHE_DIR/boards.txt"

function info() {
    echo -e "\e[34m[INFO]\e[0m $1"
}

function error() {
    echo -e "\e[31m[ERROR]\e[0m $1"
    exit 1
}

function success() {
    echo -e "\e[32m[SUCCESS]\e[0m $1"
}

function help_msg() {
    cat << EOF
crosdl (v1.2.0) - A CLI for downloading ChromeOS related images

USAGE:
    crosdl [OPTIONS]
OPTIONS:
    -t <type>           Image type (reco = recovery image, shim = RMA shim) (required)
    -b <board>          Filter by board name (required)
    -m <model>          Filter by model name (only for reco)
    -h <hwid>           Filter by HWID pattern (only for reco)
    -cv <version>       Filter by Chrome version (only for reco, optional, defaults to latest)
    -pv <version>       Filter by platform version (only for reco, optional, defaults to latest)
    -o <path>           Output file path (required)
    --help              Show this help message
    --clear-cache       Clear cached data
    --cache             Populate cache
CREDIT:
    Author: Scaratek (https://scaratek.dev)
        Source code license: GPL-v3
        Repository: https://github.com/scaratech/crosdl
    Recovery image DB: https://github.com/MercuryWorkshop/chromeos-releases-data
    RMA shim source: https://cros.download/shims
EOF
    exit 0
}

function clear_cache() {
    if [ -d "$CACHE_DIR" ]; then
        rm -rf "$CACHE_DIR"
        success "Cache cleared"
        exit 0
    fi
}

function cache_data() {
    mkdir -p "$CACHE_DIR"

    info "Caching release information"
    wget -q -O "$CACHE_DIR/data.json" "$CROS_RELEASE_DATA"

    info "Caching boards index"
    wget -q -O "$BOARDS_CACHE" "https://cdn.cros.download/boards.txt"

    success "Cache populated"
    exit 0
}

function download_shim() {
    local board="$1"
    local output="$2"
    
    info "Searching for shim for board: $board"
    
    local boards_list

    if [ -f "$BOARDS_CACHE" ]; then
        boards_list=$(cat "$BOARDS_CACHE")
    else
        info "Downloading boards index"

        if ! boards_list=$(wget -q -O- "https://cdn.cros.download/boards.txt"); then
            error "Failed to download boards index"
        fi

        echo "$boards_list" > "$BOARDS_CACHE"
    fi
    
    if ! echo "$boards_list" | grep -q "/$board/"; then
        error "Board '$board' not found in shim list"
    fi
    
    local shim_url="https://dl.cros.download/files/$board/$board.zip"
    local shim_size=$(echo "$http_res" | grep -i "Content-Length:" | tail -1 | awk '{print $2}' | tr -d '\r')
    
    info "Found shim:"
    echo "  Board: $board"
    echo "  URL: $shim_url"
    
    info "Downloading shim"
    
    if wget -q --show-progress -O "$output" "$shim_url"; then
        success "Download complete: $output"
    else
        error "Failed to download shim"
    fi
}

function download_recovery() {
    local board="$1"
    local model="$2"
    local hwid="$3"
    local chrome_version="$4"
    local platform_version="$5"
    local output="$6"
    
    info "Searching for matching device"
    local jq_filter='to_entries[] | select('
    
    if [[ -n "$board" ]]; then
        jq_filter+="(.key == \"$board\")"
    fi
    
    if [[ -n "$model" ]]; then
        [[ -n "$board" ]] && jq_filter+=" and "
        jq_filter+="(.value.brand_names[]? // \"\" | contains(\"$model\"))"
    fi
    
    if [[ -n "$hwid" ]]; then
        [[ -n "$board" || -n "$model" ]] && jq_filter+=" and "
        jq_filter+="(.value.hwid_matches[]? // \"\" | test(\"$hwid\"; \"i\"))"
    fi
    
    jq_filter+=') | .value'
    local board_data=$(jq -c "$jq_filter" "$CACHE_DIR/data.json" 2>/dev/null | head -1)
    
    if [[ -z "$board_data" ]]; then
        error "No matching device found"
    fi
    
    local images_filter='.images[] | select(.platform_version != "0.0.0")'
    
    if [[ -n "$chrome_version" ]]; then
        images_filter+=" | select(.chrome_version | startswith(\"$chrome_version\"))"
    fi
    
    if [[ -n "$platform_version" ]]; then
        images_filter+=" | select(.platform_version | startswith(\"$platform_version\"))"
    fi
    
    local image_data=$(echo "$board_data" | jq -c "$images_filter" 2>/dev/null | tail -1)
    
    if [[ -z "$image_data" ]]; then
        error "No matching image found with specified version filters"
    fi
    
    local image_url=$(echo "$image_data" | jq -r '.url')
    local chrome_ver=$(echo "$image_data" | jq -r '.chrome_version')
    local platform_ver=$(echo "$image_data" | jq -r '.platform_version')
    
    info "Found image:"
    echo "  Chrome Version: $chrome_ver"
    echo "  Platform Version: $platform_ver"
    echo "  URL: $image_url"
    
    info "Downloading to $output"
    
    if wget -q --show-progress -O "$output" "$image_url"; then
        success "Download complete: $output"
    else
        error "Download failed"
    fi
}

if ! command -v jq &> /dev/null; then
    error "jq not found, please install jq"
fi

if ! command -v wget &> /dev/null; then
    error "wget not found, please install wget"
fi

TYPE=""
BOARD=""
MODEL=""
HWID=""
CHROME_VERSION=""
PLATFORM_VERSION=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -t) 
            if [[ -z "$2" || "$2" == -* ]]; then
                error "Option -t requires an argument (reco or shim)"
            fi

            TYPE="$2"
            shift 2
            ;;
        -b) 
            if [[ -z "$2" || "$2" == -* ]]; then
                error "Option -b requires an argument (board name)"
            fi

            BOARD="$2"
            shift 2
            ;;
        -m) 
            if [[ -z "$2" || "$2" == -* ]]; then
                error "Option -m requires an argument (model name)"
            fi

            MODEL="$2"
            shift 2
            ;;
        -h) 
            if [[ -z "$2" || "$2" == -* ]]; then
                error "Option -h requires an argument (HWID pattern)"
            fi

            HWID="$2"
            shift 2
            ;;
        -cv) 
            if [[ -z "$2" || "$2" == -* ]]; then
                error "Option -cv requires an argument (Chrome version)"
            fi

            CHROME_VERSION="$2"
            shift 2
            ;;
        -pv) 
            if [[ -z "$2" || "$2" == -* ]]; then
                error "Option -pv requires an argument (platform version)"
            fi

            PLATFORM_VERSION="$2"
            shift 2
            ;;
        -o) 
            if [[ -z "$2" || "$2" == -* ]]; then
                error "Option -o requires an argument (output file path)"
            fi

            OUTPUT="$2"
            shift 2
            ;;
        --help) help_msg;;
        --clear-cache) clear_cache; shift;;
        --cache) cache_data; shift;;
        "") shift;;
        *) error "Unknown option: $1";;
    esac
done

if [[ -z "$TYPE" && -z "$BOARD" && -z "$MODEL" && -z "$HWID" && -z "$OUTPUT" ]]; then
    help_msg
fi

[[ -z "$TYPE" ]] && error "Type (-t) is required"
[[ -z "$OUTPUT" ]] && error "Output path (-o) is required"

if [[ "$TYPE" != "reco" && "$TYPE" != "shim" ]]; then
    error "Invalid type: $TYPE (must be 'reco' or 'shim')"
fi

if [[ "$TYPE" != "reco" && "$TYPE" != "shim" ]]; then
    error "Invalid type: $TYPE (must be 'reco' or 'shim')"
fi

mkdir -p "$CACHE_DIR"
mkdir -p "$MANIFESTS_DIR"

if [ ! -f "$CACHE_DIR/data.json" ]; then
    info "Caching release information"
    wget -q -O "$CACHE_DIR/data.json" "$CROS_RELEASE_DATA"
fi

case "$TYPE" in
    reco)
        [[ -z "$BOARD" && -z "$MODEL" && -z "$HWID" ]] && error "At least one filter (-b, -m, or -h) is required for recovery images"
        download_recovery "$BOARD" "$MODEL" "$HWID" "$CHROME_VERSION" "$PLATFORM_VERSION" "$OUTPUT"
        ;;
    shim)
        [[ -z "$BOARD" ]] && error "Board name (-b) is required for shim downloads"
        download_shim "$BOARD" "$OUTPUT"
        ;;
esac
