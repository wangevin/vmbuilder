#!/bin/bash
clear
echo "#############################################################################################"
echo "###"
echo "# Welcome to the Proxmox Virtual Machine Builder script that uses Cloud Images"
echo "# This will automate so much and make it so easy to spin up a VM machine from a cloud image."
echo "# A VM Machine typically will be spun up and ready in less then 3 minutes."
echo "#"
echo "# Written by Francis Munch"
echo "# email: francismunch@tuta.io"
echo "# github: https://github.com/francismunch/vmbuilder"
echo "###"
echo "#############################################################################################"
echo
echo

# ====================
# Need to run as root
# ====================
if ![ $(id -u) = 0 ];
then 
	echo "Please run as root"
	exit
else
	TEXT_RESET='\e[0m'
	TEXT_YELLOW='\e[0;33m'
	TEXT_RED_B='\e[1;31m'
fi

#
# ==================
# Helper Functions
# ==================
#
# Echo out in YELLOW
echo_yellow()
{
	echo -n -e $TEXT_YELLOW
	echo $1
	echo -e $TEXT_RESET
}
# Echo out in RED
echo_red()
{
	echo -n -e $TEXT_RED
	echo $1
	echo -e $TEXT_RESET
}
# Install package if not installed (NOT NEEDED BUT PUT IN GITHUB)
install()
{
	echo_yellow "Installing $1 ..."
	# Test if no data passed
	if [ -z $1 ];
	then
		echo_red "No Package specified"
	else
		dpkg -s $1 &> /dev/null
		if [ $? -eq 0 ]; 
		then
			echo_yellow "Package $1 already installed!"
		else
			sudo apt install $1 -y
		fi
	fi
}
# Add a packate to an Image
add_to_image()
{
	echo_yellow "Add Package $2 to image $1 ..."
	if [ -z $1 ];
	then
		echo_red "No Package specified"
	elif [ -z $2 ];
	then
		echo_red "No Package specified"
	else
		# Example
		# sudo virt-customize -a focal-server-cloudimg-amd64.img --install sudo	
		sudo virt-customize -a $1 --install $2		
	fi
}

# =========================================================
# Going to ask questions for VM number, hostname, vlan tag
# =========================================================
while true; do
   echo_yellow "Enter desired hostname for the Virutal Machine: "
   read -r NEWHOSTNAME
   if [[ ! $NEWHOSTNAME == *['!'@#\$%^\&*()\_+\']* ]];then
      break;
   else
      echo_red "Contains a character not allowed for a hostname, please try again"
   fi
done
echo
echo_yellow "*** Taking a 5-7 seconds to gather information ***"
echo
# Picking VM ID number
# ====================
vmidnext=$(pvesh get /cluster/nextid)
declare -a vmidsavail=$(pvesh get /cluster/resources | awk '{print $2}' | sed '/storage/d' | sed '/node/d' | sed '/id/d' | sed '/./,/^$/!d' | cut -d '/' -f 2 | sed '/^$/d')

#echo ${vmidsavail[@]}

for ((i=1;i<=99;i++));
do
   systemids+=$(echo " " $i)
done

USEDIDS=("${vmidsavail[@]}" "${systemids[@]}")
declare -a all=( echo ${USEDIDS[@]} )

function get_vmidnumber() {
    echo_yellow "${1} New VM ID number: "
    read number
    if [[ " ${all[*]} " != *" ${number} "* ]]
    then
        VMID=${number:-$vmidnext}
    else
        get_vmidnumber 'Enter a different number because either you are using it or reserved by the sysem'
    fi
}
echo_yellow "Enter desired VM ID number or press enter to accept default of $vmidnext: "
get_vmidnumber ''

echo_yellow "The VM number will be $VMID"

## Get User Name and Password
# ===========================
echo_yellow "Enter desired VM username: "
read USER
while true; do
    echo_yellow "Please enter password for the user: "
    read -s PASSWORD
    echo_yellow "Please repeat password for the user: "
    read -s PASSWORD1
    [ "$PASSWORD" = "$PASSWORD1" ] && break
    echo_red "Please try again passwords did not match"
done
echo
# really just hashing the password so its not in plain text in the usercloud.yaml
# that is being created during the process
# really should do keys for most secure
kindofsecure=$(openssl passwd -1 -salt SaltSalt $PASSWORD)

## Selecting the Storage th VM will run on
# =========================================
echo_yellow "Please select the storage the VM will run on?"
storageavail=$(awk '{if(/:/) print $2}' /etc/pve/storage.cfg)
typestorage=$(echo "${storageavail[@]}")
declare -a allstorage=( ${typestorage[@]} )
total_num_storage=${#allstorage[@]}
allstorage2=$( echo ${allstorage[@]} )

select option in $allstorage2; do
if [ 1 -le "$REPLY" ] && [ "$REPLY" -le $total_num_storage ];
then
        vmstorage=$option
        break;
else
        echo_red "Incorrect Input: Select a number 1-$total_num_storage"
fi
done

echo_yellow "The storage you selected for the VM is $vmstorage"

## Selecting the ISO Storage location
# ====================================
echo
echo_yellow "Please select ISO storage location"
isostorageavail=$(awk '{if(/path/) print $2}' /etc/pve/storage.cfg)
path=/template/iso/
typeisostorage=$(echo "${isostorageavail[@]}")
declare -a allisostorage=( ${typeisostorage[@]} )

cnt=${#allisostorage[@]}
for (( i=0;i<cnt;i++)); do
    allisostorage[i]="${allisostorage[i]}$path"
done
total_num_storage_paths=${#allisostorage[@]}
allisostorage2=$( echo ${allisostorage[@]} )

select option in $allisostorage2; do
if [ 1 -le "$REPLY" ] && [ "$REPLY" -le $total_num_storage_paths ];
then
        echo_yellow "The selected option is $REPLY"
        echo_yellow "The selected storage is $option"
        isostorage=$option
        break;
else
        echo_red "Incorrect Input: Select a number 1-$total_num_storage_paths"
fi
done


echo_yellow "The cloud image will be downloaded to " $isostorage " or look there if already downloaded"
echo

## user.yaml config location and storage for snippets
# ===================================================
echo_yellow "Please select the storage that has snippets available"
echo_yellow "If you pick one that does not have it enabled the VM being created will not have all the"
echo_yellow "user settings (user name, password , keys) so if you need to check in the GUI click on Datacenter"
echo_yellow "then click on storage and see if enabled, if not you need to enable it on the storage you want it"
echo_yellow "to be placed on.  There will be two questions for snippet setup. One for the actual locaiton to put the user.yaml and the"
echo_yellow "second for the storage being used for snippets."
echo
snippetsstorageavail=$(awk '{if(/path/) print $2}' /etc/pve/storage.cfg)
snippetspath=/snippets/

declare -a allsnippetstorage=( ${snippetsstorageavail[@]} )

cnt=${#allsnippetstorage[@]}
for (( i=0;i<cnt;i++)); do
    allsnippetstorage[i]="${allsnippetstorage[i]}$snippetspath"
done

total_num_snippet_paths=${#allsnippetstorage[@]}
allsnippetstorage2=$( echo ${allsnippetstorage[@]} )

select option in $allsnippetstorage2; do
if [ 1 -le "$REPLY" ] && [ "$REPLY" -le $total_num_snippet_paths ];
then
        snippetstorage=$option
        break;
else
        echo_red "Incorrect Input: Select a number 1-$total_num_snippet_paths"
fi
done

echo
echo_yellow "The snippet storage location will be " $snippetstorage "here, which will hold the user data yaml file for each VM"
echo
echo_yellow "Now that we have selected the snippet storage path ($snippetstorage) we need to actually select the storage that this path is on."
echo_yellow "Make sure the path picked and the storage picked are one in the same or it will fail."
echo_yellow "example /var/lib/vz/snippets/ is "local" storage"
echo
echo_yellow "Please select the storage the snippets will be on"
storageavailsnip=$(awk '{if(/:/) print $2}' /etc/pve/storage.cfg)
typestoragesnip=$(echo "${storageavailsnip[@]}")
declare -a allstoragesnip=( ${typestoragesnip[@]} )
total_num_snippet_storages=${#allstoragesnip[@]}
allstoragesnip2=$( echo ${allstoragesnip[@]} )

select option in $allstoragesnip2; do
if [ 1 -le "$REPLY" ] && [ "$REPLY" -le $total_num_snippet_storages ];
then
        snipstorage=$option
        break;
else
        echo "Incorrect Input: Select a number 1-$total_num_storage"
fi
done

echo_yellow "The snippet storage path of the user.yaml file will be" $snippetstorage
echo_yellow "The storage for snippets being used is" $snipstorage
echo

## Checking to see what VMBR interface you want to use
# ===================================================
echo_yellow "Please select VMBR to use for your network"
declare -a vmbrs=$(awk '{if(/vmbr/) print $2}' /etc/network/interfaces)
declare -a vmbrsavail=( $(printf "%s\n" "${vmbrs[@]}" | sort -u) )

cnt=${#vmbrsavail[@]}
for (( i=0;i<cnt;i++)); do
    vmbrsavail[i]="${vmbrsavail[i]}"
done
total_num_vmbrs=${#vmbrsavail[@]}
vmbrsavail2=$( echo ${vmbrsavail[@]} )

select option in $vmbrsavail2; do
if [ 1 -le "$REPLY" ] && [ "$REPLY" -le $total_num_vmbrs ];
then
#        echo "The selected option is $REPLY"
#        echo "The selected storage is $option"
        vmbrused=$option
        break;
else
        echo_red "Incorrect Input: Select a number 1-$total_num_vmbrs"
fi
done

echo_yellow "Your network bridge will be on " $vmbrused
echo

## VLAN information block
# ========================
while true
do
    echo_yellow "Do you need to enter a VLAN number? [Y/n] "
    read -r VLANYESORNO

    case $VLANYESORNO in
        [yY][eE][sS]|[yY])
            echo
            while true
            do
                echo_yellow "Enter desired VLAN number for the VM: "
                read VLAN
                if [[ $VLAN -ge 0 ]] && [[ $VLAN -le 4096 ]]
                then
                    break
                fi
            done
            break
            ;;
        [nN][oO]|[nN])
            break
            ;;
        *)
            echo_red "Invalid input, please enter Y/N or yes/no"
            ;;
    esac
done

## Setting DCHP or a Static IP
# ============================
echo
while true
do
    echo_yellow "Enter Yes/Y to use DHCP for IP or Enter No/N to set a static IP address: "
    read DHCPYESORNO

    case $DHCPYESORNO in
        [yY][eE][sS]|[yY])
            break
        ;;
        [nN][oO]|[nN])
            while true; do
                echo_yellow "Enter IP address to use (format example 192.168.1.50/24): "
                read IPADDRESS
                echo_yellow "Please repeat IP address to use (format example 192.168.1.50/24): "
                read IPADDRESS2
                echo
                [ "$IPADDRESS" = "$IPADDRESS2" ] && break
                echo_red "Please try again IP addresses did not match"
            done
            while true; do
                echo_yellow "Enter gateway IP address to use (format example 192.168.1.1): "
                read GATEWAY
                echo_yellow "Please repeate gateway IP address to use (format example 192.168.1.1): "
                read GATEWAY2
                [ "$GATEWAY" = "$GATEWAY2" ] && break
                echo_red "Please try again gateway IP addresses did not match"
            done
            break
        ;;
        *)
            echo_red "Invalid input, please enter Y/n or yes/no"
        ;;
    esac
done

# ====================================================================================================================
## This next section is asking if you need to resize the root disk so its jsut not the base size from the cloud image
# ====================================================================================================================
while true
do
    echo_yellow "Would you like to resize the base cloud image disk (Enter Y/N?) "
    read -r RESIZEDISK

    case $RESIZEDISK in
        [yY][eE][sS]|[yY])
            echo_yellow "Please enter in GB's (exampe 2 for adding 2GB to the resize) how much space you want to add: "
            echo_yellow "Enter size in Gb's: "
            read ADDDISKSIZE
            break
        ;;
        [nN][oO]|[nN])
            RESIZEDISK=n
            break
        ;;
        *)
            echo_red "Invalid input, please enter Y/n or yes/no"
        ;;
    esac
done

# =================================================================================
# Asking if they want to change core ram and stuff other then some defaults I set
# Default cores is 4 and memory is 2048
# =================================================================================
while true
do
    echo_yellow "The default CPU cores is set to 2 and default memory (ram) is set to 2048"
    echo_yellow "Would you like to change the cores or memory (Enter Y/n)? "
    read -r corememyesno

    case $corememyesno in
        [yY][eE][sS]|[yY])
            echo_yellow "Enter number of cores for VM $VMID: "
            read CORES
            echo_yellow "Enter how much memory for the VM $VMID (example 2048 is 2Gb of memory): "
            read MEMORY
            break
        ;;
        [nN][oO]|[nN])
            CORES="2"
            MEMORY="2048"
            break
        ;;
        *)
            echo_red "Invalid input, please enter Y/n or Yes/no"
        ;;
    esac
done

# =========================================================================
# This block is see if they want to add a key to the VM
# and then it checks the path to it and checks to make sure it exists
# =========================================================================
while true
do
    echo_yellow "Do you want to add a ssh key by entering the path to the key? (Enter Y/n) "
    read -r sshyesno

    case $sshyesno in
        [yY][eE][sS]|[yY])
            while true; do
                echo_yellow "Enter the path and key name (path/to/key.pub): "
                read path_to_ssh_key
                echo
                [ -f "$path_to_ssh_key" ] && echo_yellow "It appears to be a good key path." && SSHAUTHKEYS=$(cat "$path_to_ssh_key") && break || echo_red "Does not exist, try again please."
            done
            break
        ;;
        [nN][oO]|[nN])
            break
        ;;
        *)
            echo_red "Invalid input, please enter Y/N or yes/no"
        ;;
    esac
done

# ==============================================================
# Setting if user can use a password to ssh or just keys
# default is set to keys only so must say yes for password ssh
# ==============================================================
while true
do
    echo_yellow "Do you want ssh password authentication (Enter Y/n)? "
    read -r sshpassyesorno

    case $sshpassyesorno in
        [yY][eE][sS]|[yY])
            sshpassallow=True
            break
        ;;
        [nN][oO]|[nN])
            sshpassallow=False
            break
        ;;
        *)
            echo_red "Invalid input, please enter Y/N or yes/no"
        ;;
    esac
done
echo

# ==================================================================
# GOING TO SETUP OTHER PACKAGE INSTALL OPTIONS ON FIRST RUN
# EXAMPLE WOULD BE 
# qm set VMID --agent 1
# qemu-guest-agent
# ==================================================================
while true
do
    echo_yellow "Would you like to install qemu-gust-agent on first run? (Enter Y/n) " 
    read -r qemuyesno

    case $qemuyesno in
        [yY][eE][sS]|[yY])
            QEMUGUESTAGENT=y
            break
        ;;
        [nN][oO]|[nN])
            QEMUGUESTAGENT=n
            break
        ;;
        *)
            echo_red "Invalid input, please enter Y/n or yes/no"
        ;;
    esac
done

# ================================
# Autostart at boot question
# ================================
while true
do
    echo_yellow "Do you want the VM to autostart after you create it here? (Enter Y/n)? "
    read -r AUTOSTARTS

    case $AUTOSTARTS in
        [yY][eE][sS]|[yY])
            AUTOSTART=yes
            break
        ;;
        [nN][oO]|[nN])
            AUTOSTART=no
            break
        ;;
        *)
            echo_red "Invalid input, please enter Y/N or yes/no"
        ;;
    esac
done


# This block of code is for picking which node to have the VM on.
# Couple things it creates the VM on the current node, then migrate's
# to the node you selected, so must have shared storage (at least for
# what I have tested or storages that are the same).  I run
# ceph on my cluster, so its easy to migrate them.
echo
echo_yellow "   PLEASE READ - THIS IS FOR PROXMOX CLUSTERS "
echo_yellow "   This will allow you to pick the Proxmox node for the VM to be on once it is completed "
echo_yellow "   BUT "
echo_yellow "   It will start on the proxmox node you are on and then it will use "
echo_yellow "   qm migrate to the target node (JUST FYI) "
echo

if [ -f "/etc/pve/corosync.conf" ];
then
    localnode=$(cat '/etc/hostname')
    while true
    do
        echo_yellow "Enter Yes/y to pick the node to install the virtual machine onto OR enter No/n to use current node of $localnode : "
        read NODESYESNO

        case $NODESYESNO in
            [yY][eE][sS]|[yY])
                echo_yellow "Please select the NODE to migrate the Virtual Machine to after creation (current node $localnode)"
                nodesavailable=$(pvecm nodes | awk '{print $3}' | sed '/Name/d')
                nodesavailabe2=$(echo "${nodesavailable[@]}")
                declare -a NODESELECTION=( ${nodesavailabe2[@]} )
                total_num_nodes=${#NODESELECTION[@]}
                echo_yellow $total_num_nodes

                select option in $nodesavailabe2; do
                    if [ 1 -le "$REPLY" ] && [ "$REPLY" -le $total_num_nodes ];
                    then
                        migratenode=$option
                        break;
                    else
                        echo_red "Incorrect Input: Select a number 1-$total_num_nodes"
                    fi
                done

                echo_yellow "The Virtual Machine $VMID with be on $migratenode after it is created and moved"
                NODESYESNO=y
                break
            ;;
            [nN][oO]|[nN])
                NODESYESNO=n
                break
            ;;
            *)
                echo_red "Invalid input, please enter Y/n or yes/no"
            ;;
        esac
    done
else
    NODESYESNO=n
fi

# ==========================
# VM Protection: $PROTECTVM
# ==========================
while true
do
    echo_yellow "Do you want VM protection enabled[Y/n]: "
    read -r PROTECTVM

    case $PROTECTVM in
        [yY][eE][sS]|[yY])
            break
        ;;
        [nN][oO]|[nN])
            break
        ;;
        *)
            echo_red "INVALID INPUT, PLEASE ENTER [Y/n]"
        ;;
    esac
done

# ==============
# Select the VM
# ==============
echo
echo_yellow "Please select the cloud image you would like to use"
PS3='Select an option and press Enter: '
options=("Ubuntu Groovy 20.10 Cloud Image" "Ubuntu Focal 20.04 Cloud Image" "Ubuntu Minimal Focal 20.04 Cloud Image" "CentOS 7 Cloud Image" "Debian 10 Cloud Image" "Debian 9 Cloud Image" "Ubuntu 18.04 Bionic Image" "CentOS 8 Cloud Image" "Fedora 32 Cloud Image" "Rancher OS Cloud Image")
select osopt in "${options[@]}"
do
  case $osopt in
        "Ubuntu Groovy 20.10 Cloud Image")
          [ -f "$isostorage/groovy-server-cloudimg-amd64-disk-kvm.img" ] && echo && echo "Moving on you have this cloud image" && break || echo && echo "You do not have this cloud image file so we are downloading it now" && echo && wget https://cloud-images.ubuntu.com/daily/server/groovy/current/groovy-server-cloudimg-amd64-disk-kvm.img -P $isostorage && break
          ;;
        "Ubuntu Focal 20.04 Cloud Image")
          [ -f "$isostorage/focal-server-cloudimg-amd64-disk-kvm.img" ] && echo && echo "Moving on you have this cloud image" && break || echo && echo "You do not have this cloud image file so we are downloading it now" && echo && wget https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64-disk-kvm.img -P $isostorage && break
          ;;
        "Ubuntu Minimal Focal 20.04 Cloud Image")
          [ -f "$isostorage/ubuntu-20.04-minimal-cloudimg-amd64.img" ] && echo && echo "Moving on you have this cloud image" && break || echo && echo "You do not have this cloud image file so we are downloading it now" && echo && wget https://cloud-images.ubuntu.com/minimal/releases/focal/release/ubuntu-20.04-minimal-cloudimg-amd64.img -P $isostorage && break
          ;;
        "CentOS 7 Cloud Image")
          [ -f "$isostorage/CentOS-7-x86_64-GenericCloud.qcow2" ] && echo && echo "Moving on you have this cloud image" && break || echo && echo "You do not have this cloud image file so we are downloading it now" && echo && wget http://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2 -P $isostorage && break
          ;;
        "Debian 10 Cloud Image")
          [ -f "$isostorage/debian-10-openstack-amd64.qcow2" ] && echo && echo "Moving on you have this cloud image" && break || echo && echo "You do not have this cloud image file so we are downloading it now" && echo && wget https://cdimage.debian.org/cdimage/openstack/current-10/debian-10-openstack-amd64.qcow2 -P $isostorage && break
          ;;
        "Debian 9 Cloud Image")
          [ -f "$isostorage/debian-9-openstack-amd64.qcow2" ] && echo && echo "Moving on you have his cloud image" && break || echo && echo "You do not have this cloud image file so we are downloading it now" && echo && wget https://cdimage.debian.org/cdimage/openstack/current-9/debian-9-openstack-amd64.qcow2 -P $isostorage && break
          ;;
        "Ubuntu 18.04 Bionic Image")
          [ -f "$isostorage/bionic-server-cloudimg-amd64.img" ] && echo && echo "Moving on you have his cloud image" && break || echo && echo "You do not have this cloud image file so we are downloading it now" && echo && wget https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img -P $isostorage && break
          ;;
        "CentOS 8 Cloud Image")
          [ -f "$isostorage/CentOS-8-GenericCloud-8.2.2004-20200611.2.x86_64.qcow2" ] && echo && echo "Moving on you have his cloud image" && break || echo && echo "You do not have this cloud image file so we are downloading it now" && echo && wget https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.2.2004-20200611.2.x86_64.qcow2 -P $isostorage && break
          ;;
        "Fedora 32 Cloud Image")
          [ -f "$isostorage/Fedora-Cloud-Base-32-1.6.x86_64.qcow2" ] && echo && echo "Moving on you have his cloud image" && break || echo && echo "You do not have this cloud image file so we are downloading it now" && echo && wget https://download.fedoraproject.org/pub/fedora/linux/releases/32/Cloud/x86_64/images/Fedora-Cloud-Base-32-1.6.x86_64.qcow2 -P $isostorage && break
          ;;
        "Rancher OS Cloud Image")
          [ -f "$isostorage/rancheros-openstack.img" ] && echo && echo "Moving on you have his cloud image" && break || echo && echo "You do not have this cloud image file so we are downloading it now" && echo && wget https://github.com/rancher/os/releases/download/v1.5.5/rancheros-openstack.img -P $isostorage && break
          ;;
        *) echo "invalid option";;
  esac
done
echo_yellow "You have selected Cloud Image $osopt"
echo

# setting the Cloud Image for later for qm info
if [ "$osopt" == "Ubuntu Groovy 20.10 Cloud Image" ];
then
   cloudos=$isostorage'groovy-server-cloudimg-amd64-disk-kvm.img'
elif [ "$osopt" == "Ubuntu Focal 20.04 Cloud Image" ];
then
   cloudos=$isostorage'focal-server-cloudimg-amd64-disk-kvm.img'
elif [ "$osopt" == "Ubuntu Minimal Focal 20.04 Cloud Image" ];
then
   cloudos=$isostorage'ubuntu-20.04-minimal-cloudimg-amd64.img'
elif [ "$osopt" == "CentOS 7 Cloud Image" ];
then
   cloudos=$isostorage'CentOS-7-x86_64-GenericCloud.qcow2'
elif [ "$osopt" == "Debian 10 Cloud Image" ];
then
   cloudos=$isostorage'debian-10-openstack-amd64.qcow2'
elif [ "$osopt" == "Debian 9 Cloud Image" ];
then
   cloudos=$isostorage'debian-9-openstack-amd64.qcow2'
elif [ "$osopt" == "Ubuntu 18.04 Bionic Image" ];
then
   cloudos=$isostorage'bionic-server-cloudimg-amd64.img'
elif [ "$osopt" == "CentOS 8 Cloud Image" ];
then
   cloudos=$isostorage'CentOS-8-GenericCloud-8.2.2004-20200611.2.x86_64.qcow2'
elif [ "$osopt" == "Fedora 32 Cloud Image" ];
then
   cloudos=$isostorage'Fedora-Cloud-Base-32-1.6.x86_64.qcow2'
else [ "$osopt" == "Rancher OS Cloud Image" ];
   cloudos=$isostorage'rancheros-openstack.img'
fi

# =================
# Add to YAML file
# =================

# just in case you are reusing ID's - which most do so...
# next line removes any existing one for this vmid we are setting up
[ -f "$snippetstorage$VMID.yaml" ] && rm $snippetstorage$VMID.yaml

#cloud-config data for user
echo "#cloud-config" >> $snippetstorage$VMID.yaml
echo "hostname: $NEWHOSTNAME" >> $snippetstorage$VMID.yaml
echo "manage_etc_hosts: true" >> $snippetstorage$VMID.yaml
echo "user: $USER" >> $snippetstorage$VMID.yaml
echo "password: $kindofsecure" >> $snippetstorage$VMID.yaml
echo "ssh_authorized_keys:" >> $snippetstorage$VMID.yaml
echo "  - $SSHAUTHKEYS" >> $snippetstorage$VMID.yaml
#echo "$SSHAUTHKEYS" >> $snippetstorage$VMID.yaml
echo "chpasswd:" >> $snippetstorage$VMID.yaml
echo "  expire: False" >> $snippetstorage$VMID.yaml
echo "ssh_pwauth: $sshpassallow" >> $snippetstorage$VMID.yaml
echo "users:" >> $snippetstorage$VMID.yaml
echo "  - default" >> $snippetstorage$VMID.yaml
echo "package_upgrade: true" >> $snippetstorage$VMID.yaml
echo "packages:" >> $snippetstorage$VMID.yaml
if [[ $QEMUGUESTAGENT =~ ^[Yy]$ || $QEMUGUESTAGENT =~ ^[yY][eE][sS] ]]
then
    echo " - qemu-guest-agent" >> $snippetstorage$VMID.yaml
    echo "runcmd:" >> $snippetstorage$VMID.yaml
    echo " - systemctl restart qemu-guest-agent" >> $snippetstorage$VMID.yaml
fi

# create a new VM
qm create $VMID --name $NEWHOSTNAME --cores $CORES --onboot 1 --memory $MEMORY --agent 1,fstrim_cloned_disks=1

if [[ $VLANYESORNO =~ ^[Yy]$ || $VLANYESORNO =~ ^[yY][eE][sS] ]]
then
    qm set $VMID --net0 virtio,bridge=$vmbrused,tag=$VLAN
else
    qm set $VMID --net0 virtio,bridge=$vmbrused
fi

# import the downloaded disk to local-lvm storage

if [[ $vmstorage == "local" ]]
then
   qm importdisk $VMID $cloudos $vmstorage -format qcow2
else
   qm importdisk $VMID $cloudos $vmstorage
fi

if [[ $vmstorage == "local" ]]
then
   qm set $VMID --scsihw virtio-scsi-pci --scsi0 /var/lib/vz/images/$VMID/vm-$VMID-disk-0.qcow2,discard=on
else
   qm set $VMID --scsihw virtio-scsi-pci --scsi0 $vmstorage:vm-$VMID-disk-0,discard=on
fi

# cd drive for cloudinit info
qm set $VMID --ide2 $vmstorage:cloudinit

# make it boot hard drive only
qm set $VMID --boot c --bootdisk scsi0

qm set $VMID --serial0 socket --vga serial0

#Here we are going to set the network stuff from above
if [[ $DHCPYESORNO =~ ^[Yy]$ || $DHCPYESORNO =~ ^[yY][eE][sS] ]]
then
    qm set $VMID --ipconfig0 ip=dhcp
else
    qm set $VMID --ipconfig0 ip=$IPADDRESS,gw=$GATEWAY
fi

# Addding to the default disk size if selected from above
if [[ $RESIZEDISK =~ ^[Yy]$ || $RESIZEDISK =~ ^[yY][eE][sS] ]]
then
    qm resize $VMID scsi0 +"$ADDDISKSIZE"G
fi

if [[ "$PROTECTVM" =~ ^[Yy]$ || "$PROTECTVM" =~ ^[yY][eE][sS] ]]
then
    qm set "$VMID" --protection 1
else
    qm set "$VMID" --protection 0
fi

# Disabling tablet mode, usually is enabled but don't need it
qm set $VMID --tablet 0

# Setting the cloud-init user information
qm set $VMID --cicustom "user=$snipstorage:snippets/$VMID.yaml"

echo
while true
do
 read -r -p "Do you want to turn this into a TEMPLATE VM [Y/n]: " TEMPLATEVM

 case "$TEMPLATEVM" in
     [yY][eE][sS]|[yY])
 break
 ;;
     [nN][oO]|[nN])
 break
        ;;
     *)
 echo "INVALID INPUT, PLEASE ENTER [Y/n]"
 ;;
 esac
done

if [[ "$TEMPLATEVM" =~ ^[Yy]$ || "$TEMPLATEVM" =~ ^[yY][eE][sS] ]]
then
    qm template "$VMID"
    echo "You can now use this as a template"
    exit 0
fi

## Start the VM after Creation!!!!
if [[ $AUTOSTART =~ ^[Yy]$ || $AUTOSTART =~ ^[yY][eE][sS] ]]
then
    qm start $VMID
fi

# Migrating VM to the correct node if selected
if [[ $NODESYESNO =~ ^[Yy]$ || $NODESYESNO =~ ^[yY][eE][sS] ]]
then
    qm migrate $VMID $migratenode --online
fi
