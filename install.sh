#!/bin/sh

exit_on_error() {
	echo "$1" >&2
	exit
}
sign_file() {
	file="$1"
	echo "Signing $file (enter your passphrase)"
	while true; do
		sbsign --key "$KEYS/ISK.key" --cert "$KEYS/ISK.pem" "$file" --output "$file" 2> /dev/null
		if [ "$?" != 0 ]; then
			echo "Sorry, try again"
		else
			break
		fi
	done
}
find_replace_config() {
	mv "$OCPATH/config.plist" "$OCPATH/temp.plist"
	awk -v findkey="$1" -v replacevalue="$2" '$0 ~ "<key>" findkey "<\/key>" {print; getline; print "\t\t\t" replacevalue; next} 1' "$OCPATH/temp.plist" > "$OCPATH/config.plist" 2> /dev/null || exit_on_error "Failed to replace value $2 at key $1"
	rm "$OCPATH/temp.plist"
}
find_replace() {
	mv "$3" "$3temp"
	sed "s|$1|$2|" "$3temp" > "$3" || exit_on_error "Failed to replace value $1 with $2 in $3!"
	rm "$3temp"
}
ask_question() {
	printf '%s' "$1"
	read answer
}
download_unzip_to_dir() {
	curl -Lfso "$SCRIPTDIR/$2.zip" "$1" || exit_on_error "Failed to download $2"
	unzip -qq "$SCRIPTDIR/$2.zip" -d "$SCRIPTDIR/$2" || exit_on_error "Failed to unzip $2"
	rm "$SCRIPTDIR/$2.zip"
}
shim_make() {
	"$OCUTILS/ShimUtils/shim-make.tool" -r "$OCUTILS/shim_root" -s "$OCUTILS/shim_source" $1 > /dev/null 2>&1 || exit_on_error "Failed to make Shim!"
}

if [ ! -x /usr/bin/xxd ] || [ ! -x /usr/bin/base64 ]; then
	NO_PASSWORD=0
	echo "Will not be able to generate passwords"
fi

if [ ! -x /usr/bin/gcc ] || [ ! -x /usr/bin/make ] || [ ! -x /usr/bin/uuidgen ] || [ ! -x /usr/bin/openssl ]; then
	NO_VAULT=0
	echo "Will not be able to vault"
fi

if [ ! -x /usr/bin/cert-to-efi-sig-list ] || [ ! -x /usr/bin/sbsign ] || [ ! -x /usr/bin/openssl ]; then
	NO_SB=0
	echo "Will not be able to generate Secure Boot keys"
fi

if [ ! -x /usr/bin/gcc ] || [ ! -x /usr/bin/make ] || [ ! -x /usr/bin/python3 ]; then
	NO_SHIM=0
	echo "Will not be able to integrate Shim with OpenCore"
fi

OCVER=$(curl --silent -qI https://github.com/acidanthera/OpenCorePkg/releases/latest | awk -F '/' '/^location/ {print  substr($NF, 1, length($NF)-1)}');
SCRIPTDIR="$(mktemp -d || exit_on_error \"Couldn\'t make temporary directory\")"
LOCALDIR="$(pwd -P)"
trap "rm -rf $SCRIPTDIR" EXIT

echo "Welcome!"
echo "This script will create an EFI for OpenCore that can be used exclusively for Linux and Windows booting. It cannot be used for hackintoshing or booting macOS. For that purpose, the official install guide at https://dortania.github.io/OpenCore-Install-Guide/ should be used instead."
ask_question "Use DEBUG version of OpenCore? (Disable GUI, log to file and screen, dump ACPI and system info to partition) (y/N) "

if [ "$answer" != "${answer#[Yy]}" ]; then
	BUILD=DEBUG
else
	BUILD=RELEASE
fi

echo "Cleaning leftover files..."
rm -rf "$SCRIPTDIR/OpenCore"
echo "Downloading the latest release of OpenCore..."
mkdir "$SCRIPTDIR/OpenCore"
download_unzip_to_dir "https://github.com/acidanthera/OpenCorePkg/releases/download/$OCVER/OpenCore-$OCVER-$BUILD.zip" "OpenCore"
ask_question "Is your EFI architecture IA32, or 32 bit? (If in doubt, select no) (y/N) "

if [ "$answer" != "${answer#[Yy]}" ]; then
	ARCH=IA32
else
	ARCH=X64
fi

OCPATH="$SCRIPTDIR/OpenCore/$ARCH/EFI/OC"
OCUTILS="$SCRIPTDIR/OpenCore/Utilities"
OCBINDATA="$SCRIPTDIR/OcBinaryData/OcBinaryData-master"

echo "Removing unneeded drivers..."
find "$OCPATH"/Drivers/* ! -name 'OpenRuntime.efi' ! -name 'OpenLinuxBoot.efi' ! -name 'OpenCanopy.efi' ! -name 'Ext4Dxe.efi' -exec rm -f {} +
echo "Removing unneeded tools..."
rm -f "$OCPATH"/Tools/*

echo "Setting up a theme for OpenCanopy"

if [ ! -d "$OCBINDATA" ]; then
	download_unzip_to_dir "https://github.com/acidanthera/OcBinaryData/archive/refs/heads/master.zip" "OcBinaryData"
fi

cp -r "$OCBINDATA/Resources/" "$OCPATH/"

ask_question "What filesystem is your /boot partition on? (ext4, btrfs, fat32, etc.): "
answer=$(echo "$answer" | awk '{print tolower($0)}')

curl -Lfso "$OCPATH/config.plist" "https://raw.githubusercontent.com/some100/opencore-linux-script/refs/heads/main/configs/config$BUILD.plist"
case "$answer" in
	"btrfs")
		echo "Getting filesystem driver"
		rm "$OCPATH/Drivers/Ext4Dxe.efi"
		cp "$OCBINDATA/Drivers/btrfs_x64.efi" "$OCPATH/Drivers/btrfs_x64.efi" || exit_on_error "Failed to get filesystem $answer driver!"
		echo "Copying changes to config.plist"
		find_replace "Ext4Dxe.efi" "btrfs_x64.efi" "$OCPATH/config.plist"
		;;
	"ext4")
		;;
	fat*)
		;;
	"")
		answer=ext4
		;;
	*)
		echo "Getting filesystem driver"
		rm "$OCPATH/Drivers/Ext4Dxe.efi"
		curl -Lfso "$OCPATH/Drivers/${answer}_${ARCH}.efi" "https://github.com/pbatard/EfiFs/releases/latest/download/${answer}_${ARCH}.efi" || exit_on_error "Failed to get filesystem $answer driver!"
		echo "Copying changes to config.plist"
		find_replace "Ext4Dxe.efi" "${answer}_${ARCH}.efi" "$OCPATH/config.plist"
esac
echo "Using $answer as filesystem"

if [ -z "$NO_PASSWORD" ]; then
	ask_question "Add a picker password to OpenCore? (y/N) "

	if [ "$answer" != "${answer#[Yy]}" ]; then
		printf '%s\n' "Enter password:"
		password=$("$OCUTILS/ocpasswordgen/ocpasswordgen.linux") || exit_on_error "Password generation failed!"
		password_hash=$(echo $password | awk -F'[<>]' '{print $2}' | xxd -r -p | base64 -w 0)
		password_salt=$(echo $password | awk -F'[<>]' '{print $4}' | xxd -r -p | base64 -w 0)
		find_replace_config "PasswordHash" "<data>$password_hash</data>"
		find_replace_config "PasswordSalt" "<data>$password_salt</data>"
		find_replace_config "EnablePassword" "<true/>"
	fi
fi

ask_question "Don't show picker on every boot? (You can still show picker by holding the 0 key) (y/N) "

if [ "$answer" != "${answer#[Yy]}" ]; then
	echo "Disabling picker in config..."
	find_replace_config "ShowPicker" "<false/>"
fi

if [ -z "$NO_SB" ]; then
	ask_question "Set up UEFI Secure Boot? (y/N) "

	if [ "$answer" != "${answer#[Yy]}" ]; then
		KEYS="$LOCALDIR/Keys"

		if [ -d "$KEYS" ]; then
			ask_question "Found existing keys! Do you want to delete them? (y/N) "

			if [ "$answer" != "${answer#[Yy]}" ]; then
				rm -rf "$KEYS"
			else
				REUSEKEYS=1
			fi
		fi
		if [ "$REUSEKEYS" != 1 ]; then
			mkdir "$KEYS"
			stty -echo
			while true; do
				printf '%s' "Please enter your passphrase for your Secure Boot Keys: "
				read passphrase
				printf '\n%s' "Verify passphrase: "
				read answer
				if [ "$answer" != "$passphrase" ]; then
					echo "Sorry, try again."
				else
					printf '\n'
					stty echo
					break
				fi
			done
			printf '%s' "How many days should the keys be valid? "
			read expiry

			if [ -z "$expiry" ]; then
				echo "No expiry provided, defaulting to 1 year"
				expiry=365
			fi

			echo "Generating Platform Key"
			openssl req -new -x509 -newkey rsa:2048 -sha256 -days $expiry -subj "/CN=Platform Key" -keyout "$KEYS/PK.key" -out "$KEYS/PK.pem" -passout pass:"$passphrase" -batch 2> /dev/null || exit_on_error "Couldn't generate Platform Key!"
			echo "Generating Key Exchange Key"
			openssl req -new -x509 -newkey rsa:2048 -sha256 -days $expiry -subj "/CN=Key Exchange Key" -keyout "$KEYS/KEK.key" -out "$KEYS/KEK.pem" -passout pass:"$passphrase" -batch 2> /dev/null || exit_on_error "Couldn't generate Key Exchange Key!"
			echo "Generating Image Signing Key"
			openssl req -new -x509 -newkey rsa:2048 -sha256 -days $expiry -subj "/CN=Image Signing Key" -keyout "$KEYS/ISK.key" -out "$KEYS/ISK.pem" -passout pass:"$passphrase" -batch 2> /dev/null || exit_on_error "Couldn't generate Image Signing Key!"
			echo "Converting PEMs to ESL format"
			cd "$KEYS"
			cert-to-efi-sig-list -g "$(uuidgen)" PK.pem PK.esl
			cert-to-efi-sig-list -g "$(uuidgen)" KEK.pem KEK.esl
			cert-to-efi-sig-list -g "$(uuidgen)" ISK.pem ISK.esl
			ask_question "Exclude Microsoft's keys? (Don't select yes unless you are certain you won't block option ROMs, like video BIOS!) (y/N) "

			if [ "$answer" != "${answer#[Yy]}" ]; then
				echo "Adding ISK to DB"
				mv ISK.esl db.esl
			else
				echo "Downloading Microsoft's keys"
				curl -Lfso MsWin.crt http://go.microsoft.com/fwlink/?LinkID=321192 || exit_on_error "Couldn't download Windows certificate!"
				curl -Lfso UEFI.crt http://go.microsoft.com/fwlink/?LinkId=321194 || exit_on_error "Couldn't download Microsoft UEFI driver signing certificate!"
				echo "Converting DERs to PEMs"
				openssl x509 -in MsWin.crt -inform DER -out MsWin.pem -outform PEM
				openssl x509 -in UEFI.crt -inform DER -out UEFI.pem -outform PEM
				echo "Converting Microsoft's keys to ESL format"
				cert-to-efi-sig-list -g "$(uuidgen)" MsWin.pem MsWin.esl
				cert-to-efi-sig-list -g "$(uuidgen)" UEFI.pem UEFI.esl
				echo "Adding Microsoft's keys to DB"
				cat ISK.esl MsWin.esl UEFI.esl > db.esl
			fi

			echo "Signing keys (Enter your passphrase three times!)"
			sign-efi-sig-list -k PK.key -c PK.pem PK PK.esl PK.auth > /dev/null
			sign-efi-sig-list -k PK.key -c PK.pem KEK KEK.esl KEK.auth > /dev/null
			sign-efi-sig-list -k KEK.key -c KEK.pem db db.esl db.auth > /dev/null
		fi

		if [ -z "$NO_SHIM" ]; then
			ask_question "Chainload OpenCore using Shim? (Highly recommended if your distro uses shim) (y/N) "

			if [ "$answer" != "${answer#[Yy]}" ]; then
				cd "$OCUTILS/ShimUtils"
				USINGSHIM=1

				ask_question "Where is your distribution's shimx64.efi located? (should be somewhere like /boot/efi/efi/ubuntu/shimx64.efi) "
				./shim-to-cert.tool "$answer" || exit_on_error "Failed to extract certificates from Shim!"

				# Remove the redirections to /dev/null to unsuppress debug output
				echo "Setting up build environment"
				shim_make "setup"
				echo "Building Shim"
				shim_make "make VENDOR_DB_FILE=\"$OCUTILS/ShimUtils/vendor.db\""
				echo "Installing Shim to OpenCore"
				shim_make "install $OCPATH/../.."
				echo "Adding changes to config.plist"
				find_replace_config "ShimRetainProtocol" "<true/>"
				find_replace_config "LauncherPath" '<string>\\EFI\\OC\\shimx64.efi</string>'
				echo "Adding empty SBAT section to OpenCore"
				wget -q https://raw.githubusercontent.com/chenxiaolong/random-scripts/e752bf07bcfb0aa19a9d7dafa139cca74ecca4b7/pe-add-sections.py || exit_on_error "Couldn't download pe-add-sections.py!"
				chmod +x pe-add-sections.py
				./pe-add-sections.py -s .sbat /dev/null -z .sbat -i "$OCPATH/OpenCore.efi" -o "$OCPATH/OpenCore.efi" || exit_on_error "Couldn't add empty SBAT section to OpenCore!"
			fi
		fi

		echo "Signing OpenCore drivers..."
		for driver in "$OCPATH/Drivers"/*; do
			sign_file "$driver"
		done
		echo "Signing Bootstrap..."
		sign_file "$OCPATH/../BOOT/BOOTx64.efi"

		if [ "$USINGSHIM" = 1 ]; then
			echo "Signing Shim..."
			sign_file "$OCPATH/shimx64.efi"
			echo "Signing MokManager..."
			sign_file "$OCPATH/mmx64.efi"
		fi

		if [ -z "$NO_VAULT" ]; then
			ask_question "Do you plan to Vault your configuration? (Prevent further changes) (y/N) "

			if [ "$answer" != "${answer#[Yy]}" ]; then
				VAULTSB=1
			else
				VAULTSB=0
				echo "Signing OpenCore now, will not vault"
				sign_file "$OCPATH/OpenCore.efi"
			fi
		fi

		cd "$SCRIPTDIR"
		echo "Please add PK.auth, KEK.auth, and db.auth to your firmware!"
	fi
fi

ask_question "Create persistent boot option for OpenCore? (Required if using Shim. Only recommended if permanently installing to EFI) (y/N) "

if [ "$answer" != "${answer#[Yy]}" ]; then
	echo "Enabling LauncherOption in config.plist"
	find_replace_config "LauncherOption" "<string>Full</string>"
fi

if [ -z "$NO_VAULT" ]; then
	if [ -z "$VAULTSB" ]; then
		ask_question "Vault configuration? (Prevents changes from being made to configuration) (y/N) "
	fi

	if [ "$answer" != "${answer#[Yy]}" ] || [ "$VAULTSB" = 1 ]; then
		echo "Requiring secure vault in config.plist"
		find_replace_config "Vault" "<string>Secure</string>"
		echo "Downloading OpenCore Source..."
		download_unzip_to_dir "https://github.com/acidanthera/OpenCorePkg/archive/refs/tags/$OCVER.zip" "OpenCorePkg"
		mv "$SCRIPTDIR/OpenCorePkg/OpenCorePkg-$OCVER"/* "$SCRIPTDIR/OpenCorePkg"
		echo "Compiling RsaTool..."
		cd "$SCRIPTDIR/OpenCorePkg/Utilities/RsaTool" && make && cd "$SCRIPTDIR"
		echo "Copying RsaTool to OpenCore..."
		cp "$SCRIPTDIR/OpenCorePkg/Utilities/RsaTool/RsaTool" "$OCUTILS/CreateVault"
		rm -rf OpenCorePkg
		echo "Vaulting OpenCore..."
		"$OCUTILS/CreateVault/sign.command" "$OCPATH" || exit_on_error "Failed to vault configuration!"

		if [ "$VAULTSB" = 1 ]; then
			sign_file "$OCPATH/OpenCore.efi"
		fi
	fi
fi

ask_question "Where should OpenCore be installed? (example: /boot/efi, /efi, your USB drive, etc.) "

if [ ! -w "$answer" ]; then
	exit_on_error "No permission to write to directory $answer or does not exist!"
fi

cp -r "$SCRIPTDIR/OpenCore/$ARCH"/* $answer/ || exit_on_error "Failed to copy OpenCore to selected directory!"
echo "Done!"
exit
