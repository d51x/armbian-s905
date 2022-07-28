#!/bin/bash

SCRIPT_VER="2.1"

# Set font color
STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"
ERROR="[\033[91m ERROR \033[0m]"
FINISH="[\033[93m FINISH \033[0m]"

TOTAL_STEPS=4
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

#source /boot/uEnv.txt 2>/dev/null

TMP="/tmp"
DEV_EMMC=/dev/mmcblk2
PART_ROOT=${DEV_EMMC}p1
DIR_INSTALL=/mnt/p2

EMMC_AUTOSCRIPT_FILE=/boot/emmc2_autoscript
#UENV_FILE=/boot/uEnv.txt
UENV_FILE=uEnv.txt
UENV_EMMC_FILE=/boot/uEnv_emmc.txt

START_BOOT_SECTOR_1=0x400000        # emmc_autoscript, uEnv, dtb, kernel
START_BOOT_SECTOR_2=0x6400000       # initrd
START_EXT4_PART=116 # Mb  offset address 0x0x6400000
RESERVED_BLOCKS=/tmp/reservedblks
RESERVED_IMG=/tmp/reserved.img
RESERVED_BLOCKS_START=0x27400000
RESERVED_BLOCKS_SIZE=0x800000

# Encountered a serious error, abort the script execution
error_msg() {
    echo -e "${ERROR} ${1}"
    exit 1
}

selected_kernel=""

select_kernel() {
  kernels=( $(ls *.tar.gz) )
  i="1"
  echo -e ""
  echo -e "${STEPS} 1/${TOTAL_STEPS} Select from available kernels:"

  for fk in ${kernels[@]}; do
    echo  -e "${i}. ${fk}"
    let "i++"
  done

  echo -e "or ${i} for exit"

  read -p "Select number: " res_num

  if ! [[ "${res_num}" =~ ^[0-9]+$ ]]; then
    echo -e "${ERROR}: ${res_num} is not a number"
    select_kernel
  fi

  if [[ "${res_num}" -lt 1 || "${res_num}" -gt "${i}" ]]; then
    echo -e "${ERROR} ${res_num} is incorrect number"
    select_kernel
  fi
  [[ "${res_num}" -eq "${i}" ]] && exit 0
  selected_kernel=${kernels[ (($res_num-1)) ]}
  echo -e "${INFO} selected kernel: ${selected_kernel}"
}

init_vars() {
    inputs_kernel=$1
    kernel_file=${inputs_kernel##*/}
    kernel_name=${kernel_file/.tar.gz/}

}

unpack_kernel() {
    echo -e "${STEPS} 2/${TOTAL_STEPS} Start unpacking the kernel [ ${inputs_kernel} ] ..."

    echo -e "${INFO} removing previous kernels..."
    rm -f /boot/config-* /boot/initrd.img-* /boot/System.map-* /boot/uInitrd-* /boot/vmlinuz-* 2>/dev/null && sync
    rm -f /boot/uInitrd /boot/zImage 2>/dev/null && sync
    rm -rf /boot/dtb 2>/dev/nill && sync

    echo -e "${INFO} unpacking kernel ${kernel_name}"
    if [ -d ${TMP}/${kernel_name} ]; then
        #echo -e "Directory ${kernel_name} already exists. Removing it."
        rm -r ${TMP}/${kernel_name}
    fi

    tar -xzf ${kernel_file} -C ${TMP}

    new_kernel_name="$(ls ${TMP}/${kernel_name}/boot-${kernel_name}*.tar.gz)"
    new_kernel_name=${new_kernel_name##*/}
    new_kernel_name=${new_kernel_name/.tar.gz}
    new_kernel_name="$(echo ${new_kernel_name} | grep -oE '[1-9].[0-9]{1,3}.[0-9].+')"

    tar -xzf ${TMP}/${kernel_name}/boot-${new_kernel_name}.tar.gz -C ${TMP}/${kernel_name}
    cp -f ${TMP}/${kernel_name}/uInitrd-${new_kernel_name} /boot/uInitrd-${new_kernel_name}
    cp -f ${TMP}/${kernel_name}/vmlinuz-${new_kernel_name} /boot/vmlinuz-${new_kernel_name}
    sync
    echo -e "${INFO} unpacking boot-${new_kernel_name}.tar.gz done."

    rm -rf /usr/lib/modules/* 2>/dev/null
    tar -xzf ${TMP}/${kernel_name}/modules-${new_kernel_name}.tar.gz -C /usr/lib/modules
    sync
    echo -e "${INFO} unpacking modules-${new_kernel_name}.tar.gz done."

    mkdir -p /boot/dtb/amlogic
    tar -xzf ${TMP}/${kernel_name}/dtb-amlogic-${new_kernel_name}.tar.gz -C /boot/dtb/amlogic
    sync
    echo -e "${INFO} unpucking dtb-amlogic-${new_kernel_name}.tar.gz done"

    rm -rf ${TMP}/${kernel_name} 2>/dev/null
}

update_uenv_file() {
    echo -e "${STEPS} 3/${TOTAL_STEPS} Creating uEnv_emmc.txt file..."
    cp -f ${UENV_FILE} ${UENV_EMMC_FILE}

    #replace zImage in LINUX
    sed -i -r "s/\LINUX=(.+)/LINUX\=\/vmlinuz-${new_kernel_name}/g" ${UENV_EMMC_FILE}

    #replace initrd in INITRD
    sed -i -r "s/\INITRD=(.+)/INITRD\=\/uInitrd-${new_kernel_name}/g" ${UENV_EMMC_FILE}

    #replace root=UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx with root=/dev/blkmmcXpY

    new_path=$(sed 's,/,\\/,g' <<< ${PART_ROOT})
    sed -i "s/UUID=\b[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}\b/${new_path}/g" ${UENV_EMMC_FILE}

    echo -e "${INFO} creating uEnv_emmc.txt done."

}

create_emmc_autoscript() {
    source ${UENV_EMMC_FILE} 2>/dev/null

    KERNEL_FILE=/boot${LINUX}
    RAMDISK_FILE=/boot${INITRD}
    DTB_FILE=/boot${FDT}

    #echo -e "${INFO} compiling new emmc_autoscript"

    let start_sector=$START_BOOT_SECTOR_1/512
    let autoscript_sector=$start_sector

    AUTOSCRIPT_BLOCK_CNT=3

    dtb_fsize=`wc -c ${DTB_FILE} | awk '{print $1}'`
    uenv_fsize=`wc -c ${UENV_EMMC_FILE} | awk '{print $1}'`
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
    echo "Read ${UENV_EMMC_FILE} from EMMC"
    if mmc read \${env_addr} \${env_sector} \${env_block_cnt}; then env import -t \${env_addr} \${env_size};setenv bootargs \${APPEND};printenv bootargs;echo "Read zImage from EMMC";if mmc read \${kernel_addr} \${kernel_sector} \${kernel_block_cnt}; then echo "Read uInitrd from EMMC";if mmc read \${initrd_addr} \${initrd_sector} \${initrd_block_cnt}; then echo "Read FDT from EMMC";if mmc read \${dtb_addr} \${dtb_sector} \${dtb_block_cnt}; then run addmac;echo "Start booting system...";run boot_start;fi;fi;fi;fi
EOF

    mkimage -C none -A arm -T script -d ${EMMC_AUTOSCRIPT_FILE}.cmd ${EMMC_AUTOSCRIPT_FILE} >/dev/null

    echo -e "${INFO} compiling new emmc_autoscript done."
}

copy_file_to_boot() {
    echo -e "${INFO} copy $1 [seek=$2, size=$3]"
    dd if=$1 of=${DEV_EMMC} bs=512 seek=$2 conv=fsync status=none
}

create_boot_partition() {
    echo -e "${STEPS} 4/${TOTAL_STEPS} Preparing pseudo-BOOT partition in EMMC"

    create_emmc_autoscript

    let seek_block=$autoscript_sector
    fsize=`wc -c ${EMMC_AUTOSCRIPT_FILE} | awk '{print $1}'`
    copy_file_to_boot ${EMMC_AUTOSCRIPT_FILE} ${seek_block} ${fsize} "emmc_autoscript"

    let seek_block=$seek_block+$AUTOSCRIPT_BLOCK_CNT
    copy_file_to_boot ${DTB_FILE} ${seek_block} ${dtb_fsize} "dtb-file"

    let seek_block=$seek_block+$dtb_block_cnt
    copy_file_to_boot ${UENV_EMMC_FILE} ${seek_block} ${uenv_fsize} "uEnv.txt"

    let seek_block=$seek_block+$uenv_block_cnt
    copy_file_to_boot ${KERNEL_FILE} ${seek_block} ${kernel_fsize} "kernel zImage"

    copy_file_to_boot ${RAMDISK_FILE} ${initrd_sector} ${initrd_fsize} "ramdisk uInitrd"

    echo -e "${INFO} preparing pseudo-BOOT partition DONE"
}

#########################################################################3

echo -e "${SUCCESS} Start install new kernel to emmc..."
echo -e "${SUCCESS} Script version: ${SCRIPT_VER}"

# Check script permission
 [[ "$(id -u)" == "0" ]] || error_msg "please run this script as root: [ sudo $0 ]"
#

select_kernel
init_vars "${selected_kernel}"
unpack_kernel
update_uenv_file
create_boot_partition


echo -e "${FINISH} Successful installed, please unplug the USB, re-insert the power supply to start the armbian."
exit 0
