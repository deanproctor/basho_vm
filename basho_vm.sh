#!/bin/bash

usage()
{
cat << EOF
usage: $0 options

This script will create and launch a new VM.

OPTIONS:
  -h   Show this message
  -d   Show debug messages
  -n   The Guest VM name
  -c   Number of virtual CPUs to allocate. Default: 1
  -m   Amount of memory in MB to allocate the VM. Default: 1024
  -r   The size in MB of the root partition
  -s   The size in MB of the swap partition
EOF
}

NAME=
MEM=1024
CPU=1
ROOTSIZE=5120
SWAPSIZE=1024
VERBOSITY="--quiet"

while getopts "hdn:c:m:n:r:s" OPTION
do
  case $OPTION in
    h)
      usage
      exit 1
      ;;
    d)
      VERBOSITY="--verbose --debug"
      ;;
    c)
      CPU=$OPTARG
      ;;
    m)
      MEM=$OPTARG
      ;;
    n)
      NAME=$OPTARG
      ;;
    r)
      ROOTSIZE=$OPTARG
      ;;
    s)
      SWAPSIZE=$OPTARG
      ;;
    ?)
      usage
      exit
      ;;
  esac
done

if [[ -z $NAME ]]
then
  usage
  exit 1
fi

SQLITE="sqlite /var/basho/vms.db"
IMAGE_DIR=/var/lib/libvirt/images/$NAME

echo "Destroying previous environment named ${NAME}"
echo "ctrl-c now to abort"

sleep 3

virsh destroy $NAME 2>&1 > /dev/null
virsh undefine $NAME 2>&1 > /dev/null

$SQLITE "UPDATE ips SET status='free', name='' WHERE name='${NAME}'"
IP=$($SQLITE "SELECT MIN(ip) from ips WHERE status='free'")

echo
echo "VM Parameters:"
echo " - Name:        ${NAME}"
echo " - CPUs:        ${CPU}"
echo " - RAM:         ${MEM}"
echo " - Root Size:   ${ROOTSIZE}"
echo " - Swap Size:   ${SWAPSIZE}"
echo " - IP:          ${IP}"
echo

sleep 3

echo "Creating VM..."
echo

ubuntu-vm-builder kvm -o --tmpfs - --suite=precise --flavour=virtual --arch=amd64 --components=main,universe \
        --hostname=${NAME} --mem=${MEM} --cpus=${CPU} \
        --dest ${IMAGE_DIR} --rootsize=${ROOTSIZE} --swapsize=${SWAPSIZE} \
        --ip=${IP} --bridge=br0 --mask=255.255.248.0 --gw=10.0.27.1 --bcast=10.0.31.255 --net=10.0.27.0/21 --dns=8.8.8.8 \
        --addpkg=openssh-server --addpkg=acpid --addpkg=sysstat --addpkg=chef --addpkg=ntp \
        --addpkg=curl --addpkg=wget --addpkg=vim --addpkg=git-core --lang=en_US.UTF-8 \
        --copy=/usr/local/share/kvm/templates/manifest.txt \
        --firstboot=/usr/local/share/kvm/files/firstboot.sh \
        --libvirt=qemu:///system ${VERBOSITY}

if [ $? -eq 0 ]
then
  $SQLITE "UPDATE ips SET name='$NAME', status='in-use' WHERE ip='$IP'"

  echo "Starting VM..."
  virsh autostart $NAME
  virsh start $NAME

  echo "VM creation complete."
  echo " - Name:        ${NAME}"
  echo " - CPUs:        ${CPU}"
  echo " - RAM:         ${MEM}"
  echo " - Root Size:   ${ROOTSIZE}"
  echo " - Swap Size:   ${SWAPSIZE}"
  echo " - IP:          ${IP}"
  echo
fi

