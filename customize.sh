
# write device codename in DEVICE=""
# if the kernel is flashble on multiple devices , write the value with comma separated 
# suppose the kernel is flashable on both veux and peux , then write
# DEVICE="veux,peux"
# verification will be parsed during installation by reading ro.product.device
# if left empty , it will proceed without verifying

DEVICE=""


# Backups the original boot image before patching the kernel

BACKUP=1 # set to 0 to skip Backup

BACKUP_PATH="" # Enter backup path here , Default=/sdcard/Backup/



IMAGE="" # can specify kernel image path here
# default is zip root ($MODPATH)





# Check if device verification is required
if [ -n "$DEVICE" ]; then
    current_device=$(getprop ro.product.device)  # Get current device codename
    device_verified=false

    
    IFS=','
    for allowed_device in $DEVICE; do
        if [ "$current_device" = "$allowed_device" ]; then
            device_verified=true
            break
        fi
    done
    unset IFS

    # abort if the device codename mismatches
    if [ "$device_verified" = false ]; then
        ui_print "- Error: Device $current_device is not supported !"
        abort
    else
        ui_print "- Device verified: $current_device"
    fi
else
    ui_print "- Warning : Device verification is Unset"
fi

# fn to backup og boot image

backup_boot_image() {
    if [ "$BACKUP" -eq 1 ]; then
        # set default backup path if not specified
        [ -z "$BACKUP_PATH" ] && BACKUP_PATH="/sdcard/Backup/"

        if [ "${BACKUP_PATH: -1}" = "/" ]; then
            BACKUP_PATH="${BACKUP_PATH}boot.img"
        fi
        
        # Extract directory path
        backup_dir=$(dirname "$BACKUP_PATH")
        
        mkdir -p "$backup_dir"

        if [ -e "$boot_path" ]; then
            ui_print "- Creating backup of the original boot image at $BACKUP_PATH..."
            dd if="$boot_path" of="$BACKUP_PATH" bs=4096

            # Verify if the backup was successfully created
            if [ -e "$BACKUP_PATH" ]; then
                ui_print "- Backup created successfully"
                # Generate SHA-256 checksum
                sha256sum "$BACKUP_PATH" > "$BACKUP_PATH.sha256"
            else
                ui_print "- Error: Failed to create boot image backup!"
                abort
            fi
        else
            ui_print "- Error: Original boot image not found for backup!"
            abort
        fi
    else
        ui_print "- Backup skipped as BACKUP=0."
    fi
}

cleanup() {
    ui_print "- Cleaning up...."
    rm -rf "/data/adb/tmp"
    touch "$MODPATH/remove"
    ui_print "- Finished"
}


# Function to check if device has dynamic partitions
is_dynamic_device() {
    if [ "$(getprop ro.boot.dynamic_partitions)" = "true" ]; then
        return 0  # Device has dynamic partitions
    else
        return 1  # Device does not have dynamic partitions
    fi
}

# get the current active slot (_a or _b)
get_active_slot() {
    local slot=$(grep -o "androidboot.slot_suffix=._" /proc/cmdline | cut -d '=' -f 2)
    [ -z "$slot" ] && slot=$(grep -o "androidboot.slot=." /proc/cmdline | cut -d '=' -f 2)

    # fallback to checking slot via getprop if /proc/cmdline didn't provide it
    [ -z "$slot" ] && slot=$(getprop ro.boot.slot_suffix)
    [ -z "$slot" ] && slot=$(getprop ro.boot.slot)
    echo "$slot"
}

set_boot_partition() {
    if is_dynamic_device; then
        slot=$(get_active_slot)
        boot_partition="boot$slot"
        ui_print "- Device is dynamic, using boot partition: $boot_partition"
    else
        boot_partition="boot"
        ui_print "- Device is non-dynamic, using boot partition: $boot_partition"
    fi
}

# function to find the boot partition path
find_boot_partition() {
    local partition="$1"
    local path

    path="/dev/block/by-name/$partition"
    if [ -e "$path" ]; then
        echo "$(readlink -f "$path")"
        return 0
    fi

    path="/dev/block/bootdevice/by-name/$partition"
    if [ -e "$path" ]; then
        echo "$(readlink -f "$path")"
        return 0
    fi

    path=$(find /dev/block -name "$partition" 2>/dev/null | head -n 1)
    if [ -n "$path" ]; then
        echo "$(readlink -f "$path")"
        return 0
    fi

    ui_print "- Error: Boot partition not found!"
    abort
}

# Main logic
set_boot_partition
boot_path=$(find_boot_partition "$boot_partition")
ui_print "- Boot partition path: $boot_path"
backup_boot_image
if [ "$APATCH" ]; then
    ui_print "- APatch detected"
    ui_print "- APatch: $APATCH_VER │ $APATCH_VER_CODE"
    bin_dir="/data/adb/ap/bin"
elif [ "$KSU" ]; then
    ui_print "- KernelSU Detected"
    ui_print "- KSU: $KSU_KERNEL_VER_CODE │ $KSU_VER_CODE"
    bin_dir="/data/adb/ksu/bin"
elif [ "$MAGISK_VER_CODE" ]; then
    ui_print "- Magisk Detected"
    ui_print "- Magisk: $MAGISK_VER │ $MAGISK_VER_CODE"
    bin_dir="/data/adb/magisk"
else
    ui_print "- ! Not Supported"
    abort
fi
magiskboot="$bin_dir/magiskboot"
[ ! -f "$magiskboot" ] && abort "- magiskboot not found"
[ ! -x "$magiskboot" ] && chmod +x "$magiskboot"

# create temporary directory and copy the boot image using dd
mkdir -p /data/adb/tmp
boot_img="/data/adb/tmp/boot.img"
ui_print "- Copying boot image....."
dd if="$boot_path" of="$boot_img" bs=4096

# navigate to temporary directory and unpack the boot image
cd /data/adb/tmp
ui_print "- Unpacking boot image..."
if "$magiskboot" unpack boot.img; then
    ui_print "- Boot image unpacked successfully"

    rm -f kernel


# check if a custom image path is set, and use it if available
if [ -n "$IMAGE" ]; then
    # ui_print "- Using Image: $IMAGE"
    if [ -f "$IMAGE" ]; then
        cp "$IMAGE" "$(pwd)/kernel"
    else
        ui_print "- Error: Kernel Image not found"
        abort
    fi
else
    cp "$MODPATH/Image" "$(pwd)/kernel"
fi

    # Repack the boot image
    ui_print "- Repacking boot image..."
    "$magiskboot" repack boot.img

    # Flash the new boot image
    new_boot_img="$(pwd)/new-boot.img"
    if [ -e "$new_boot_img" ]; then
        ui_print "- Flashing......"
        dd if="$new_boot_img" of="$boot_path" bs=4096
        ui_print "- Flashed successfully!"
    else
        ui_print "- Error: new-boot.img not found!"
        abort
    fi
else
    ui_print "- Error unpacking boot image!"
    abort
fi
cleanup
