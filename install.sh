#!/bin/sh

OCVER=$(curl --silent -qI https://github.com/acidanthera/OpenCorePkg/releases/latest | awk -F '/' '/^location/ {print  substr($NF, 1, length($NF)-1)}');

echo "Welcome!"
echo "This script will create an EFI for OpenCore that can be used exclusively for Linux and Windows booting. It cannot be used for hackintoshing or booting macOS. For that purpose, the official install guide at https://dortania.github.io/OpenCore-Install-Guide/ should be used instead."
printf '%s' "Use DEBUG version of OpenCore? (Disable GUI, log to file and screen, dump ACPI and system info to partition) (y/N) "
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
printf '%s' "Is your EFI architecture IA32, or 32 bit? (If in doubt, select no) (y/N) "
read answer

if [ "$answer" != "${answer#[Yy]}" ]; then
	ARCH=IA32
else
	ARCH=X64
fi

OCPATH=OpenCore/$ARCH/EFI/OC

echo "Removing unneeded drivers..."
find $OCPATH/Drivers/* ! -name 'OpenRuntime.efi' ! -name 'OpenLinuxBoot.efi' ! -name 'OpenCanopy.efi' ! -name 'Ext4Dxe.efi' -exec rm -f {} +
echo "Removing unneeded tools..."
rm -f $OCPATH/Tools/*
echo "Setting up a theme for OpenCanopy"
cp -r OcBinaryData/Resources/ $OCPATH/
printf '%s' "What filesystem is your /boot partition on? (ext4, btrfs, etc.): "
read answer
answer=$(echo "$answer" | awk '{print tolower($0)}')

if [ "$answer" != "ext4" ] && [ "$answer" != "" ]; then
	echo 'Getting filesystem driver...'
	rm $OCPATH/Drivers/Ext4Dxe.efi
	wget -q https://github.com/pbatard/EfiFs/releases/latest/download/$answer\_$ARCH.efi || { 
	echo "Failed to get filesystem driver! Maybe it is not supported yet. If you think it is supported, try opening an issue."; exit 
	}
	echo "Moving filesystem driver..."
	mv $answer\_$ARCH.efi $OCPATH/Drivers/
	echo "Copying changes to config.plist..."
	sed "s|<string>Ext4Dxe.efi</string>|<string>$answer\_$ARCH.efi</string>|" configs/config$BUILD.plist 1> $OCPATH/config.plist
	echo "Using $answer as filesystem"
else
	cp configs/config$BUILD.plist $OCPATH/config.plist
	echo "Using ext4 as filesystem"
fi

printf '%s' "Add a picker password to OpenCore? (y/N) "
read answer

if [ "$answer" != "${answer#[Yy]}" ]; then
	mv $OCPATH/config.plist $OCPATH/temp.plist
	printf '%s\n' "Enter password:"
	passwordFields=$(OpenCore/Utilities/ocpasswordgen/ocpasswordgen.linux)
	passwordHash=$(echo $passwordFields | awk -F'[<>]' '{print $2}' | xxd -r -p | base64 -w 0)
	passwordSalt=$(echo $passwordFields | awk -F'[<>]' '{print $4}' | xxd -r -p | base64 -w 0)
	awk -v hash="$passwordHash" '/<key>PasswordHash<\/key>/ {print; getline; print "\t\t\t<data>" hash "</data>"; next} 1' $OCPATH/temp.plist | awk -v salt="$passwordSalt" '/<key>PasswordSalt<\/key>/ {print; getline; print "\t\t\t<data>" salt "</data>"; next} 1' | awk '/<key>EnablePassword<\/key>/ {print; getline; print "\t\t\t<true/>"; next} 1' 1> $OCPATH/config.plist
	rm $OCPATH/temp.plist
fi

printf '%s' 'Vault configuration? (Prevents changes from being made to configuration) (y/N) '
read answer

if [ "$answer" != "${answer#[Yy]}" ]; then
	echo 'Requiring secure vault in config.plist'
	mv $OCPATH/config.plist $OCPATH/temp.plist
	awk '/<key>Vault<\/key>/ {print; getline; print "\t\t\t<string>Secure</string>"; next} 1' $OCPATH/temp.plist 1> $OCPATH/config.plist
	rm $OCPATH/temp.plist
	echo 'Downloading OpenCore Source...'
	wget -q https://github.com/acidanthera/OpenCorePkg/archive/refs/tags/$OCVER.zip
	unzip -qq $OCVER.zip
	mv OpenCorePkg-$OCVER OpenCorePkg
	rm $OCVER.zip
	echo 'Compiling RsaTool...'
	cd OpenCorePkg/Utilities/RsaTool && make && cd ../../../
	echo 'Copying RsaTool to OpenCore...'
	cp OpenCorePkg/Utilities/RsaTool/RsaTool OpenCore/Utilities/CreateVault
	rm -rf OpenCorePkg
	echo 'Vaulting OpenCore...'
	OpenCore/Utilities/CreateVault/sign.command "$(pwd -P)"/$OCPATH
fi

printf '%s' "Where should OpenCore be installed? (example: /boot/efi, /efi, your USB drive, etc.) "
read answer
if [ "$answer" = "" ]; then
	echo 'No directory specified!'
	exit
elif [ ! -d "$answer" ]; then
	echo 'Directory does not exist!'
	exit
fi

cp -r OpenCore/$ARCH/* $answer/ || echo 'Failed to copy OpenCore to selected directory!'

echo 'Done!'
