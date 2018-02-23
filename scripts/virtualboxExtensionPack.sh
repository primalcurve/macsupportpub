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
/bin/echo "The VirtualBox vboxmanage command line utility version is " $vboxmanageVersion

releaseNumber="${vboxmanageVersion%%r*}"
/bin/echo "Release number is " "$releaseNumber"
buildNumber="${vboxmanageVersion##*r}"
/bin/echo "Build number is " "$buildNumber"

fileToDownload="Oracle_VM_VirtualBox_Extension_Pack-$releaseNumber-$buildNumber.vbox-extpack"
/bin/echo "File to Download is :" "$fileToDownload"

echo "Downloading" "${fileToDownload}" "using the following syntax:" /usr/bin/curl -sS http://download.virtualbox.org/virtualbox/"$releaseNumber"/"$fileToDownload" -o "/tmp/$fileToDownload"
/usr/bin/curl -sS http://download.virtualbox.org/virtualbox/"$releaseNumber"/"$fileToDownload" -o "/tmp/$fileToDownload"

extensionpackSHASumSource=$(/usr/bin/curl -sS -A 'Macintosh' 'https://www.virtualbox.org/download/hashes/'"${releaseNumber}"'/SHA256SUMS' | /usr/bin/grep "${fileToDownload}" | /usr/bin/head -c 64)
extensionpackSHASumCheck=$(/usr/bin/shasum -a 256 "/tmp/$fileToDownload" | /usr/bin/head -c 64)

if [[ "${extensionpackSHASumSource}" != "${extensionpackSHASumCheck}" ]]
	then
		/bin/echo "SHA256 CheckSum Error. Quitting now."
		exit 0
	else
		/bin/echo "The SHA256SUM of the Extension Pack matches the source. Continuing."
fi

# The following bit of code expands the Extension Pack tarball and gets a 256 shasum for the license.txt file. This is used to automatically accept the license in the final step.
/bin/mkdir -p '/tmp/Oracle_VM_VirtualBox_Extension_Pack'

/usr/bin/tar xzC '/tmp/Oracle_VM_VirtualBox_Extension_Pack' -f "/tmp/$fileToDownload"

if [[ -e '/tmp/Oracle_VM_VirtualBox_Extension_Pack/ExtPack-license.txt' ]]
	then
		licenseSum=$(/usr/bin/shasum -a 256 '/tmp/Oracle_VM_VirtualBox_Extension_Pack/ExtPack-license.txt' | /usr/bin/head -c 64)
	else
		/bin/echo 'License file could not be found. Extensions will have to be installed manually. Exiting quietly.'
		exit 0
fi

"${vboxManageCLI}" extpack install "/tmp/$fileToDownload" --replace --accept-license="${licenseSum}"

exit 0