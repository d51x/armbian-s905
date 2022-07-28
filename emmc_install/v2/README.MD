В данной директории располагаются скрипты и необходимые файлы, чтобы максимально использовать весь объем eMMC под раздел ROOTFS

### Список файлов
- aml_autoscript.zip - копируется на SD/USB, его подгружает u-Boot и обновляет переменные окружения, в частности, в этом архиве лежит измененный под наши нужды aml_autoscript
- aml_autoscript - сам измененный aml_autoscript, собранный из aml_autoscript.cmd
- aml_autoscript.cmd - основное отличие от оригинального файла в том, что он делал так 
```
setenv start_emmc_autoscript 'if fatload mmc 1 1020000 emmc_autoscript; then autoscr 1020000; fi;'
```
а мы делаем так, чтобы подгрузить файл не из файловой системы с emmc (т.к. наш u-Boot это не умеет), а подгрузить файл в память напрямую читая указанную олбласть eMMC
```
setenv start_emmc_autoscript 'mmc dev 1; sleep 3; if mmc read 1020000 2000 3; then autoscr 1020000;fi'
```

- aml_autoscript_emmc и aml_autoscript_emmc.cmd - из этих файлов как раз и сделаны копии aml_autoscript и aml_autoscript.cmd, на случай если последние перезатрете оригинальными

- s905-install-emmc.sh - сам скрипт переноса
- s905-kernel-update-emmc.sh - скрипт обновления ядра на установленной в emmc системе
- uEnv.txt модифицированный под наши нужды, в частности, чтобы был доступен раздел rootfs, который начинается со смещения 116 Мб от начала eMMC
```
blkdevparts=mmcblk2:-@116M(rootfs)
```
Этот файл нужен для первоначальной загрузки с SD/USB, чтобы раздел был доступен, и чтобы скрипт переноса отработал корректно

- uEnv_emmc.txt - этот файл уже будет использоваться для загрузки с eMMC

### Как сделать перенос
1. подготавливаем SD/USB флешку с armbian (версия [ophub](https://github.com/ophub/amlogic-s9xxx-armbian "ophub"))
2. копируем на флешку (раздел BOOT) файлы:
	- aml_autoscript
	- aml_autoscript.zip
	- s905-install-emmc.sh
	- uEnv.txt 
		- либо копируем файл и в нем заменяем UUID на значение из оригинального файла uEnv.txt
		- либо в оригинальном файле в APPEND дописываем ***'blkdevparts=mmcblk2:-@116M(rootfs)'*** после ***rootfstype=ext4***
	- uEnv_emmc.txt
	- [uInitrd-5.15.55-ophub](https://github.com/d51x/armbian-s905/tree/main/emmc_install/files "uInitrd-5.15.55-ophub")
	- [vmlinuz-5.15.55-ophub.7z](https://github.com/d51x/armbian-s905/tree/main/emmc_install/files "vmlinuz-5.15.55-ophub.7z") (необходимо распаковать архив)
3. вставляем SD/USB флешку в приставку и загружаемся
4. выполняем команду
	```
	sudo /bin/bash /boot/s905-install-emmc.sh
	```
	Результат работы скрипта
```
[ SUCCESS ] Start install armbian to emmc...
[ SUCCESS ] Script version: 2.1
[ STEPS ] preparing pseudo-BOOT partition in EMMC
[ INFO ] Compile new emmc_autoscript
[ INFO ] Copy /boot/emmc2_autoscript to pseudo-BOOT partition:   seek=8192       size=1433
[ INFO ] Copy /boot/dtb/amlogic/meson-gxbb-vega-s95-meta.dtb to pseudo-BOOT partition:   seek=8195       size=37433
[ INFO ] Copy /boot/uEnv_emmc.txt to pseudo-BOOT partition:      seek=8269       size=416
[ INFO ] Copy /boot/vmlinuz-5.15.55-ophub to pseudo-BOOT partition:      seek=8270       size=26511872
[ INFO ] Copy /boot/uInitrd-5.15.55-ophub to pseudo-BOOT partition:      seek=237568     size=12555379
[ INFO ] DONE. BOOTFS was copied to EMMC
[ STEPS ] Creating ROOTFS patition...
[ INFO ] reserving env-partition blocks
[ STEPS ] formating ROOTFS patition
Warning: the backup superblock/group descriptors at block 131072 contain bad blocks.
[ STEPS ] copying ROOTFS to EMMC
[ INFO ] Copy the [ etc ] directory.
[ INFO ] Copy the [ home ] directory.
[ INFO ] Copy the [ lib64 ] directory.
[ INFO ] Copy the [ opt ] directory.
[ INFO ] Copy the [ root ] directory.
[ INFO ] Copy the [ selinux ] directory.
[ INFO ] Copy the [ srv ] directory.
[ INFO ] Copy the [ usr ] directory.
[ INFO ] Copy the [ var ] directory.
[ INFO ] Generate the new fstab file.
[ INFO ] DONE. ROOTFS was copied to EMMC
[ SUCCESS ] Successful installed, please unplug the USB, re-insert the power supply to start the armbian.
```
5. По завершению работы скрипта флешку не вытаскиваем, передергиваем питание, грузимся еще раз с флешки и не более
6. Теперь вынимаем флешку и передергиваем питание
7. Должен грузиться armbian с eMMC

### Как обновить ядро

Для обновления ядра нам понадобятся только 3 файла - архив файла ядра, uEnv.txt и скрипт обновления

1. Скачиваем архив файла ядра [5.15.15.tar.gz](https://disk.yandex.ru/d/ZirpowaNMBTiEA "5.15.15.tar.gz") и копируем файл в папку /boot на eMMC.

	Его содержимое
	```
	5.15.15/
		boot-5.15.15-d51x.tar.gz
			config-5.15.15-d51x (нас не интересует)
			initrd.img-5.15.15-d51x (нас не интересует)
			System.map-5.15.15-d51x (нас не интересует)
			uInitrd-5.15.15-d51x (ramdisk копируется в /boot) 
			vmlinuz-5.15.15-d51x (kernel копируется в /boot)
		dtb-allwinner-5.15.15-d51x.tar.gz (нас не интересует)
		dtb-amlogic-5.15.15-d51x.tar.gz  (набор dtb-файлов, копируется в /boot/dtb/amlogic)
		dtb-rockchip-5.15.15-d51x.tar.gz (нас не интересует)
		header-5.15.15-d51x.tar.gz (нас не интересует)
		modules-5.15.15-d51x.tar.gz  (модули ядра, копируются в /usr/lib/modules)
		sha256sums
	```
2. Копируем скрипт s905-kernel-update-emmc.sh в /boot
3. Копируем uEnv.txt (должен сожержать опцию blkdevparts) в /boot.
	Файл можно взять оригинальный, который использовался при запуске с SD карты. Скрипт обновления ядра автоматически на его основе создаст файл eEnv_emmc.txt и пропишет новые имена файлов для kernel и initrd, а так же в bootargs заменит UUID на путь /dev/mmcblk2p1
4. Запускаем скрипт ./s905-kernel-update-emmc.sh и ждем результаты вполнения
	```
	root@VegaS95:/boot# ./s905-kernel-update-emmc.sh
	[ SUCCESS ] Start install new kernel to emmc...
	[ SUCCESS ] Script version: 2.1

	[ STEPS ] 1/4 Select from available kernels:
	1. 5.15.15.tar.gz
	2. 5.15.17.tar.gz
	or 3 for exit
	Select number: 1
	[ INFO ] selected kernel: 5.15.15.tar.gz
	[ STEPS ] 2/4 Start unpacking the kernel [ 5.15.15.tar.gz ] ...
	[ INFO ] removing previous kernels...
	[ INFO ] unpacking kernel 5.15.15
	[ INFO ] unpacking boot-5.15.15-d51x.tar.gz done.
	[ INFO ] unpacking modules-5.15.15-d51x.tar.gz done.
	[ INFO ] unpucking dtb-amlogic-5.15.15-d51x.tar.gz done
	[ STEPS ] 3/4 Creating uEnv_emmc.txt file...
	[ INFO ] creating uEnv_emmc.txt done.
	[ STEPS ] 4/4 Preparing pseudo-BOOT partition in EMMC
	[ INFO ] compiling new emmc_autoscript done.
	[ INFO ] copy /boot/emmc2_autoscript [seek=8192, size=1433]
	[ INFO ] copy /boot/dtb/amlogic/meson-gxbb-vega-s95-meta.dtb [seek=8195, size=37433]
	[ INFO ] copy /boot/uEnv_emmc.txt [seek=8269, size=400]
	[ INFO ] copy /boot/vmlinuz-5.15.15-d51x [seek=8270, size=26511872]
	[ INFO ] copy /boot/uInitrd-5.15.15-d51x [seek=204800, size=7522635]
	[ INFO ] preparing pseudo-BOOT partition DONE
	[ FINISH ] Successful installed, please unplug the USB, re-insert the power supply to start the armbian.
	root@VegaS95:/boot# reboot
	```