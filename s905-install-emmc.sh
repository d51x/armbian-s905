#!/bin/bash

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
#      'blkdevparts=mmcblk2:512M@108M(cache),-M@644M(rootfs)'
#
#   Reboot system and you can access to these partitions as
#     cache:  /dev/mmcblk2p1
#     rootfs: /dev/mmcblk2p2
#
#   Note: EMMC has partitions: 
#        name                        offset              size              flag
#================================================================================   
#   0: bootloader                         0            400000                  0
#   1: reserved                     2400000           4000000                  0
#   2: cache                        6c00000          20000000                  2    
#   3: env                         27400000            800000                  0    
#   4: logo                        28400000           2000000                  1    
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
# I don't know, but my attempts show that partitions 0, 1 and 3 are necessary for normal botting from emmc,
# other partitions 4 - 13 can be combined to one partition ROOTFS 
# and partition 2 (cache) we can use as BOOTFS partition.
#
# May be if change partitions structure which contains in "reserved" partition we can move 
# "env" partition before "cache" and all space after "env" could be used for BOOT and ROOT partitions,
# because original "cache" partition size is 512 Mb 
# Unfortunately I don't try yet
# uEnv.txt is a base file for kernel, ramfs, dtb
# copy uEnv.txt to uEnv_emmc.txt and change root=UUID=61fc7a35-...... to root=/dev/mmcblk2p2
###############################################################################################################




echo -e "${STEPS} Start install armbian to emmc..."

source /boot/uEnv.txt 2>/dev/null

DEV_EMMC=/dev/mmcblk2
PART_BOOT=${DEV_EMMC}p1
PART_ROOT=${DEV_EMMC}p2
DIR_INSTALL=/mnt/p2
DTB_FILE=/boot${FDT}
EMMC_AUTOSCRIPT_FILE=/boot/emmc2_autoscript
UENV_FILE=/boot/uEnv_emmc.txt
KERNEL_FILE=/boot${LINUX}
RAMDISK_FILE=/boot${INITRD}

START_BOOT_SECTOR=0x6C00000


clean_boot_partition() {
    echo -e "${STEPS} clear boot partition"
    dd if=/dev/zero of=${DEV_EMMC} bs=1M seek=108 count=512 conv=fsync
}

create_emmc_autoscript() {
    echo -e "${INFO} Compile new emmc_autoscript"

    let start_sector=$START_BOOT_SECTOR/512
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

    let next_sector=$next_sector+$kernel_block_cnt

    let initrd_block_cnt=$initrd_fsize/512+1
    initrd_sector=$next_sector
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

create_boot_partition() {
    echo -e "${STEPS} prepare BOOTFS partition into EMMC"
    
    create_emmc_autoscript

    echo -e "${INFO} Copy emmc_autoscript to BOOT partition"
    seek_block=0
    fsize=`wc -c ${EMMC_AUTOSCRIPT_FILE} | awk '{print $1}'`
    echo -e "${INFO}\t file: ${EMMC_AUTOSCRIPT_FILE} \t\t\t size=${fsize} \t seek=${seek_block}"
    dd if=${EMMC_AUTOSCRIPT_FILE} of=${PART_BOOT} bs=512 conv=fsync

    echo -e "${INFO} Copy dtb-file to BOOT partition"
    let seek_block=$seek_block+$AUTOSCRIPT_BLOCK_CNT
    echo -e "${INFO}\t file: ${DTB_FILE} \t\t\t size=${dtb_fsize} \t seek=${seek_block}"
    dd if=${DTB_FILE} of=${PART_BOOT} bs=512 seek=${seek_block} conv=fsync

    echo -e "${INFO} Copy uEnv.txt to BOOT partition"
    let seek_block=$seek_block+$dtb_block_cnt
    echo -e "${INFO}\t file: ${UENV_FILE} \t\t\t size=${uenv_fsize} \t seek=${seek_block}"
    dd if=${UENV_FILE} of=${PART_BOOT} bs=512 seek=${seek_block} conv=fsync

    echo -e "${INFO} Copy kernel zImage to BOOT partition"
    let seek_block=$seek_block+$uenv_block_cnt
    echo -e "${INFO}\t file: ${KERNEL_FILE} \t\t\t size=${kernel_fsize} \t seek=${seek_block}"
    dd if=${KERNEL_FILE} of=${PART_BOOT} bs=512 seek=${seek_block} conv=fsync

    echo -e "${INFO} Copy ramdisk uInitrd to BOOT partition"
    let seek_block=$seek_block+$kernel_block_cnt
    echo -e "\t file: ${RAMDISK_FILE} \t\t\t size=${initrd_fsize} \t seek=${seek_block}"
    dd if=${RAMDISK_FILE} of=${PART_BOOT} bs=512 seek=${seek_block} conv=fsync

    echo -e "${INFO} DONE. BOOTFS was copied to EMMC"
}

clean_root_partition() {
    echo -e "${STEPS} clear root partition"
    dd if=/dev/zero of=${DEV_EMMC} bs=1M seek=644 count=6812 conv=fsync
}

create_root_partition() {
    echo -e "${STEPS} make ROOTFS patition"
    ROOTFS_UUID="$(cat /proc/sys/kernel/random/uuid)"
    mkfs.ext4 -F -q -U ${ROOTFS_UUID} -L "ROOTFS_EMMC" ${PART_ROOT}
    sleep 3
}

copy_rootfs() {
    echo -e "${STEPS} copy ROOTFS to EMMC"
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

clean_root_partition
create_root_partition
copy_rootfs

clean_boot_partition
create_boot_partition


echo -e "${SUCCESS} Successful installed, please unplug the USB, re-insert the power supply to start the armbian."
exit 0
