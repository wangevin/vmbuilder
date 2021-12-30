#!/bin/bash
#set -x -v -o -e
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
if [ "$EUID" -ne 0 ];
then 
	echo "Please run as root"
	exit
else
	TEXT_RESET='\e[0m'
	TEXT_YELLOW='\e[0;33m'
	TEXT_RED='\e[1;31m'
fi

#
# ==================
# Helper Functions
# ==================
#

# If  NOECHO="y" then will not echo input, ala password. Defaults to echo.
ask()
{
	if [ $# -eq 0 ]; then
		echo -e "\e[1;31mNo arguments supplied, Format: ask <variable> <prompt>\e[0m"
	elif [ $# -ne 2 ]; then
		echo -e "\e[1;31mInvalid number of arguments supplied, Format: ask <variable> <prompt>\e[0m"
	fi

	while true ; do
		echo -n "$2 "

        if [ "$NOECHO" = "y" ];
        then
            read -r -s INPUT
            echo ""
        else
            read -r INPUT
        fi

        if [ -z "$INPUT" ]; then
                echo -e "\e[1;31mNo input provided\e[0m"
		else
			break
        fi
	done

    declare -n VAR_PTR=$1
	VAR_PTR="$INPUT"
}

ask-number()
{
	while true; do
		ask $1 "$2"
		if ! [[ "${!1}" =~ ^[+-]?[0-9]+\.?[0-9]*$ ]]; then
			echo -e "\e[1;31mInput must be a number\e[0m"
		else
			break
		fi
	done
}

ask-yes-no()
{
	while true; do
		ask ANSWER "$2 [Y/n]"
		case "$ANSWER" in
        	[yY][eE][sS]|[yY])
				RESPONSE="y"
				break
				;;
			[nN][oO]|[nN])
				RESPONSE="n"
            	break
        		;;
        	*)
            	echo -e "\e[1;31mInvalid input, please enter Y/N or yes/no\e[0m"
            	;;
    	esac
	done
	declare -n VAR_PTR=$1
	VAR_PTR="$RESPONSE"
}

ask-verify()
{
	while true; do
		ask FIRST_TIME "$2"
		ask SECOND_TIME "$2 (Repeat to Verify)"
		if [ "$FIRST_TIME" = "$SECOND_TIME" ]; then
			declare -n VAR_PTR=$1
			VAR_PTR="$FIRST_TIME"
			break
		else
			echo -e "\e[1;31mPlease try again as inputs did not match\e[0m"
		fi
	done
    NOECHO=""
}

ask-verify-noecho()
{
    NOECHO="y"

    ask-verify RESPONSE "$2"

    declare -n VAR_PTR=$1
	VAR_PTR="$RESPONSE"

    NOECHO=""
}

ask-boolean()
{
	while true; do
		ask ANSWER "$2 [T/F]"
		case "$ANSWER" in
        	[tT][rR][uU]|[eE])
				RESPONSE=True
				break
				;;
			[fF][aA]|[lL][sS][eE])
				RESPONSE=False
            	break
        		;;
        	*)
            	echo -e "\e[1;31mInvalid input, please enter T/F or true/false\e[0m"
            	;;
    	esac
	done
	declare -n VAR_PTR=$1
	VAR_PTR="$RESPONSE"
}

# Install package if not installed (NOT NEEDED BUT PUT IN GITHUB)
install()
{
	echo "Installing $1 ..."
	# Test if no data passed
	if [ -z $1 ];
	then
		echo_red "No Package specified"
	else
		dpkg -s $1 &> /dev/null
		if [ $? -eq 0 ]; 
		then
			echo "Package $1 already installed!"
		else
			sudo apt install $1 -y
		fi
	fi
}
# Add a packate to an Image
add_to_image()
{
	echo "Add Package $2 to image $1 ..."
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
# Get NEWHOSTNAME
# =========================================================
while true; do
    ask NEWHOSTNAME "Enter desired hostname for the Virutal Machine:"
    if [[ ! $NEWHOSTNAME == *['!'@#\$%^\&*()\_+\']* ]];then
      break;
   else
      echo -e "\e[1;31mContains a character not allowed for a hostname, please try again\e[0m"
   fi
done
echo ""


# =========================================================
# Get List of Exixting VMID's for Verification
# =========================================================
echo -n "Please Wait: Gathering information to verify the Virtual Machine ID (VM ID) ."
# Get the VMID's currently used
vmidnext=$(pvesh get /cluster/nextid)
echo -n "."
declare -a vmidsavail=$(pvesh get /cluster/resources | awk '{print $2}' | sed '/storage/d' | sed '/node/d' | sed '/id/d' | sed '/./,/^$/!d' | cut -d '/' -f 2 | sed '/^$/d')
echo -n "."
#echo ${vmidsavail[@]}

for ((i=1;i<=99;i++));
do
   systemids+=$(echo " " $i)
done

USEDIDS=("${vmidsavail[@]}" "${systemids[@]}")
echo -n "."
declare -a all=( echo ${USEDIDS[@]} )
echo "."

# =========================================================
# Get VMID
# =========================================================
while true; do
    ask-number number "Enter Virtual Machine ID (VM ID) number:"
    if [[ " ${all[*]} " != *" ${number} "* ]]
    then
        VMID=${number:-$vmidnext}
        break
    else
        echo -e "\e[1;31mEnter a different VM ID number because either $number is already in use or reserved by the system\e[0m"
    fi
done
echo ""


# =========================================================
# Get USER and PASSWORD
# =========================================================
ask-verify USER "Enter username to log into new VM:"
ask-verify-noecho PASSWORD "Please enter password for the user $USER:"
# really just hashing the password so its not in plain text in the usercloud.yaml
# that is being created during the process
# really should do keys for most secure
kindofsecure=$(openssl passwd -1 -salt SaltSalt $PASSWORD)
echo ""


# =========================================================
# Get vmstorage - Selecting the Storage the VM will run on
# =========================================================
echo "Please select the storage the VM will run on?"
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

echo "The storage you selected for the VM is $vmstorage"
echo ""


# =========================================================
# Get isostorage - Selecting the ISO Storage location
# =========================================================
echo "Please select ISO storage location"
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
        echo "The selected option is $REPLY"
        echo "The selected storage is $option"
        isostorage=$option
        break;
else
        echo_red "Incorrect Input: Select a number 1-$total_num_storage_paths"
fi
done

echo "The cloud image will be downloaded to " $isostorage " or look there if already downloaded"
echo ""


# =========================================================================================
# Get snippetstorage and snipstorage - $VMID.yaml config location and storage for snippets
# =========================================================================================
echo "Please select the storage that has snippets available"
echo "If you pick one that does not have it enabled the VM being created will not have all the"
echo "user settings (user name, password , keys) so if you need to check in the GUI click on Datacenter"
echo "then click on storage and see if enabled, if not you need to enable it on the storage you want it"
echo "to be placed on.  There will be two questions for snippet setup. One for the actual locaiton to put the user.yaml and the"
echo "second for the storage being used for snippets."
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
echo "The snippet storage location will be " $snippetstorage "here, which will hold the user data yaml file for each VM"
echo
echo "Now that we have selected the snippet storage path ($snippetstorage) we need to actually select the storage that this path is on."
echo "Make sure the path picked and the storage picked are one in the same or it will fail."
echo "example /var/lib/vz/snippets/ is "local" storage"
echo
echo "Please select the storage the snippets will be on"
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

echo "The snippet storage path of the user.yaml file will be" $snippetstorage
echo "The storage for snippets being used is" $snipstorage
echo ""


# ============================================================
# Get vmbrused - Selecting the VMBR interface you want to use
# ============================================================
echo "Please select VMBR to use for your network"
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
        echo -e "$TEXT_RED Incorrect Input: Select a number 1-$total_num_vmbrs $TEXT_RESET"
fi
done

echo "Your network bridge will be on " $vmbrused
echo ""


# =========================================================
# Get VLAN 
# =========================================================
ask-yes-no VLANYESORNO "Do you need to enter a VLAN number?"
if [ "$VLANYESORNO" = "y" ]; then
    ask-number VLAN "Enter desired VLAN number for the VM:"
fi
echo ""


# =========================================================
# Get DHCPYESORNO, IPADDRESS and GATEWAY
# =========================================================
ask-yes-no DHCPYESORNO "Enter Yes/Y to use DHCP for IP or Enter No/N to set a static IP address:"
if [ "$DHCPYESORNO" = "n" ]; then
    ask-verify IPADDRESS "Enter IP address to use (format example 192.168.1.50/24):"
    ask-verify GATEWAY "Enter gateway IP address to use (format example 192.168.1.1):"
fi
echo ""


# =====================================================================================================================================================
# Get RESIZEDISK and ADDDISKSIZE -  This next section is asking if you need to resize the root disk so its jsut not the base size from the cloud image
# =====================================================================================================================================================
ADDDISKSIZE=""
ask-yes-no RESIZEDISK "Would you like to resize the base cloud image disk"
if [ "$RESIZEDISK" = "y" ]; then
    ask-number ADDDISKSIZE "Enter size in Gb's (Example 2 for adding 2GB to the resize):"
fi
echo ""


# =================================================================================
# Get COORES and MEMORY
# Asking if they want to change core ram and stuff other then some defaults I set
# Default cores is 4 and memory is 2048
# =================================================================================
CORES="2"
MEMORY="2048"
echo "The default CPU cores is set to $CORES and default memory (ram) is set to $MEMORY"
ask-yes-no corememyesno "Would you like to change the cores or memory?"
if [ "$corememyesno" = "y" ]; then
    ask-number CORES "Enter number of cores for VM $VMID:"
    ask-number MEMORY "Enter how much memory for the VM $VMID (example 2048 is 2Gb of memory):"
fi
echo ""


# =========================================================================
# Get SSHAUTHKEYS
# This block is see if they want to add a key to the VM
# and then it checks the path to it and checks to make sure it exists
# =========================================================================
ask-yes-no sshyesno "Do you want to add a ssh key by entering the path to the key?"
if [ "$sshyesno" = "y" ]; then
    while true
    do
        ask path_to_ssh_key "Enter the path and key name (path/to/key.pub):"
        if [ -f "$path_to_ssh_key" ]; then
            echo "It appears to be a good key path."
            SSHAUTHKEYS=$(cat "$path_to_ssh_key")
            break
        else
            echo -e "$TEXT_RED Does not exist, try again please. $TEXT_RESET"
        fi
    done
fi
echo ""


# ==============================================================
# Set sshpassallow=True
# Setting if user can use a password to ssh or just keys
# default is set to keys only so must say yes for password ssh
# ==============================================================
sshpassallow=False
ask-yes-no sshpassyesorno "Do you want ssh password authentication [Y/n]:"
if [ "$sshpassyesorno" = "y" ]; then
    sshpassallow=True
fi
echo ""


# ==================================================================
# Get QEMUGUESTAGENT
# GOING TO SETUP OTHER PACKAGE INSTALL OPTIONS ON FIRST RUN
# EXAMPLE WOULD BE 
# qm set VMID --agent 1
# qemu-guest-agent
# ==================================================================
QEMUGUESTAGENT=n
ask-yes-no qemuyesno "Would you like to install qemu-gust-agent on first run?"
if [ "$qemuyesno" = "y" ]; then
    QEMUGUESTAGENT=y
fi
echo ""


# ================================
# Get AUTOSTART
# Autostart at boot question
# ================================
AUTOSTART=no
ask-yes-no AUTOSTARTS "Do you want the VM to autostart after you create it here?"
if [ "$AUTOSTARTS" = "y" ]; then
    AUTOSTART=yes
fi
echo ""


# =========================================================================
# Get NODESYESNO, migratenode
# This block of code is for picking which node to have the VM on.
# Couple things it creates the VM on the current node, then migrate's
# to the node you selected, so must have shared storage (at least for
# what I have tested or storages that are the same).  I run
# ceph on my cluster, so its easy to migrate them.
# =========================================================================
echo
echo "   PLEASE READ - THIS IS FOR PROXMOX CLUSTERS "
echo "   This will allow you to pick the Proxmox node for the VM to be on once it is completed "
echo "   BUT "
echo "   It will start on the proxmox node you are on and then it will use "
echo "   qm migrate to the target node (JUST FYI) "
echo

NODESYESNO=n
if [ -f "/etc/pve/corosync.conf" ];
then
    localnode=$(cat '/etc/hostname')
    while true
    do
        ask-yes-no NODESYESNO "Enter Yes/y to pick the node to install the virtual machine onto OR enter No/n to use current node of $localnode:"
        if [ "$NODESYESNO" = "y" ]; then
            while true
            do
                echo "Please select the NODE to migrate the Virtual Machine to after creation (current node $localnode)"
                nodesavailable=$(pvecm nodes | awk '{print $3}' | sed '/Name/d')
                nodesavailabe2=$(echo "${nodesavailable[@]}")
                declare -a NODESELECTION=( ${nodesavailabe2[@]} )
                total_num_nodes=${#NODESELECTION[@]}
                echo $total_num_nodes

                select option in $nodesavailabe2; do
                    if [ 1 -le "$REPLY" ] && [ "$REPLY" -le $total_num_nodes ];
                    then
                        migratenode=$option
                        break;
                    else
                        echo_red "Incorrect Input: Select a number 1-$total_num_nodes"
                    fi
                done
            done

            echo "The Virtual Machine $VMID with be on $migratenode after it is created and moved"
            NODESYESNO=y
        fi
    done
fi
echo ""


# ==========================
# Get PROTECTVM
# VM Protection: $PROTECTVM
# ==========================
ask-yes-no PROTECTVM "Do you want VM protection enabled?"
echo ""


# ==============
# Select the VM
# ==============
echo
echo "Please select the cloud image you would like to use"
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
echo "You have selected Cloud Image $osopt"
echo ""


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


display-var()
{
    echo -e "$1\t\t${!1}"
}
echo "Stopping before creating VM to validate all inputs"
echo ""
echo ""
echo "Here are the required variables and Values"

display-var VMID
display-var NEWHOSTNAME
display-var CORES
display-var MEMORY
display-var VLANYESORNO
display-var VMID
display-var vmbrused
display-var VLAN
display-var vmstorage
display-var VMID
display-var cloudos
display-var vmstorage
display-var DHCPYESORNO
display-var IPADDRESS
display-var GATEWAY
display-var RESIZEDISK
display-var ADDDISKSIZE
display-var PROTECTVM
display-var snipstorage
display-var TEMPLATEVM
display-var AUTOSTART
display-var NODESYESNO
display-var migratenode

exit
#=========================================================================================================================================





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
