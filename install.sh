#!/bin/sh

OCVER=$(curl --silent -qI https://github.com/acidanthera/OpenCorePkg/releases/latest | awk -F '/' '/^location/ {print  substr($NF, 1, length($NF)-1)}');

echo 'Welcome!'
echo 'This script will create an EFI for OpenCore that can be used exclusively for Linux and Windows booting. It cannot be used for hackintoshing or booting macOS. For that purpose, the official install guide at https://dortania.github.io/OpenCore-Install-Guide/ should be used instead.'
printf 'Use DEBUG version of OpenCore? (y/N) '
read answer

if [ "$answer" != "${answer#[Yy]}" ]; then
	BUILD=DEBUG
else
	BUILD=RELEASE
fi
echo 'Cleaning leftover files...'
rm -rf OpenCore OpenCore-$OCVER-$BUILD.zip
echo 'Downloading the latest release of OpenCore...'
mkdir OpenCore
wget -q https://github.com/acidanthera/OpenCorePkg/releases/download/$OCVER/OpenCore-$OCVER-$BUILD.zip
unzip -qq OpenCore-$OCVER-$BUILD.zip -d OpenCore
printf 'Is your EFI architecture IA32, or 32 bit? (If in doubt, select no) (y/N) '
read answer

if [ "$answer" != "${answer#[Yy]}" ]; then
	ARCH=IA32
else
	ARCH=X64
fi
echo 'Copying config.plist...'
cp configs/config.plist OpenCore/$ARCH/EFI/OC/config.plist
echo 'Removing unneeded drivers...'
find OpenCore/$ARCH/EFI/OC/Drivers/* ! -name 'OpenRuntime.efi' ! -name 'OpenLinuxBoot.efi' ! -name 'OpenCanopy.efi' ! -name 'Ext4Dxe.efi' -exec rm -f {} +
echo 'Removing unneeded tools...'
rm -f OpenCore/$ARCH/EFI/OC/Tools/*
echo 'Setting up a theme for OpenCanopy'
cp -r OcBinaryData/Resources/ OpenCore/$ARCH/EFI/OC/
printf 'What filesystem is your /boot partition on? (ext4, btrfs, etc.): '
read answer
answer=$(echo "$answer" | awk '{print tolower($0)}')

if [ "$answer" != "ext4" ]; then
	echo 'Getting filesystem driver...'
	rm OpenCore/$ARCH/EFI/OC/Drivers/Ext4Dxe.efi
	wget -q https://github.com/pbatard/EfiFs/releases/latest/download/$answer\_$ARCH.efi || { 
	echo 'Failed to get filesystem driver! Maybe it is not supported yet. If you think it is supported, try opening an issue.'; exit 
	}
	echo 'Moving filesystem driver...'
	mv $answer\_$ARCH.efi OpenCore/$ARCH/EFI/OC/Drivers/
	echo 'Copying changes to config.plist...'
	sed -i 's/<string>Ext4Dxe.efi<\/string>/<string>$answer<\/string>/' OpenCore/$ARCH/EFI/OC/config.plist
fi

printf 'Where should OpenCore be installed? (example: /boot/efi, /efi, your USB drive, etc.) '
read answer

cp -r OpenCore/$ARCH/EFI/* $answer/EFI/

echo 'Done!'
