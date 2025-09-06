# ==== IOMMU library for BASMRUN ====
IOMMU_ROOT="/data/local/tmp/balkava_hardware/iommu"
IOMMU_LOG="$IOMMU_ROOT/logs.txt"

_iommu_log() {
    mkdir -p "$IOMMU_ROOT" || return 1
    printf '[IOMMU] %s\n' "$*" >> "$IOMMU_LOG"
}

# kv parse: get VALUE of KEY= from arg string
kv() {
    # usage: kv "KEY" "$ARGSTR"
    echo "$2" | awk -v K="$1" '{
        for (i=1;i<=NF;i++) if ($i ~ "^"K"=") { sub("^"K"=","",$i); print $i; exit }
    }'
}

# normalize 0x... to lowercase w/ 0x prefix
hexnorm() {
    v=$(echo "$1" | tr 'A-F' 'a-f')
    case "$v" in
        0x*) echo "$v" ;;
        *)   printf '0x%x\n' "$((v))" ;;
    esac
}

_dec() {
    printf '%d' "$(($1))"
}

in_range() {
    # usage: in_range IOVA_START SIZE IOVA_QUERY
    s=$(( $1 ))
    sz=$(( $2 ))
    q=$(( $3 ))
    e=$(( s + sz ))
    [ "$q" -ge "$s" ] && [ "$q" -lt "$e" ]
}

iommu_domain_dir() { echo "$IOMMU_ROOT/domains/$1"; }
iommu_dev_dir()    { echo "$IOMMU_ROOT/devices/$1"; }

iommu_create_domain() {
    name=$1 pg=$2
    d=$(iommu_domain_dir "$name")
    mkdir -p "$d/maps" || return 1
    {
        echo "NAME=$name"
        echo "PGSIZE=$pg"
    } > "$d/config"
    _iommu_log "CREATE_DOMAIN name=$name pgsize=$pg"
}

iommu_destroy_domain() {
    name=$1 d=$(iommu_domain_dir "$name")
    [ -d "$d" ] || { echo "ERR: no such domain" ; return 1; }
    if grep -Rl "$name" "$IOMMU_ROOT/devices" >/dev/null 2>&1; then
        echo "ERR: domain in use"
        return 1
    fi
    rm -rf "$d"
    _iommu_log "DESTROY_DOMAIN name=$name"
}

iommu_attach_dev() {
    dev=$1 dom=$2 dd=$(iommu_dev_dir "$dev")
    d=$(iommu_domain_dir "$dom")
    [ -d "$d" ] || { echo "ERR: no such domain"; return 1; }
    mkdir -p "$dd" || return 1
    echo "$dom" > "$dd/domain"
    _iommu_log "ATTACH dev=$dev domain=$dom"
}

iommu_detach_dev() {
    dev=$1 dd=$(iommu_dev_dir "$dev")
    [ -d "$dd" ] || { echo "ERR: no such device"; return 1; }
    rm -f "$dd/domain"
    rmdir "$dd" 2>/dev/null
    _iommu_log "DETACH dev=$dev"
}

iommu_map() {
    dom=$1 iova=$2 phys=$3 size=$4 perm=$5
    d=$(iommu_domain_dir "$dom")
    [ -d "$d" ] || { echo "ERR: no such domain"; return 1; }
    f="$d/maps/${iova}-${size}"
    {
        echo "PHYS=$phys"
        echo "SIZE=$size"
        echo "PERM=$perm"
    } > "$f"
    _iommu_log "MAP domain=$dom iova=$iova phys=$phys size=$size perm=$perm"
}

iommu_unmap() {
    dom=$1 iova=$2 size=$3
    d=$(iommu_domain_dir "$dom")
    f="$d/maps/${iova}-${size}"
    [ -f "$f" ] || { echo "ERR: no such mapping"; return 1; }
    rm -f "$f"
    _iommu_log "UNMAP domain=$dom iova=$iova size=$size"
}

iommu_translate() {
    dom=$1 iova_hex=$2
    d=$(iommu_domain_dir "$dom")
    [ -d "$d" ] || { echo "FAULT:DOMAIN"; return 1; }
    iova=$(( iova_hex ))
    hit=""
    for m in "$d/maps/"*; do
        [ -f "$m" ] || continue
        base_hex=$(basename "$m" | cut -d- -f1)
        size=$(basename "$m" | cut -d- -f2)
        base=$(( base_hex ))
        if in_range "$base" "$size" "$iova"; then
            phys=$(grep '^PHYS=' "$m" | cut -d= -f2)
            perm=$(grep '^PERM=' "$m" | cut -d= -f2)
            offset=$(( iova - base ))
            phys_dec=$(( phys ))
            phys_off=$(( phys_dec + offset ))
            printf 'PHYS=0x%x PERM=%s\n' "$phys_off" "$perm"
            hit=1
            break
        fi
    done
    [ -n "$hit" ] || echo "FAULT:UNMAPPED"
}

iommu_stats() {
    dom=$1 d=$(iommu_domain_dir "$dom")
    [ -d "$d" ] || { echo "ERR: no such domain"; return 1; }
    n=0
    bytes=0
    for m in "$d/maps/"*; do
        [ -f "$m" ] || continue
        n=$((n+1))
        bytes=$(( bytes + $(basename "$m" | cut -d- -f2) ))
    done
    echo "DOMAIN=$dom MAPS=$n BYTES=$bytes"
}

iommu_dma() {
    dev=$1 dir=$2 iova_hex=$3 size=$4
    dd=$(iommu_dev_dir "$dev")
    [ -f "$dd/domain" ] || { echo "FAULT:NODEV"; return 1; }
    dom=$(cat "$dd/domain")
    tr=$(iommu_translate "$dom" "$iova_hex")
    case "$tr" in
        FAULT:*)
            _iommu_log "DMA_FAIL dev=$dev dom=$dom iova=$iova_hex size=$size reason=$tr"
            echo "$tr"
            return 1
            ;;
        *)
            perm=$(echo "$tr" | awk '{print $2}' | cut -d= -f2)
            case "$dir" in
                read)
                    echo "$perm" | grep -q "r" && {
                        _iommu_log "DMA_OK dev=$dev dir=$dir $tr size=$size"
                        echo "OK $tr"
                        return
                    }
                    ;;
                write)
                    echo "$perm" | grep -q "w" && {
                        _iommu_log "DMA_OK dev=$dev dir=$dir $tr size=$size"
                        echo "OK $tr"
                        return
                    }
                    ;;
            esac
            _iommu_log "DMA_FAIL dev=$dev dir=$dir $tr size=$size reason=PERM"
            echo "FAULT:PERM"
            return 1
            ;;
    esac
}
# ==== end library ====