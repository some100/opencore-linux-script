# opencore-linux-script
Attempts to automate installation of OpenCore solely for booting Linux systems

## What is OpenCore?
OpenCore is a boot manager that was mainly created for the purposes of hackintoshing, or installing macOS on non-Apple hardware. However, it can also boot other operating systems such as Linux and Windows. This script mainly focuses on the former, and creates a configuration that, while useless for hackintoshing, is enough for booting Linux.

## Why use OpenCore over something like GRUB or systemd-boot?
Well, OpenCore generally is much faster than GRUB. It's a much smaller binary as well. The entire boot manager, with drivers included, has a lower disk usage than just grubx64.efi. OpenCore has many security features, such as Vaulting, picker password protection, and trusted loading with UEFI Secure Boot. OpenCore's development also follows best practices for security, such as fuzzing and formal review. OpenCore also generally looks nicer with a macOS style boot picker.
