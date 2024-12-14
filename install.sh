#!/bin/sh

sign_file() {
	file="$1"
	echo "Signing $file (enter your passphrase)"
	while true; do
		sbsign --key $KEYS/ISK.key --cert $KEYS/ISK.pem $file --output $file 2> /dev/null
		if [ "$?" != 0 ]; then
			echo 'Sorry, try again'
		else
			break
		fi
	done
}
find_replace_config() {
	mv $OCPATH/config.plist $OCPATH/temp.plist
	awk -v findkey="$1" -v replacevalue="$2" '$0 ~ "<key>" findkey "<\/key>" {print; getline; print "\t\t\t" replacevalue; next} 1' "$OCPATH/temp.plist" > "$OCPATH/config.plist" 2> /dev/null
	rm $OCPATH/temp.plist
}

OCVER=$(curl --silent -qI https://github.com/acidanthera/OpenCorePkg/releases/latest | awk -F '/' '/^location/ {print  substr($NF, 1, length($NF)-1)}');
SCRIPTDIR="$(pwd -P)"

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
rm -rf $SCRIPTDIR/OpenCore
echo 'Downloading the latest release of OpenCore...'
mkdir $SCRIPTDIR/OpenCore
curl -Lso OpenCore.zip https://github.com/acidanthera/OpenCorePkg/releases/download/$OCVER/OpenCore-$OCVER-$BUILD.zip
unzip -qq OpenCore.zip -d $SCRIPTDIR/OpenCore && rm OpenCore.zip
printf '%s' "Is your EFI architecture IA32, or 32 bit? (If in doubt, select no) (y/N) "
read answer

if [ "$answer" != "${answer#[Yy]}" ]; then
	ARCH=IA32
else
	ARCH=X64
fi

OCPATH=$SCRIPTDIR/OpenCore/$ARCH/EFI/OC
OCUTILS=$SCRIPTDIR/OpenCore/Utilities

echo "Removing unneeded drivers..."
find $OCPATH/Drivers/* ! -name 'OpenRuntime.efi' ! -name 'OpenLinuxBoot.efi' ! -name 'OpenCanopy.efi' ! -name 'Ext4Dxe.efi' -exec rm -f {} +
echo "Removing unneeded tools..."
rm -f $OCPATH/Tools/*
echo "Setting up a theme for OpenCanopy"
cp -r $SCRIPTDIR/OcBinaryData/Resources/ $OCPATH/
printf '%s' "What filesystem is your /boot partition on? (ext4, btrfs, etc.): "
read answer
answer=$(echo "$answer" | awk '{print tolower($0)}')

if [ "$answer" != "ext4" ] && [ "$answer" != "" ]; then
	echo 'Getting filesystem driver...'
	rm $OCPATH/Drivers/Ext4Dxe.efi
	wget -qO $OCPATH/Drivers/$answer\_$ARCH.efi https://github.com/pbatard/EfiFs/releases/latest/download/$answer\_$ARCH.efi || { 
	echo "Failed to get filesystem driver! Maybe it is not supported yet. If you think it is supported, try opening an issue."; exit 
	}
	echo "Copying changes to config.plist..."
	sed "s|<string>Ext4Dxe.efi</string>|<string>$answer\_$ARCH.efi</string>|" $SCRIPTDIR/configs/config$BUILD.plist 1> $OCPATH/config.plist
	echo "Using $answer as filesystem"
else
	cp $SCRIPTDIR/configs/config$BUILD.plist $OCPATH/config.plist
	echo "Using ext4 as filesystem"
fi

printf '%s' "Add a picker password to OpenCore? (y/N) "
read answer

if [ "$answer" != "${answer#[Yy]}" ]; then
	printf '%s\n' "Enter password:"
	passwordFields=$($OCUTILS/ocpasswordgen/ocpasswordgen.linux)
	passwordHash=$(echo $passwordFields | awk -F'[<>]' '{print $2}' | xxd -r -p | base64 -w 0)
	passwordSalt=$(echo $passwordFields | awk -F'[<>]' '{print $4}' | xxd -r -p | base64 -w 0)
	find_replace_config "PasswordHash" "<data>$passwordHash</data>"
	find_replace_config "PasswordSalt" "<data>$passwordSalt</data>"
	find_replace_config "EnablePassword" "<true/>"
fi

printf '%s' "Set up UEFI Secure Boot? (y/N) "
read answer

if [ "$answer" != "${answer#[Yy]}" ]; then
	KEYS=$SCRIPTDIR/Keys

	if [ -d "$KEYS" ]; then
		printf '%s' "Found existing keys! Do you want to delete them? (y/N) "
		read answer

		if [ "$answer" != "${answer#[Yy]}" ]; then
			rm -rf $KEYS
		else
			REUSEKEYS=1
		fi
	fi
	if [ "$REUSEKEYS" != 1 ]; then
		mkdir $KEYS
		stty -echo
		while true; do
			printf '%s' "Please enter your passphrase for your Secure Boot Keys: "
			read passphrase
			printf '\n%s' "Verify passphrase: "
			read answer
			if [ "$answer" != "$passphrase" ]; then
				echo 'Sorry, try again.'
			else
				printf '\n'
				stty echo
				break
			fi
		done
		echo 'Generating Platform Key'
		openssl req -new -x509 -newkey rsa:2048 -sha256 -days 365 -subj "/CN=Platform Key" -keyout $KEYS/PK.key -out $KEYS/PK.pem -passout pass:$passphrase -batch 2> /dev/null
		echo 'Generating Key Exchange Key'
		openssl req -new -x509 -newkey rsa:2048 -sha256 -days 365 -subj "/CN=Key Exchange Key" -keyout $KEYS/KEK.key -out $KEYS/KEK.pem -passout pass:$passphrase -batch 2> /dev/null
		echo 'Generating Image Signing Key'
		openssl req -new -x509 -newkey rsa:2048 -sha256 -days 365 -subj "/CN=Image Signing Key" -keyout $KEYS/ISK.key -out $KEYS/ISK.pem -passout pass:$passphrase -batch 2> /dev/null
		echo 'Converting PEMs to ESL format'
		cd $KEYS
		cert-to-efi-sig-list -g "$(uuidgen)" PK.pem PK.esl
		cert-to-efi-sig-list -g "$(uuidgen)" KEK.pem KEK.esl
		cert-to-efi-sig-list -g "$(uuidgen)" ISK.pem ISK.esl
		printf '%s' "Exclude Microsoft's keys? (Don't select yes unless you are certain you won't block option ROMs, like video BIOS!) (y/N) "
		read answer

		if [ "$answer" != "${answer#[Yy]}" ]; then
			echo "Adding ISK to DB"
			mv ISK.esl db.esl
		else
			echo "Downloading Microsoft's keys"
			curl -Lso MsWin.crt http://go.microsoft.com/fwlink/?LinkID=321192
			curl -Lso UEFI.crt http://go.microsoft.com/fwlink/?LinkId=321194
			echo "Converting DERs to PEMs"
			openssl x509 -in MsWin.crt -inform DER -out MsWin.pem -outform PEM
			rm MsWin.crt
			openssl x509 -in UEFI.crt -inform DER -out UEFI.pem -outform PEM
			rm UEFI.crt
			echo "Converting Microsoft's keys to ESL format"
			cert-to-efi-sig-list -g "$(uuidgen)" MsWin.pem MsWin.esl
			cert-to-efi-sig-list -g "$(uuidgen)" UEFI.pem UEFI.esl
			echo "Adding Microsoft's keys to DB"
			cat ISK.esl MsWin.esl UEFI.esl > db.esl
		fi

		echo 'Signing keys (Enter your passphrase three times!)'
		sign-efi-sig-list -k PK.key -c PK.pem PK PK.esl PK.auth > /dev/null
		sign-efi-sig-list -k PK.key -c PK.pem KEK KEK.esl KEK.auth > /dev/null
		sign-efi-sig-list -k KEK.key -c KEK.pem db db.esl db.auth > /dev/null
	fi

	printf '%s' "Chainload OpenCore using Shim? (Highly recommended if your distro uses shim) (y/N) "
	read answer

	if [ "$answer" != "${answer#[Yy]}" ]; then
		cd $OCUTILS/ShimUtils
		USINGSHIM=1

		printf '%s' "Download shimx64.efi from Ubuntu? (y/N) "
		read answer

		if [ "$answer" != "${answer#[Yy]}" ]; then
			curl -Lso shimUbuntu.tar.xz https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/shim-signed/1.59/shim-signed_1.59.tar.xz
			tar xf shimUbuntu.tar.xz
			mv shim-signed/microsoft-shimx64.efi shimx64.efi
			./shim-to-cert.tool shimx64.efi || echo 'Failed to extract certificates from Shim!'
		else
			printf '%s' "Where is your distribution's shimx64.efi located? (should be somewhere like /boot/efi/efi/ubuntu/shimx64.efi)"
			read answer
			./shim-to-cert.tool "$answer" || echo 'Failed to extract certificates from Shim!'
		fi
		# Remove the redirections to /dev/null to unsuppress debug output
		echo 'Setting up build environment'
		./shim-make.tool -r $SCRIPTDIR/OpenCore/shim_root -s $SCRIPTDIR/OpenCore/shim_source setup > /dev/null 2>&1 || echo 'Failed to setup build environment!'
		echo 'Building Shim'
		./shim-make.tool -r $SCRIPTDIR/OpenCore/shim_root -s $SCRIPTDIR/OpenCore/shim_source make VENDOR_DB_FILE=$OCUTILS/ShimUtils/vendor.db > /dev/null 2>&1 || echo 'Failed to build Shim! Did you install libelf development libraries?'
		echo 'Installing Shim to OpenCore'
		./shim-make.tool -r $SCRIPTDIR/OpenCore/shim_root -s $SCRIPTDIR/OpenCore/shim_source install $OCPATH/../.. > /dev/null 2>&1 || echo 'Failed to install Shim to OpenCore EFI!'
		echo 'Adding changes to config.plist'
		find_replace_config "ShimRetainProtocol" "<true/>"
		find_replace_config "LauncherPath" "\EFI\OC\shimx64.efi"
		echo 'Adding empty SBAT section to config.plist'
		wget -q https://raw.githubusercontent.com/chenxiaolong/random-scripts/e752bf07bcfb0aa19a9d7dafa139cca74ecca4b7/pe-add-sections.py && chmod +x pe-add-sections.py
		./pe-add-sections.py -s .sbat /dev/null -z .sbat -i $OCPATH/OpenCore.efi -o $OCPATH/OpenCore.efi
	fi

	echo 'Signing OpenCore drivers...'
	for driver in `find $OCPATH/Drivers/*`; do
		sign_file "$driver"
	done
	echo 'Signing Bootstrap...'
	sign_file "$OCPATH/../BOOT/BOOTx64.efi"

	if [ "$USINGSHIM" = 1 ]; then
		echo "Signing Shim..."
		sign_file "$OCPATH/shimx64.efi"
		echo "Signing MokManager..."
		sign_file "$OCPATH/mmx64.efi"
	fi

	printf '%s' "Do you plan to Vault your configuration? (Prevent further changes) (y/N) "
	read answer

	if [ "$answer" != "${answer#[Yy]}" ]; then
		VAULTSB=1
	else
		VAULTSB=2
		echo 'Signing OpenCore now, will not vault'
		sign_file "$OCPATH/OpenCore.efi"
	fi
	cd $SCRIPTDIR
	echo 'Please add PK.auth, KEK.auth, and db.auth to your firmware!'
fi

printf '%s' 'Create persistent boot option for OpenCore? (Required if using Shim. Only recommended if permanently installing to EFI) (y/N) '
read answer

if [ "$answer" != "${answer#[Yy]}" ]; then
	echo 'Enabling LauncherOption in config.plist'
	find_replace_config "LauncherOption" "<string>Full</string>"
fi

if [ "$VAULTSB" != 2 ] && [ "$VAULTSB" != 1 ]; then
	printf '%s' 'Vault configuration? (Prevents changes from being made to configuration) (y/N) '
	read answer
fi

if [ "$answer" != "${answer#[Yy]}" ] || [ "$VAULTSB" = 1 ]; then
	echo 'Requiring secure vault in config.plist'
	find_replace_config "Vault" "<string>Secure</string>"
	echo 'Downloading OpenCore Source...'
	curl -Lso OpenCore.zip https://github.com/acidanthera/OpenCorePkg/archive/refs/tags/$OCVER.zip
	unzip -qq OpenCore.zip
	mv OpenCorePkg-$OCVER OpenCorePkg
	rm OpenCore.zip
	echo 'Compiling RsaTool...'
	cd OpenCorePkg/Utilities/RsaTool && make && cd ../../../
	echo 'Copying RsaTool to OpenCore...'
	cp OpenCorePkg/Utilities/RsaTool/RsaTool $OCUTILS/CreateVault
	rm -rf OpenCorePkg
	echo 'Vaulting OpenCore...'
	$OCUTILS/CreateVault/sign.command $OCPATH

	if [ "$VAULTSB" = 1 ]; then
		sign_file "$OCPATH/OpenCore.efi"
	fi
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