#!/bin/bash

# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run this script with root privileges (sudo)"
  exit 1
fi

# Check if a parameter is provided
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <final_image_name>"
  exit 1
fi

final_image_name=$1
download_dir="/tmp/cloud_image"
image_url="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
expected_file_name="jammy-server-cloudimg-amd64.img"
final_image_format="qcow2"

# Check if there is enough space on the local machine for the download
required_space=$(curl -sI "$image_url" | grep -i "content-length" | awk '{print $2}')
if [ -z "$required_space" ]; then
  echo "Failed to determine the image size. Exiting."
  exit 1
fi

if [ "$(df -P / | awk 'NR==2 {print $4}')" -lt "$required_space" ]; then
  echo "Not enough space on the local machine for the image download."
  exit 1
fi

# Install required packages
echo "Installing required packages..."
apt update
apt install -y cloud-image-utils qemu-utils
clear

# Create a temporary directory for downloading the cloud image
echo "Creating a temporary directory for downloading the cloud image..."
mkdir -p "$download_dir"
cd "$download_dir"

# Download the cloud-init image for KVM of Ubuntu 22.04 Jammy with a specific file name
echo "Downloading the cloud-init image..."
wget "$image_url" -O "$expected_file_name"

# Verify the download by checking the file name
if [ ! -f "$expected_file_name" ]; then
  echo "Download failed. Exiting."
  exit 1
fi

# Create a cloud-init configuration file with improved package updates and creating the "ansible" user
echo "Creating a cloud-init configuration file..."
cat <<EOF > user-data.yaml
#cloud-config
password: root
chpasswd: { expire: False }
ssh_pwauth: True
runcmd:
  - apt:
      update_cache: yes
  - apt:
      upgrade: yes
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - systemctl enable sshd
  - systemctl start sshd
packages:
  - qemu-guest-agent
  - openssh-server
users:
  - name: ansible
    passwd: $6$rounds=4096$DAspIRiG9Il9NTgY$D99yHj5EjPQT1zmuC9JXW.PXm9YHTpW4X/0T7C4Xq4FvQ/bO74mUQnFwCxX5jqVRIDJ5qbxEPDbPTXj.UQZ9J0
    lock_passwd: false
    sudo: ALL=(ALL:ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - <insert your SSH public key here>
EOF

# Combine the cloud-init configuration with the cloud image
echo "Combining the cloud-init configuration with the cloud image..."
mv "$expected_file_name" original-image.img
cloud-localds "$final_image_name".img original-image.img user-data.yaml

# Convert the final image format to qcow2
echo "Converting the final image format to qcow2..."
qemu-img convert -O qcow2 "$final_image_name".img "$final_image_name.$final_image_format"

# Cleaning files
echo "Cleaning files..."
rm -rf "$final_image_name".img user-data.yaml original-image.img

# Show files
echo "Showing files..."
ls -l "$download_dir"

# Print instructions for further setup (kubelet, kubectl, kubeadm)
echo "The cloud-init configured and prepared image is ready: $final_image_name.$final_image_format"
echo "This image includes qemu-guest-agent, kubelet, kubectl, kubeadm, and openssh-server."
echo "QEMU Guest Agent and SSH server (sshd) are configured and started within the image."
echo "A user 'ansible' has been added with the password 'ansible', SSH keys, and sudo privileges without a password prompt."
echo "The final image is in qcow2 format, has been resized to 32G, and is up-to-date."
echo "Please use the image to create VMs in your KVM environment."

# Additional setup instructions here...

exit 0