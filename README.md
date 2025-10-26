# `crosdl`
A CLI for downloading ChromeOS related images

## Requirements
- A UNIX-like shell
- `git`
- `wget`
- `jq`

## Installation
```sh
$ curl https://scaratek.dev/install_crosdl.sh | bash
```

## Usage
Please note these download as zip archives !!!
```sh
# Flags
## -t = type (reco = recovery image, shim = rma shim)
## -b = filter by board
## -m = filter by model (Only for reco)
## -h = filter by HWID (Only for reco)
## -cv = filter by chrome version (Only for reco) (optional, defaults to latest)
## -pv = filter by platform version (Only for reco) (optional, defaults to latest)
## -o = path to download to

# Examples: 
crosdl -t reco -b octopus -cv 141 -o output.zip
crosdl -t reco -m "Dell Chromebook 3100" -pv 141 -o output.zip
crosdl -t reco -h ATLAS -o output.zip
crosdl -t shim -b dedede -o output.zip
```

## Credit
- Recovery image DB: https://github.com/MercuryWorkshop/chromeos-releases-data
- RMA shim source: https://cros.download/shims
