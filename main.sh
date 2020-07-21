#!/bin/bash

function check_IOMMU() {
    iommu_cli = ""

    if [ `ls /sys/kernel/iommu_groups/` != "" ]; then
        echo "[+] Found IOMMU groups"
    else
        echo "[-] Failed to find IOMMU groups!"
        echo "\tThis could be because you have not added"
        echo "\tthe appropriate flags to the kernel boot line"

        if [ `cat /proc/cpuinfo | grep "vendor_id" | cut -d: -f2 |  head -n 1` == "GenuineIntel" ]; then
            echo "\tFor your CPU, you should add \"intel_iommu=on\""
            $iommu_cli = "intel_iommu=on"
            
        else
            echo "\tFor your CPU, you should add \"amd_iommu=on\""
            $iommu_cli = "amd_iommu=on"
        fi 

        if [ -f "/boot/grub/grub.cfg" ]; then
            echo "[+] GRUB bootloader detected. Would you like for me"
            read -p "\tto automatically add the IOMMU argument?" answer

            case $answer in
                [yY]* ) echo "[+] Adding to configuration file..."
                        cp /etc/default/grub /etc/default/grub.bak
                        sed 's|GRUB_CMDLINE_LINUX_DEFAULT="[^"]*|& '$iommu_test'|g' /etc/default/grub > /etc/default/grub
                        
                        echo "[ ] Updating GRUB configuration..."
                        grub-mkconfig -o /boot/grub/grub.cfg

                        echo "[+] Done! Reboot to enable IOMMU support and try again"
                        exit 1

                        break;;
                * ) echo "[ ] Passing..."; break;;
            esac
        fi
    fi

}

function get_gpu_iommu_grp() {
    if [ -f ~/.done_iommu ]; then
        echo "[+] Detected IOMMU setup completion"
        return
    fi

    echo "[+] Found `lspci | grep -i vga | wc -l` available GPU devices:"
    echo lspci | grep -i vga

    iommu_grp=""

    read -p "Enter the first number on the desired GPU you would like to passthrough > " pci_addr

    for g in /sys/kernel/iommu_groups/*; do
        echo "IOMMU Group ${g##*/}:"
        for d in $g/devices/*; do
            if [[ $"lspci -nns ${d##*/}" == *"$pci_addr:"* ]]; then
                echo "[+] Found target IOMMU group ${g##*/}"
                iommu_grp="${g##*/}"
                break;
            fi
        done;
    done;

    if [ iommu_grp == "" ]; then
        echo "[-] Failed to find IOMMU group of GPU. Are you sure IOMMU is working properly?"
        exit 2
    fi


    path="/sys/kernel/iommu_groups/$iommu_grp/devices/"

    for g in $path/*; do
        thing="$(lspci -nns ${g##*/} | cut -d\[ -f 3-)"   

        if [[ $thing == *"["* ]]; then
            echo "[+] Detected special"
            thing="$(echo "$thing" | cut -d\[ -f 2)"
            echo $thing > ~/.done_iommu
            add_device $thing
        fi
    done

    cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak
    sed 's|MODULES=([^)]*|& vfio_pci vfio vfio_iommu_type1 vfio_virqfd |g' /etc/mkinitcpio.conf > /etc/mkinitcpio.conf

    sed 's|HOOKS=([^)]*|& modconf |g' /etc/mkinitcpio.conf > /etc/mkinitcpio.conf


    echo "[ ] Regenerating Initfs..."

    mkinitcpio -P

    echo "[+] Complete! Reboot again to ensure that VFIO is successfully set up"
    exit 0

}

function add_device() {
    if [ -f /etc/modprobe.d/vfio.conf ]; then
        echo ",$1" >> /etc/modprobe.d/vfio.conf
    else
        echo "options vfio-pci ids=$1"
    fi
}



function check_vfio_ok() {
    echo "[ ] Checking if VFIO setup was completed successfully..."

    test_addr = "$(cat ~/.done_iommu)"
    if [[ "$(lspci -nnk -d $test_addr | grep vfio-pci)" == "" ]]; then
        echo "[-] VFIO driver failed to load. Check dmesg and journalctl for more info"
        exit 10
    else 
        echo "[+] VFIO setup successful!"
    fi

}

function setup_libvirt() {
    echo "[ ] Setting up virtualization software..."

    pacman -S qemu libvirt edk2-ovmf virt-manager

    systemctl enable libvirtd.service
    systemctl enable virtlogd.service

    systemctl start libvirtd.service
    systemctl start virtlogd.service

    echo "[+] Done"
}

function last_steps() {
    pci_addr="$(lspci -nnk | grep `cat /.done_iommu` | cut -d " " -f 1)"


    echo "Before you go, there are a few things you should do:"
    echo " 1. Create a new virtual machine using virt-manager and BEFORE"
    echo "    CLICKING Finish, check the \"Customize before install\" checkbox"
    echo " 2. In the Overview section, make sure your firmware is set to UEFI"
    echo " 3. In the CPUs section, change the CPU model to \"host-passthrough\""
    echo " 4. Add the PCI bus IDs to the virtual machine using Add Hardware -> PCI Host Device"
    echo "        - Add all PCI devices that have $pci_addr in them"
    echo " 5. Set up Virtio disks"
    echo ""
    echo "You're all set! Good luck!"
    echo "Check out https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF#Setting_up_IOMMU"
    echo "for more information when stuff breaks!"

}


function main() {
    check_IOMMU
    get_gpu_iommu_grp
    check_vfio_ok
    setup_libvirt
}

main