#!/bin/bash
set -e

CACHE_DIR="$HOME/.cache/crosdl"
CROS_RELEASE_DATA="https://cdn.jsdelivr.net/gh/MercuryWorkshop/chromeos-releases-data/data.json"
BOARDS_CACHE="$CACHE_DIR/boards.txt"
MANIFESTS_DIR="$CACHE_DIR/manifests"

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
crosdl (v1.0.0) - A CLI for downloading ChromeOS related images

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
CREDIT:
    Author: Scaratek (https://scaratek.dev)
        Source code license: GPL-v3
        Repository: https://github.com/scaratech/crosdl
        Notes: Parts of the shim downloader code were stolen from vk6
    Recovery image DB: https://github.com/MercuryWorkshop/chromeos-releases-data
    RMA shim source: https://cros.download/shims
EOF
    exit 0
}

function download_shim() {
    local board="$1"
    local output="$2"
    local shim_dir="$CACHE_DIR/chunks/$board"
    
    info "Searching for shim for board: $board"
    mkdir -p "$MANIFESTS_DIR"

    local boards_index

    if [ -f "$BOARDS_CACHE" ]; then
        boards_index=$(cat "$BOARDS_CACHE")
    else
        info "Downloading boards index"

        if ! boards_index=$(wget -q -O- "https://cdn.cros.download/boards.txt"); then
            error "Failed to download boards index"
        fi

        echo "$boards_index" > "$BOARDS_CACHE"
    fi
    
    local shim_url_path
    shim_url_path=$(echo "$boards_index" | grep "/$board/" | head -1)

    if [ -z "$shim_url_path" ]; then
        error "Board '$board' not found in shim database"
    fi
    
    shim_url_path="${shim_url_path}.manifest"

    local shim_url_dir=$(dirname "$shim_url_path")
    local manifest_cache="$MANIFESTS_DIR/${board}_shim.json"
    local shim_manifest
    
    if [ -f "$manifest_cache" ]; then
        shim_manifest=$(cat "$manifest_cache")
    else
        info "Downloading manifest"

        if ! shim_manifest=$(wget -q -O- "https://cdn.cros.download/$shim_url_path"); then
            error "Failed to download manifest"
        fi

        echo "$shim_manifest" > "$manifest_cache"
    fi
    
    local zip_size=$(echo "$shim_manifest" | jq -r '.size')
    local zip_size_pretty=$(numfmt --format %.2f --to=iec "$zip_size" 2>/dev/null || echo "$zip_size bytes")
    local shim_chunks=$(echo "$shim_manifest" | jq -r '.chunks[]')
    local chunk_count=$(echo "$shim_chunks" | wc -l)
    
    info "Found shim:"
    echo "  Size: $zip_size_pretty"
    echo "  Chunks: $chunk_count"
    
    mkdir -p "$shim_dir"
    
    local i=0
    local downloaded=0
    local skipped=0
    
    for shim_chunk in $shim_chunks; do
        i=$((i + 1))

        local chunk_url="https://cdn.cros.download/$shim_url_dir/$shim_chunk"
        local chunk_path="$shim_dir/$shim_chunk"
        
        if [ -f "$chunk_path" ]; then
            local existing_size=$(stat -c%s "$chunk_path" 2>/dev/null || stat -f%z "$chunk_path" 2>/dev/null)

            if [ "$existing_size" -gt 0 ]; then
                skipped=$((skipped + 1))
                continue
            fi
        fi
        
        printf "\r\e[34m[INFO]\e[0m Downloading shim chunk: %d/%d" "$i" "$chunk_count"

        if wget -c -q "$chunk_url" -O "$chunk_path"; then
            downloaded=$((downloaded + 1))
        else
            printf "\n"
            error "Failed to download chunk $i"
        fi
    done
    
    printf "\n"
    
    if [ $skipped -gt 0 ]; then
        info "Downloaded $downloaded chunks, skipped $skipped (already cached)"
    fi
    
    info "Assembling shim file"
    local temp_output="${output}.tmp" > "$temp_output"
    
    for shim_chunk in $shim_chunks; do
        local chunk_path="$shim_dir/$shim_chunk"

        if [ ! -f "$chunk_path" ]; then
            error "Chunk missing: $chunk_path"
        fi

        cat "$chunk_path" >> "$temp_output"
    done

    mv "$temp_output" "$output"
    local final_size=$(stat -c%s "$output" 2>/dev/null || stat -f%z "$output" 2>/dev/null)

    if [ "$final_size" -eq "$zip_size" ]; then
        success "Download complete: $output ($(numfmt --format %.2f --to=iec "$final_size" 2>/dev/null || echo "$final_size bytes"))"
        info "Cleaning up chunks"

        rm -rf "$shim_dir"
    else
        error "File size mismatch (Expected: $zip_size, Got: $final_size)"
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
