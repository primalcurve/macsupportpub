#!/bin/bash
# Created 10-12-2016
# Updated 03-22-2017
# Updated 02-23-2018
# primalcurve

if [[ -e /usr/local/bin/vboxmanage ]]
	then
		vboxManageCLI="/usr/local/bin/vboxmanage"
elif [[ -e /usr/local/bin/VBoxManage ]]
	then
		vboxManageCLI="/usr/local/bin/VBoxManage"
fi

vboxmanageVersion=$("${vboxManageCLI}" -v)
echo 'The VirtualBox vboxmanage command line utility version is' "${vboxmanageVersion}"

releaseNumber="${vboxmanageVersion%%r*}"
echo 'Release number is' "${releaseNumber}"
buildNumber="${vboxmanageVersion##*r}"
echo 'Build number is' "${buildNumber}"

fileToDownload='Oracle_VM_VirtualBox_Extension_Pack-'"${releaseNumber}"'-'"${buildNumber}"'.vbox-extpack'
echo 'File to Download is :' "${fileToDownload}"

echo 'Downloading' "${fileToDownload}" 'using the following syntax: curl -sS http://download.virtualbox.org/virtualbox/'"${releaseNumber}"'/'"${fileToDownload}"'' -o /tmp/"${fileToDownload}"''
curl -sS 'http://download.virtualbox.org/virtualbox/'"${releaseNumber}"'/'"${fileToDownload}" -o '/tmp/'"${fileToDownload}"

extensionpackSHASumSource=$(curl -sS -A 'Macintosh' 'https://www.virtualbox.org/download/hashes/'"${releaseNumber}"'/SHA256SUMS' | grep "${fileToDownload}" | head -c 64)
extensionpackSHASumCheck=$(shasum -a 256 '/tmp/'"${fileToDownload}" | head -c 64)

if [[ "${extensionpackSHASumSource}" != "${extensionpackSHASumCheck}" ]]
	then
		echo 'SHA256 CheckSum Error. Quitting now.'
		exit 0
	else
		echo 'The SHA256SUM of the Extension Pack matches the source. Continuing.'
fi

# The following bit of code expands the Extension Pack tarball and gets a 256 shasum for the license.txt file. This is used to automatically accept the license in the final step.
mkdir -p '/tmp/Oracle_VM_VirtualBox_Extension_Pack'

tar xzC '/tmp/Oracle_VM_VirtualBox_Extension_Pack' -f '/tmp/'"${fileToDownload}"

if [[ -e '/tmp/Oracle_VM_VirtualBox_Extension_Pack/ExtPack-license.txt' ]]
	then
		licenseSum=$(shasum -a 256 '/tmp/Oracle_VM_VirtualBox_Extension_Pack/ExtPack-license.txt' | head -c 64)
	else
		echo 'License file could not be found. Extensions will have to be installed manually. Exiting quietly.'
		exit 0
fi

"${vboxManageCLI}" extpack install '/tmp/'"${fileToDownload}" --replace --accept-license="${licenseSum}"

exit 0