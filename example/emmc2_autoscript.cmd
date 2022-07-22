echo "Select EMMC"
mmc dev 1
sleep 3
echo "Set env variables"
setenv dtb_addr 0x1000000
setenv dtb_sector 0x36003
setenv dtb_block_cnt 0x4a
setenv env_addr 0x1040000
setenv env_sector 0x3604d
setenv env_block_cnt 0x1
setenv env_size 417
setenv kernel_addr 0x11000000
setenv kernel_sector 0x3604e
setenv kernel_block_cnt 0xca46
setenv initrd_addr 0x13000000
setenv initrd_sector 0x42a94
setenv initrd_block_cnt 0x5fcb
setenv boot_start booti ${kernel_addr} ${initrd_addr} ${dtb_addr}
setenv addmac 'if printenv mac; then setenv bootargs ${bootargs} mac=${mac}; elif printenv eth_mac; then setenv bootargs ${bootargs} mac=${eth_mac}; elif printenv ethaddr; then setenv bootargs ${bootargs} mac=${ethaddr}; fi'

echo "Read mmc partitions"
echo "Read /boot/uEnv_emmc.txt from EMMC"
if mmc read ${env_addr} ${env_sector} ${env_block_cnt}; then env import -t ${env_addr} ${env_size};setenv bootargs ${APPEND};printenv bootargs;echo "Read zImage from EMMC";if mmc read ${kernel_addr} ${kernel_sector} ${kernel_block_cnt}; then echo "Read uInitrd from EMMC";if mmc read ${initrd_addr} ${initrd_sector} ${initrd_block_cnt}; then echo "Read FDT from EMMC";if mmc read ${dtb_addr} ${dtb_sector} ${dtb_block_cnt}; then run addmac;echo "Start booting system...";run boot_start;fi;fi;fi;fi
