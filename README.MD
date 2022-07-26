На текущей странице описано как я перенес armbian на emmc и загружаюсь с нее без SD/USB HDD/SSD.

У меня устройтво на старом Amlogic s905 (самый первый из серии 905): ***Thronsmart Vega S95 Meta 2 Gb RAM, 8 Gb ROM***.

У него на борту **EMMC** размером 8 Gb, на самом деле 7,2 Gb
```
Disk /dev/mmcblk2: 7,28 GiB, 7818182656 bytes, 15269888 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
```

Все существующие сборки armbian не умеют загружаться с **emmc** на Amlogic s905.

Если вы запустите скрипт **armbian-install.sh**, то вы окирпичите свой девайс. Из кирпича девайс вывести не сложно с помощью прошивки android и USB Burning Tool.

Более того, если загрузиться в SD/USB, то реальные разделы с EMMC (обычно это /dev/mmcblk2) не будет видно.

На EMMC нет как таковой талицы разделов в привычном нам понимании.

В самом начале EMMC располагается bootloader, далее разделы, которые созданы прошивкой android.
```
Partition table get from SPL is :
        name                        offset              size              flag
================================================================================                                                                        
   0: bootloader                         0            400000                  0		4Mb
   1: reserved                     2400000           4000000                  0		смещение на 36 Mb и размер 64 Mb         таблица разделов? 
   2: cache                        6c00000          20000000                  2   смещение на 108 Mb и размер 512 Mb			
   3: env                         27400000            800000                  0   смещение на 628 Mb и размер 8 Mb 			uBoot env   если стереть, то перезаписывается
   4: logo                        28400000           2000000                  1   смещение на 644 Mb и размер 32 Mb 			
   5: recovery                    2ac00000           2000000                  1   смещение на 684 Mb и размер 32 Mb       		
   6: rsv                         2d400000            800000                  1 	смещение на 724 Mb и размер 8 Mb		пустой
   7: tee                         2e400000            800000                  1		смещение на 740 Mb и размер 8 Mb         пустой
   8: crypt                       2f400000           2000000                  1		смещение на 756 Mb и размер 32 Mb		пустой? 
   9: misc                        31c00000           2000000                  1		смещение на 796 Mb и размер 32 Mb   пустой   используется recovery?
  10: instaboot                   34400000          20000000                  1		смещение на 836 Mb и размер 512 Mb   пустой
  11: boot                        54c00000           2000000                  1		смещение на 1356 Mb и размер 32 Mb
  12: system                      57400000          60000000                  1		смещение на 1396 Mb и размер 1536 Mb
  13: data                        b7c00000         11a400000                  4		смещение на 2940 Mb и размер 4516 Mb		
```  
Описание структуры таблицы: 
https://github.com/laris/Phicomm-N1/blob/master/refs/partition-table-format-of-phicomm-n1.md
https://github.com/codesnake/uboot-amlogic/blob/master/include/emmc_partitions.h

EMMC это блочное устройство для встраиваемых систем. Чтобы дать возможность ядру понять какие разделы есть на EMMC, нужно воспользоваться параметром ядра **blkdevparts** (https://github.com/so61pi/examples/blob/master/linux-blkdevparts/readme.md)
Ядро должно быть собрано с такой опцией.
В armdian от balbes150 в ядре включена такая опция.
В armbian от ophub (https://github.com/ophub/amlogic-s9xxx-armbian) такая опция выключена.
Чтобы ее включить, надо пересобрать ядро с поддержкой **blkdevparts** (**CONFIG_CMDLINE_PARTITION=Y**) 
https://github.com/ophub/amlogic-s9xxx-armbian/tree/main/compile-kernel

PS как пересобирать ядро, пока писать не буду. Делал это всего лишь один раз по инструкции выше и все получилось.

Как только ядро получит поддержку **blkdevparts**, мы сможем указать ядру, какие разделы есть на EMMC.

Собранные kernel и ramdisk можно взять здесь [d51x/armbian-s905/tree/main/emmc_install/files](http://github.com/d51x/armbian-s905/tree/main/emmc_install/files "d51x/armbian-s905/tree/main/emmc_install/files")

* kernel - vmlinuz-5.15.55-ophub.7z (распаковать)
* ramdisk - uInitrd-5.15.55-ophub

Это делает в файле uEnv.txt в параметре APPEND.
Нужно добавить следующее
```
blkdevparts=mmcblk2:512M@108M(cache),-M@644M(rootfs)
```
нам нужны только эти разделы для дальнейшей работы.

Добавьте это в uEnv.txt и перезагрузитесь.

Раздел **rootfs** (это название я дал просто так, оно ничего не значит) будет использоваться как ROOT_FS. Это область на emmc, которая будет начинаться сразу после раздела env и до конца всего emmc. 
Раздел **cache** мы будем использовать как BOOT-раздел, но не в прямом смысле, а просто будем понимать, что это область на emmc, где будет располагаться kernel, initrd, uEnv.txt и dtb файл для вашего устройства.

Если вы сейчас загрузитесь, то команда lsblk отобразит разделы с emmc, которые мы прописали.
```
root@VegaS95:/mnt# lsblk
NAME         MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
sda            8:0    0 111,8G  0 disk
├─sda1         8:1    0   255M  0 part /boot
└─sda2         8:2    0 111,5G  0 part /
mmcblk2      179:0    0   7,3G  0 disk
├─mmcblk2p1  179:1    0   512M  0 part              cache
└─mmcblk2p2  179:2    0   6,7G  0 part              rootfs
mmcblk2boot0 179:32   0     4M  1 disk
mmcblk2boot1 179:64   0     4M  1 disk

```
Но пока что мы не сможем их примонтировать, потому что там неизвестные файловые системы.

PS если научиться переделывать таблицу разделов, которая находится в **reserved**, то можно раздел env поместить перед cache (целых 512 Mb), тем самым увеличить доступное место для наших нужд. Сейчас cache 512 Mb, но используем мы от силы 50 Mb.

Стереть все после раздела env можно командой
```
dd if=/dev/zero of=/dev/mmcblk2 bs=1M seek=644 count=6812
```
Это достигается тем, что мы отступаем от начала emmc на 644 блока каждый по 1M и затираем нулями все место размером 6812 блоков. 
Если у вас другой размер emmc, то нужно делать вычисления новых размеров как в этой команде, так и далее.

После того, как мы очистили все ненужно от android прошивки, приступаем к формированияю файловой системы на emmc.

1. mmcblk2p1 мы форматировать не будем, а данные будем записать как raw-данные через dd.

2. mmcblk2p2 мы отформатируем в ext4.


Форматируем rootfs:
```
ROOTFS_UUID="$(cat /proc/sys/kernel/random/uuid)"     # он нам особо то и не нужен, потому что мы будем по пути устройства к нему обращаться
mkfs.ext4 -F -q -U ${ROOTFS_UUID} -L "ROOTFS_EMMC" /dev/mmcblk2p2
```
Теперь монтируем новый раздел с emmc в папку /mnt/p2
```
mkdir /mnt/p2
mount -t ext4 /dev/mmcblk2p2 /mnt/p2
```

Создаем начальную структуру папок раздела
```
mkdir -p /mnt/p2/{boot/,dev/,media/,mnt/,proc/,run/,sys/} && sync
```
Далее копируем папки etc, home, lib64, opt, root, selinux, srv, usr, var с того устройства (SD/USB Flash/HDD/SSD), с которого загрузились.

Копируем командой
```    COPY_SRC="etc home lib64 opt root selinux srv usr var"
    for src in ${COPY_SRC}; do
        echo -e "$Copy the [ ${src} ] directory."
        tar -cf - ${src} | (
            cd /mnt/p2
            tar -xf -
        )
        sync
    done
```
Далее создаем симлинки
```
    ln -sf /usr/bin ${DIR_INSTALL}/bin
    ln -sf /usr/lib ${DIR_INSTALL}/lib
    ln -sf /usr/sbin ${DIR_INSTALL}/sbin
    ln -sf /var/tmp ${DIR_INSTALL}/tmp
    sync
```
Теперь нам надо скорректировать файл fstab.
Его содержимое будет таким
```
/dev/mmcblk2p2  /        ext4     defaults,noatime,errors=remount-ro     0 1
tmpfs                /tmp     tmpfs                   defaults,nosuid           0 0
```
К нашему корневому разделу на emmc можно обращаться как по пути /dev/mmcblk2p2, так и по UUID (ранее генерировали его).

Корневая система на emmc готова.

Далее самое сложное, это формирование BOOTFS в разделе /dev/mmcblk2p1

Сейчас u-boot делает так, если нет загрузочных SD/USB устройств, то он пытается загрузить систему из emmc. В env u-boot (вроде как приехала из aml_autoscript, который мы прошиваем, чтобы сделать multi-boot) есть такая строка
```
setenv start_emmc_autoscript 'if fatload mmc 1 1020000 emmc_autoscript; then autoscr 1020000; fi;'
```
Вот она и запускается командой ***run start_emmc_autoscript***, но ничего не происходит, потому что emmc не имеет таблицы разделов и ***fatload*** не отрабатывает.
Чтобы все это заработало, надо вместо ***fatload*** использовать команду ***mmc read***.

Т.е. нам надо загрузиться в u-boot и выполнить команду
```
setenv start_emmc_autoscript 'echo "Set mmc dev to 1"; mmc dev 1; sleep 3; echo "mmc read"; if mmc read 1020000 36000 3; then echo "start autoscript"; autoscr 1020000;fi;'
printenv start_emmc_autoscript;
saveenv;
```

Тем самым мы изменим команду загрузки с emmc и сохраним env, чтобы он уже применялся при каждой загрузке устройства.

В этой команде есть магические числа 36000 и 3.

***36000*** - это адрес блока на emmc, откуда будет загружаться ***emmc_autoscript***. Мы помним, что под BOOTFS мы используем раздел ***cache***, которые начинается с адреса ***0x6c00000***. Это hex, int это 113246208. Так как мы оперируем блоками по 512 байт, то это значение надо поделить на 512. Получим 221 184 или в hex ***0x36000***.

3 - это размер блоков, которые занимает файл. Этот файл, вернее мы сделаем свой emmc2_autoscript, занимает, скажем, 1306 байт, соответсвенно, в блоках по 512 байт он займет 3 блока.

Теперь u-boot теоретически может загрузить с emmc файл emmc2_autoscript и передать ему управление.

Почему теоретически, потому что его надо создать и записать на emmc.

Создадим файл ***emmc2_autoscript.cmd***:
```
echo "Select EMMC"
mmc dev 1
sleep 3
echo "Set env variables"
setenv dtb_addr 0x1000000
setenv dtb_sector 0x36003
setenv dtb_block_cnt 0x4A
setenv env_addr 0x1040000
setenv env_sector 0x3604D
setenv env_block_cnt 0x2
setenv env_size 491
setenv kernel_addr 0x11000000
setenv kernel_sector 0x3604F
setenv kernel_block_cnt 0xCA45
setenv initrd_addr 0x13000000
setenv initrd_sector 0x42A94
setenv initrd_block_cnt 0x5FCB
setenv boot_start booti ${kernel_addr} ${initrd_addr} ${dtb_addr}
setenv addmac 'if printenv mac; then setenv bootargs ${bootargs} mac=${mac}; elif printenv eth_mac; then setenv bootargs ${bootargs} mac=${eth_mac}; elif printenv ethaddr; then setenv bootargs ${bootargs} mac=${ethaddr}; fi'

echo "Read mmc partitions"
echo "Read uEnv2.txt from EMMC"
if mmc read ${env_addr} ${env_sector} ${env_block_cnt}; then env import -t ${env_addr} ${env_size};setenv bootargs ${APPEND};printenv bootargs;echo "Read zImage from EMMC";if mmc read ${kernel_addr} ${kernel_sector} ${kernel_block_cnt}; then echo "Read uInitrd from EMMC";if mmc read ${initrd_addr} ${initrd_sector} ${initrd_block_cnt}; then echo "Read FTD from EMMC";if mmc read ${dtb_addr} ${dtb_sector} ${dtb_block_cnt}; then run addmac;echo "Start bootin system...";run boot_start;fi;fi;fi;fi
```

В этом файле необходимо КОРРЕКТНО прописать значения для
1. dtb_sector - в hex номер сектора, куда будет загружаться dtb файл на emmc
2. dtb_block_cnt - в hex сколько блоков займет файл
3. env_sector - в hex номер сектора, куда будет загружаться uEnv.txt файл на emmc
4. env_block_cnt - в hex сколько блоков займет файл
5. env_size - размер uEnv.txt файла в десятичном формате
6. kernel_sector - в hex номер сектора, куда будет загружаться zImage файл ядра на emmc
7. kernel_block_cnt - в hex сколько блоков займет файл
8. initrd_addr - в hex номер сектора, куда будет загружаться uInitrs файл ramdisk'a на emmc
9. initrd_block_cnt - в hex сколько блоков займет файл

Самое сложное это все просчитать и корректно записать.

Загружаем поочередно файлы emmc2_autoscript, dtb, uEnv, kernel, ramdisk.

1. У нас есть файл emmc2_autoscript.cmd - это скрипт и из него надо сгенерировать файл в формате image, чтобы u-boot его понял
```
mkimage -C none -A arm -T script -d /boot/emmc2_autoscript.cmd /boot/emmc2_autoscript
```
Теперь у нас есть emmc2_autoscript, который поймет u-boot. Загрузим его в emmc, тут все просто, потому что он грузится в самое начало раздела BOOTFS:
```
dd if=/boot/emmc2_autoscript of=/dev/mmcblk2p1 bs=512
```

2. Грузим файл dtb. Тут уже сложнее, нам надо вычислить смещение на разделе, куда писать файл. Имеено эти значения мы подставляем в dtb_sector и dtb_block_cnt
```
dd if=/boot/dtb/amlogic/meson-gxbb-vega-s95-meta.dtb of=/dev/mmcblk2p1 bs=512 seek=3
```
seek=3 - отступаем 3 блока от начала раздела, потому что эти 3 блока занимает файл emmc2_autoscript

3. Грузим файл uEnv.txt. На самом деле лучше сделать копию файла uEnv.txt, скажем uEnv_emmc.txt, в котором мы должны заменить root=UUID=61fc7a35-...... на root=/dev/mmcblk2p2, либо можно как здесь, так и в fstab прописать UUID, который генерили на всякий случай

```
dd if=/boot/uEnv_emmc.txt of=/dev/mmcblk2p1 bs=512 seek=77
```
seek=77 - потому что отступаем от начала раздела 3 блока (emmc2_autoscript) + 74 блока (dtb файл). На самом деле может быть и не 74 блока, нужно размер файла разделить на 512 и округлить в большую сторону.

4. Грузим kernel
```
dd if=/boot/vmlinuz-5.15.55-ophub of=/dev/mmcblk2p1 bs=512 seek=79	
```
seek=79 - ну вы поняли - 3 блока (emmc2_autoscript) + 74 блока (dtb файл) + 2 блока (uEnv файл). Или не 2 блока, а сколько получиться при вычислении.

5. Грузим ramdisk
```
dd if=/boot/uInitrd-5.15.55-ophub of=/dev/mmcblk2p3 bs=512 seek=51860
```
seek=51860 - догадайтесь сами, почему )))

На этом формирование BOOT_FS завершено.

Теперь вытаскиваем все загрузочные SD / USB устройства из приставки. 

Передергиванием питание.

Если мы уже правили env start_emmc_autoscript и сохранили в env, то приставка теперь уже должна грузиться с emmc.

Если не правили, то самое время отмотать назад и поправить.

Все что здесь описано, это проведенные исследования проблемы загрузки s905 с emmc.
Основная ифнормация была почерпнута из темы https://forum.armbian.com/topic/18902-s905-failed-to-boot-from-emmc/

Очень помогли посты товарищей @pista и @hexdump, а так же скрипт armbian-install

PS если вдруг не происходит загрузка с emmc и система вываливается в u-boot, то надо проверить переменную start_emmc_autoscript и скорректировать при необходимости.

PSS работу скрипта s905-install-emmc.sh проверил на своем устройстве несколько раз перенося данные как с SD карточки, так и с USB SSD, на которых были установлены системы.

PSSS Если скрипт отработал, но система не грузится с emmc, то нужно тогда пробовать выполнять команды вручную.

--------------------------

Чтобы обновить ядро, dtb или просто изменить параметры cmdline, сделал упрощенный скрипт s905-install-emmc_only_update_bootfs.sh.

Он только обновляет псевдо BOOTFS на emmc.

Чтобы им воспользоваться на уже установленной системе в emmc надо создать в корне /dev/mmcblk2p2 папку /boot.

В нее положить минимальный набор файлов:

* сам скрипт s905-install-emmc_only_update_bootfs.sh
* uEnv.txt и uEnv_emmc.txt
* файл kernel - с таким именем, которое указано в uEnv.txt в параметре LINUX
* файл initrd - с таким именем, которое указано в uEnv.txt в параметре INITRD
* файд dtb - с таким именем, которое указано в uEnv.txt в параметре FDT

Запустить скрипт sudo /bin/bash /boot/s905-install-emmc_only_update_bootfs.sh.

Подождать выполнения.

Передернуть питание.


------------

### Дополнение 1

Нет необходимости занулять разделы командой dd if=/dev/zero, т.к. все равно в псевдо BOOT раздел файлы загружаются через dd, а раздел ext4 форматируется.

Это существенно позволило уменьшить время работы скрипта по переносу.

### Дополнение 2

Удалось увеличить размер раздела rootfs примерно на 500 Mb, теперь он имеет размер 7.2 Gb.
Теперь почти вся eMMC в нашем распоряжении.
```
@armbian:~$ lsblk
NAME         MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
mmcblk2      179:0    0  7,3G  0 disk
└─mmcblk2p1  179:1    0  7,2G  0 part /var/log.hdd
```
Этого удалось достичь не изменением структуры разделов ([здесь](https://github.com/d51x/armbian-s905/tree/main/docs/s905-resize-partitions.txt "здесь") я пытался это описать и воспроизвести), а следующим методом:
- файлы emmc_autoscript, uEnv, dtb и kernel я поместил в свободную область между разделами bootloader и reserved. Там свободно 32 Mb.
- файл initrd я поместил в выделенную зону (16 Mb) после раздела reserved
- все остальное место, начиная со 116Mb от начала и до конца eMMC выделено под ext4 раздел rootfs
- раздел env остался не тронутым, хотя и лежит внутри области rootfs, но при форматировании rootfs мы указываем, что он имеет badblocks начиная с 0x27400000 от начала eMMC (или 512 Mb от начала раздела rootfs)
```
mke2fs -F -q -O ^64bit -t ext4 -m 0 /dev/mmcblk2p1 -b 4096 -l /tmp/reservedblks -L "ROOTFS_EMMC" > /dev/null
```
/tmp/reservedblks - файл, который содержит номера секторов бед блоков, которые относятся к env разделу

Информацию нашел здесь https://github.com/laris/Phicomm-N1/blob/master/refs/use-single-partition-to-boot-linux-on-phicomm-n1.md

На основании этого сделал новый скрипт переноса на emmc - [s905-install-emmc.sh](https://github.com/d51x/armbian-s905/tree/main/emmc_install/v2 "s905-install-emmc.sh")

