#!/bin/bash
#
#  deletePasswordFromKeychain.sh
#  
#
#  Created 08/29/2017 	by 	Glynn Lane 		primalcurve
#				
#
####################################################
#--------------------------------------------------#
# Table of Contents
#--------------------------------------------------#
#
# The purpose of this script is to remove all entries
# of a specified Internet Password from a user's 
# keychain.
#
#--------------------------------------------------#
####################################################


####################################################
#--------------------------------------------------#
# Hard Coded Variables
#--------------------------------------------------#
####################################################

internetPasswordItem=''

if [[ "${4}" != "" ]] && [[ "${internetPasswordItem}" == "" ]]
	then
    	internetPasswordItem="$4"
fi

####################################################
#--------------------------------------------------#
# Functions
#--------------------------------------------------#
####################################################

getConsoleUser ()
{
	# Get Console User by piping the output of ls of the console virtual device into an array. Then pulling the array value with the username into the consoleUser variable, which will be used by the rest of the script.
	consoleUser=$(python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')
	/bin/echo "Current Console User is:" "${consoleUser}"
}


####################################################
#--------------------------------------------------#
# Script Logic
#--------------------------------------------------#
####################################################

getConsoleUser

for user in $(ls -1 /Users | grep -v Shared)
	do
		totalDeleted=-1
		/bin/echo
		/bin/echo "Processing keychain for user" "${user}"
		if [[ -e '/Users/'"${user}"'/Library/Keychains/login.keychain-db' ]]
			then
				until [[ "${deleteInternetPasswordResults}" == *"The specified item could not be found in the keychain."* ]]
					do
						deleteInternetPasswordResults=$(2>&1 /usr/bin/security delete-internet-password -s "${internetPasswordItem}" '/Users/'"${user}"'/Library/Keychains/login.keychain-db')
						totalDeleted=$(expr $totalDeleted + 1 )
					done
					/bin/echo "Total number of keychain entries deleted:" "${totalDeleted}"
		elif [[ -e '/Users/'"${user}"'/Library/Keychains/login.keychain' ]]
			then
				until [[ "${deleteInternetPasswordResults}" == *"The specified item could not be found in the keychain."* ]]
					do
						deleteInternetPasswordResults=$(2>&1 /usr/bin/security delete-internet-password -s "${internetPasswordItem}" '/Users/'"${user}"'/Library/Keychains/login.keychain')
						totalDeleted=$(expr $totalDeleted + 1 )
					done
					/bin/echo "Total number of keychain entries deleted:" "${totalDeleted}"
			else
				/bin/echo "No keychain found for" "${user}"
		fi
		
	done

exit 0