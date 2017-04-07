#!/bin/bash
#
#  FileVault Password Sync
#  
#
#  Created 04/06/2017 by 	Glynn Lane 		primalcurve
#				
####################################################
#--------------------------------------------------#
# Purpose
#--------------------------------------------------#
#
# Make a table of historical MAC addresses that are 
# human readable and useful for techs. Put in the JSS.
#
#--------------------------------------------------#
####################################################

unset ethernetDevices
unset macAddresses

# You will need to change this value for this script to work in your environment!
saveDir="/Path/To/Folder/"

# This is an important part of this EA. If you get devices called something else--
# like if Apple decides that networking is now "Potato Farming," you can add a 
# new line to the below to include it.
#
# For example:
#
# saveIFS="$IFS"
# IFS=$'\n'
# ethernetDevices+=($(/usr/sbin/networksetup -listallnetworkservices | /usr/bin/grep "Ethernet"))
# ethernetDevices+=($(/usr/sbin/networksetup -listallnetworkservices | /usr/bin/grep '\<USB.*LAN\>'))
# ethernetDevices+=($(/usr/sbin/networksetup -listallnetworkservices | /usr/bin/grep "Potato Farming"))
# IFS="$saveIFS"
#
# The main thing is the plus sign "+" in front of the equals sign defining the array. 
# This APPENDS values to the array. So you can keep adding newlines to your heart's 
# content and it will collect the data. You could even add Wi-Fi if you wanted.

saveIFS="$IFS"
IFS=$'\n'
ethernetDevices+=($(/usr/sbin/networksetup -listallnetworkservices | /usr/bin/grep "Ethernet"))
ethernetDevices+=($(/usr/sbin/networksetup -listallnetworkservices | /usr/bin/grep '\<USB.*LAN\>'))
IFS="$saveIFS"

if [[ ! -e "${saveDir}"/LastMACAddress ]]
	then
		/usr/bin/touch "${saveDir}"/LastMACAddress
fi

for service in "${ethernetDevices[@]}"
	do
		addressValue=($(/usr/sbin/networksetup -getinfo "$service" | /usr/bin/grep Ethernet))
		# If a device was previously connected, but is not currently connected, it shows up in
		# the service order, but with a MAC Address of "(null)". This script skips it to maintain
		# the historical data as that is what we want most.
		if [[ "${addressValue[2]}" != "(null)" ]] && [[ ! -z "${addressValue[2]}" ]]
			then
				/bin/mv "${saveDir}"/LastMACAddress "${saveDir}"/LastMACAddressRead
				/usr/bin/grep -v "$service" "${saveDir}"/LastMACAddressRead > "${saveDir}"/LastMACAddress
				/bin/echo "The last reported MAC Address for" "$service" "was" "${addressValue[2]}" "on" "$(/bin/date)" >> "${saveDir}"/LastMACAddress
				/bin/rm "${saveDir}"/LastMACAddressRead
		fi
	done

macAddresses=$(/bin/cat "${saveDir}"/LastMACAddress)

if [[ ! -z "${macAddresses[*]}" ]]
	then
		echo "<result>"${macAddresses[*]}"</result>"
	else
		echo "<result>No Wired Ethernet Addresses Have Been Collected Yet</result>"
fi

exit 0
