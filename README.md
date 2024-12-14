# opencore-linux-script
Attempts to automate installation of OpenCore solely for booting Linux systems

## Disclaimer
This script probably shouldn't be seriously used yet. I've only been able to verify it working inside of a VM. If you do decide to test this, install it to your USB drive, not your EFI partition. I am also not sure if this will work with older firmwares (pre-2017).

**THIS WILL NOT PRODUCE A USABLE EFI FOR MACOS!** For hackintoshing, use the excellent [OpenCore Install Guide](https://dortania.github.io/OpenCore-Install-Guide/) instead of this tool.

## Usage
Run install.sh. 
* Optionally, if you want to use a picker password, install xxd and base64. 
* If you want to vault your configuration, install build tools (gcc, make, etc), uuidgen, and OpenSSL (including development libraries). 
* If you want to automate generation of Secure Boot keys, install efitools, sbsigntools, OpenSSL. 
  * If you're using Shim with Secure Boot, install libelf development libraries, build tools, and python3. Install the "pefile" library to Python as well

## What is OpenCore?
OpenCore is a boot manager that was mainly created for the purposes of hackintoshing, or installing macOS on non-Apple hardware. However, it can also boot other operating systems such as Linux and Windows. This script creates a configuration that, while useless for hackintoshing, is enough for booting Linux.

## Why use OpenCore over something like GRUB or systemd-boot?
Well, OpenCore generally is much faster than GRUB. It's more lightweight as well. The entire boot manager, with drivers included, has a lower disk usage than just grubx64.efi. OpenCore has security features like vaulting, password protection, and integration with UEFI Secure Boot. OpenCore's development also follows best practices for security, such as fuzzing and formal review. OpenCore also has a macOS-style boot picker, which looks (in my opinion) much nicer than systemd-boot and (default) GRUB. 

## Configuration
OpenCore uses the config.plist to customize behavior inside of the boot manager. On the surface, it's much more complicated than configuring systemd-boot and GRUB. However, many parts of the config.plist can be ignored since we're only focusing on booting Linux. Generally, the [Configuration](https://dortania.github.io/docs/latest/Configuration.html) can help you find your way through the configuration. To increase security, you can set up a picker password, [ScanPolicy](https://dortania.github.io/OpenCore-Post-Install/universal/security/scanpolicy.html), or Vaulting.
