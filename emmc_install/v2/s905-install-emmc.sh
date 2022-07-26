#!/bin/bash

SCRIPT_VER="2.1"

# Set font color
STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"

################################################################################################################
# STEP 0:
#   add the ability to work with partitions on EMMC via "blkdevparts" cmdline param
#
#   edit your uEnv.txt
#   add the followin to APPEND param:
#      'blkdevparts=mmcblk2:-@116M(rootfs)'
#
#   Reboot system and you can access to these partition as
#     rootfs:  /dev/mmcblk2p1
#
#   Note: EMMC has original partition table: 
#        name                        offset              size              flag
#================================================================================   
#   0: bootloader                         0            400000 (4Mb)            0
#                                                      GAP 8 Mb
#   1: reserved                     2400000 (36Mb)    4000000 (64Mb)           0
#                                                      GAP 8 Mb
#   2: cache                        6c00000 (108Mb)  20000000 (512Mb)          2   
#                                                      GAP 8 Mb 
#   3: env                         27400000 (628Mb)    800000 (8Mb)            0   
#                                                      GAP 8 Mb 
#   4: logo                        28400000 (644Mb    2000000 (32Mb)           1   
#                                                      GAP 8 Mb 
#   5: recovery                    2ac00000           2000000                  1   	
#   6: rsv                         2d400000            800000                  1 	
#   7: tee                         2e400000            800000                  1
#   8: crypt                       2f400000           2000000                  1
#   9: misc                        31c00000           2000000                  1
#  10: instaboot                   34400000          20000000                  1
#  11: boot                        54c00000           2000000                  1
#  12: system                      57400000          60000000                  1
#  13: data                        b7c00000         11a400000                  4
#
#  Put emmc_autoscript, uEnv, dtb, kernel into space between bootloader and reserved partitions.
#  Put initrd into 16 Mb space after reserved partition.
#  From 116 Mb offset of the beginning emmc make zone for ext4 partition 
#
#
#
# uEnv.txt is a base file for kernel, ramfs, dtb
# copy uEnv.txt to uEnv_emmc.txt and change root=UUID=61fc7a35-...... to root=/dev/mmcblk2p1
#
# thanks to https://github.com/laris/Phicomm-N1/blob/master/refs/use-single-partition-to-boot-linux-on-phicomm-n1.md
# for information about how make more size for ext4 partition and skip env-partition as bad blocks inside ext4 partition
###############################################################################################################

source /boot/uEnv.txt 2>/dev/null

DEV_EMMC=/dev/mmcblk2
PART_ROOT=${DEV_EMMC}p1
DIR_INSTALL=/mnt/p2
DTB_FILE=/boot${FDT}
EMMC_AUTOSCRIPT_FILE=/boot/emmc2_autoscript
UENV_FILE=/boot/uEnv_emmc.txt
KERNEL_FILE=/boot${LINUX}
RAMDISK_FILE=/boot${INITRD}

START_BOOT_SECTOR_1=0x400000        # emmc_autoscript, uEnv, dtb, kernel
START_BOOT_SECTOR_2=0x6400000       # initrd
START_EXT4_PART=116 # Mb  offset address 0x0x6400000
RESERVED_BLOCKS=/tmp/reservedblks
RESERVED_IMG=/tmp/reserved.img
RESERVED_BLOCKS_START=0x27400000
RESERVED_BLOCKS_SIZE=0x800000

create_emmc_autoscript() {
    echo -e "${INFO} Compile new emmc_autoscript"

    let start_sector=$START_BOOT_SECTOR_1/512
    let autoscript_sector=$start_sector

    AUTOSCRIPT_BLOCK_CNT=3

    dtb_fsize=`wc -c ${DTB_FILE} | awk '{print $1}'`
    uenv_fsize=`wc -c ${UENV_FILE} | awk '{print $1}'`
    kernel_fsize=`wc -c ${KERNEL_FILE} | awk '{print $1}'`
    initrd_fsize=`wc -c ${RAMDISK_FILE} | awk '{print $1}'`

    let next_sector=$start_sector+$AUTOSCRIPT_BLOCK_CNT
    let dtb_block_cnt=$dtb_fsize/512+1
    dtb_sector=$next_sector
    dtb_sector_hex=`printf "0x%x" ${dtb_sector}`
    dtb_block_cnt_hex=`printf "0x%x" ${dtb_block_cnt}`

    let next_sector=$next_sector+$dtb_block_cnt

    let uenv_block_cnt=$uenv_fsize/512+1
    uenv_sector=$next_sector
    uenv_sector_hex=`printf "0x%x" ${uenv_sector}`
    uenv_block_cnt_hex=`printf "0x%x" ${uenv_block_cnt}`

    let next_sector=$next_sector+$uenv_block_cnt

    let kernel_block_cnt=$kernel_fsize/512+1
    kernel_sector=$next_sector
    kernel_sector_hex=`printf "0x%x" ${kernel_sector}`
    kernel_block_cnt_hex=`printf "0x%x" ${kernel_block_cnt}`

    let initrd_block_cnt=$initrd_fsize/512+1
    let initrd_sector=$START_BOOT_SECTOR_2/512
    initrd_sector_hex=`printf "0x%x" ${initrd_sector}`
    initrd_block_cnt_hex=`printf "0x%x" ${initrd_block_cnt}`

    cat >${EMMC_AUTOSCRIPT_FILE}.cmd <<EOF
    echo "Select EMMC"
    mmc dev 1
    sleep 3
    echo "Set env variables"
    setenv dtb_addr 0x1000000
    setenv dtb_sector ${dtb_sector_hex}
    setenv dtb_block_cnt ${dtb_block_cnt_hex}
    setenv env_addr 0x1040000
    setenv env_sector ${uenv_sector_hex}
    setenv env_block_cnt ${uenv_block_cnt_hex}
    setenv env_size ${uenv_fsize}
    setenv kernel_addr 0x11000000
    setenv kernel_sector ${kernel_sector_hex}
    setenv kernel_block_cnt ${kernel_block_cnt_hex}
    setenv initrd_addr 0x13000000
    setenv initrd_sector ${initrd_sector_hex}
    setenv initrd_block_cnt ${initrd_block_cnt_hex}
    setenv boot_start booti \${kernel_addr} \${initrd_addr} \${dtb_addr}
    setenv addmac 'if printenv mac; then setenv bootargs \${bootargs} mac=\${mac}; elif printenv eth_mac; then setenv bootargs \${bootargs} mac=\${eth_mac}; elif printenv ethaddr; then setenv bootargs \${bootargs} mac=\${ethaddr}; fi'

    echo "Read mmc partitions"
    echo "Read ${UENV_FILE} from EMMC"
    if mmc read \${env_addr} \${env_sector} \${env_block_cnt}; then env import -t \${env_addr} \${env_size};setenv bootargs \${APPEND};printenv bootargs;echo "Read zImage from EMMC";if mmc read \${kernel_addr} \${kernel_sector} \${kernel_block_cnt}; then echo "Read uInitrd from EMMC";if mmc read \${initrd_addr} \${initrd_sector} \${initrd_block_cnt}; then echo "Read FDT from EMMC";if mmc read \${dtb_addr} \${dtb_sector} \${dtb_block_cnt}; then run addmac;echo "Start booting system...";run boot_start;fi;fi;fi;fi
EOF

    mkimage -C none -A arm -T script -d ${EMMC_AUTOSCRIPT_FILE}.cmd ${EMMC_AUTOSCRIPT_FILE} >/dev/null
}

copy_file_to_boot() {
    echo -e "${INFO} Copy $1 to pseudo-BOOT partition: \t seek=$2 \t size=$3"
    dd if=$1 of=${DEV_EMMC} bs=512 seek=$2 conv=fsync status=none
}

create_boot_partition() {
    echo -e "${STEPS} preparing pseudo-BOOT partition in EMMC"
    
    create_emmc_autoscript

    let seek_block=$autoscript_sector
    fsize=`wc -c ${EMMC_AUTOSCRIPT_FILE} | awk '{print $1}'`
    copy_file_to_boot ${EMMC_AUTOSCRIPT_FILE} ${seek_block} ${fsize} "emmc_autoscript"

    let seek_block=$seek_block+$AUTOSCRIPT_BLOCK_CNT
    copy_file_to_boot ${DTB_FILE} ${seek_block} ${dtb_fsize} "dtb-file"

    let seek_block=$seek_block+$dtb_block_cnt
    copy_file_to_boot ${UENV_FILE} ${seek_block} ${uenv_fsize} "uEnv.txt"

    let seek_block=$seek_block+$uenv_block_cnt
    copy_file_to_boot ${KERNEL_FILE} ${seek_block} ${kernel_fsize} "kernel zImage"

    copy_file_to_boot ${RAMDISK_FILE} ${initrd_sector} ${initrd_fsize} "ramdisk uInitrd"

    echo -e "${INFO} DONE. BOOTFS was copied to EMMC"
}

as_block_number() {
    # Block numbers are offseted by 100M since `/dev/mmcblk1p1` starts at 116M START_BLOCK
    # in `/dev/mmcblk1`.
    #
    # Because we're using 4K blocks, the byte offsets are divided by 4K.
    expr $((($1 - ${START_EXT4_PART} * 1024 * 1024) / 4096))
}

gen_blocks() {
    seq $(as_block_number $1) $(($(as_block_number $(($1 + $2))) - 1))
}

reserv_blocks() {
    echo -e "${INFO} reserving env-partition blocks"
    gen_blocks ${RESERVED_BLOCKS_START} ${RESERVED_BLOCKS_SIZE} > ${RESERVED_BLOCKS}
    dd if=${DEV_EMMC} of=${RESERVED_IMG} bs=1M skip=36 count=64 status=none
}

restore_reserved() {
    dd if=${RESERVED_IMG} of=${DEV_EMMC} bs=1M seek=36 status=none
    rm ${RESERVED_IMG}
}

format_root_partition() {
    echo -e "${STEPS} formating ROOTFS patition"
    ROOTFS_UUID="$(cat /proc/sys/kernel/random/uuid)"
    mke2fs -F -q -O ^64bit -t ext4 -m 0 ${PART_ROOT} -b 4096 -l ${RESERVED_BLOCKS} -U ${ROOTFS_UUID} -L "ROOTFS_EMMC" > /dev/null
    sleep 3
    rm ${RESERVED_BLOCKS}
}


copy_rootfs() {
    echo -e "${STEPS} copying ROOTFS to EMMC"
    cd /
    mkdir ${DIR_INSTALL}
    mount -t ext4 ${PART_ROOT} ${DIR_INSTALL}
    mkdir -p ${DIR_INSTALL}/{boot/,dev/,media/,mnt/,proc/,run/,sys/} && sync

    COPY_SRC="etc home lib64 opt root selinux srv usr var"
    for src in ${COPY_SRC}; do
        echo -e "${INFO} Copy the [ ${src} ] directory."
        tar -cf - ${src} | (
            cd ${DIR_INSTALL}
            tar -xf -
        )
        sync
    done

    ln -sf /usr/bin ${DIR_INSTALL}/bin
    ln -sf /usr/lib ${DIR_INSTALL}/lib
    ln -sf /usr/sbin ${DIR_INSTALL}/sbin
    ln -sf /var/tmp ${DIR_INSTALL}/tmp
    sync

    echo -e "${INFO} Generate the new fstab file."
    fstab_mount_string="defaults,noatime,errors=remount-ro"
    rm -f ${DIR_INSTALL}/etc/fstab 2>/dev/null && sync

    cat >${DIR_INSTALL}/etc/fstab <<EOF
    ${PART_ROOT}  /        ext4     ${fstab_mount_string}     0 1
    tmpfs                /tmp     tmpfs                   defaults,nosuid           0 0

EOF
    sync && sleep 3
    umount ${DIR_INSTALL}
    rm -rf ${DIR_INSTALL}

    echo -e "${INFO} DONE. ROOTFS was copied to EMMC"
}

create_root_partition() {
    echo -e "${STEPS} Creating ROOTFS patition..."
    reserv_blocks
    format_root_partition
    copy_rootfs
    sync
}

#########################################################################3

echo -e "${SUCCESS} Start install armbian to emmc..."
echo -e "${SUCCESS} Script version: ${SCRIPT_VER}"

create_boot_partition
create_root_partition
restore_reserved

echo -e "${SUCCESS} Successful installed, please unplug the USB, re-insert the power supply to start the armbian."
exit 0
