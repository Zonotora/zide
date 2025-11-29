#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QEMU_DIR="${SCRIPT_DIR}/qemu-env"
DISK_IMAGE="${QEMU_DIR}/virt.qcow2"
DISK_SIZE="10G"
MEMORY="2G"
CPUS="2"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

create_disk() {
    echo_info "Creating QEMU disk image (${DISK_SIZE})..."
    qemu-img create -f qcow2 "${DISK_IMAGE}" "${DISK_SIZE}"
    echo_info "Disk image created at ${DISK_IMAGE}"
}

start_install() {
    if [ -z "$1" ]; then
        echo_error "Usage: $0 install <path-to-iso>"
        echo_info "Example: $0 install archlinux-2024.01.01-x86_64.iso"
        exit 1
    fi

    ISO_PATH="$1"

    if [ ! -f "${ISO_PATH}" ]; then
        echo_error "ISO file not found: ${ISO_PATH}"
        exit 1
    fi

    if [ ! -f "${DISK_IMAGE}" ]; then
        create_disk
    fi

    echo_info "Starting QEMU for installation..."
    echo_info "Memory: ${MEMORY}, CPUs: ${CPUS}"

    qemu-system-x86_64 \
        -enable-kvm \
        -m "${MEMORY}" \
        -smp "${CPUS}" \
        -drive file="${DISK_IMAGE}",format=qcow2 \
        -cdrom "${ISO_PATH}" \
        -boot d \
        -vga virtio \
        -display gtk,gl=on \
        -device virtio-net-pci,netdev=net0 \
        -netdev user,id=net0,hostfwd=tcp::2222-:22
}

start_vm() {
    if [ ! -f "${DISK_IMAGE}" ]; then
        echo_error "Disk image not found. Please run '$0 install <iso>' first"
        exit 1
    fi

    echo_info "Starting QEMU test environment..."
    echo_info "Memory: ${MEMORY}, CPUs: ${CPUS}"
    echo_info "SSH forwarding: localhost:2222 -> VM:22"

    qemu-system-x86_64 \
        -enable-kvm \
        -m "${MEMORY}" \
        -smp "${CPUS}" \
        -drive file="${DISK_IMAGE}",format=qcow2 \
        -vga virtio \
        -display gtk,gl=on \
        -virtfs local,path="${SCRIPT_DIR}",mount_tag=host_share,security_model=mapped-xattr,id=host_share
        # -device virtio-net-pci,netdev=net0 \
        # -netdev user,id=net0,hostfwd=tcp::2222-:22 \
}

usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Commands:
    install <iso>    Create disk and start installation from ISO
    start            Start the VM normally (with GUI)
    create-disk      Create a new disk image
    help             Show this help message

Examples:
    $0 install archlinux.iso    # Install OS from ISO
    $0 start                    # Start the VM

The VM shares the project directory at /mnt/host_share (mount with: mount -t 9p -o trans=virtio host_share /mnt/host_share)
SSH is forwarded to localhost:2222
EOF
}

case "$1" in
    install)
        start_install "$2"
        ;;
    start)
        start_vm
        ;;
    create-disk)
        create_disk
        ;;
    help|--help|-h|"")
        usage
        ;;
    *)
        echo_error "Unknown command: $1"
        usage
        exit 1
        ;;
esac

