#!/bin/bash
#
#  FileVault Password Sync
#  
#
#  Created 11/29/16 by 	Ben Janowski	Janowski
#						Minev Mehta		typingpool
#						Glynn Lane 		primalcurve
#				
#  Credits, help, and inspiration: Elliot Jordan <elliot@lindegroup.com> with https://github.com/homebysix/jss-filevault-reissue
#
####################################################
#--------------------------------------------------#
# Table of Contents
#--------------------------------------------------#
#
# The purpose of this script it to allow the user to 
# be able to put their FileVault and Login Window
# passwords back into sync.
#
# 1. Verify AD connection
# 2. Verify FileVault is on and account is FV2 enabled
# 3. Prompt user for newest password & validate it
# 4. Create a temporary FileVault user and authorize for FileVault
# 5. Prompt user for FV2 password
# 6. Verify service unlock account is enabled
# 7. Use temp user to remove/re-add user with 
#    the newest password
# 8. Performs some cleanup
# 9. Reboot to confirm pw sync
#
#--------------------------------------------------#
####################################################


####################################################
#--------------------------------------------------#
# Hard Coded Variables - Change These
#--------------------------------------------------#
####################################################

# This script uses CocoaDialog for user interaction. You can rewrite it to use osascript, but if you 
# want to use this out of the box, you'll either have to install CocoaDialog with this policy, or 
# have a separate policy you call with a trigger. I prefer the latter as I don't have to wait 
# for the PKG to download and install every single time. 

cocoaDialogInstalledByThisPolicy="No"
cocoaDialogTrigger="installcocoadialog"
cocoaDialogPath="/Where/You/Install/CocoaDialog.app/Contents/MacOS/CocoaDialog"

# Change this if your AD is not called "AD"
activeDirectory="/Active Directory/AD/All Domains"

# Change this if you bundle CocoaDialog with this policy. Otherwise the script will call for the "$cocoaDialogTrigger" policy trigger.
cocoaDialogInstalledByThisPolicy="No"
cocoaDialogTrigger="installcocoadialog"

####################################################
#--------------------------------------------------#
# Bash Functions
#--------------------------------------------------#
####################################################

installCocoaDialog ()
{
	if [[ ! -e "${cocoaDialogPath}" ]]
		then
			/bin/echo
			/bin/echo "CocoaDialog is missing from this computer. Invoking the" "$cocoaDialogTrigger" "trigger."
			/usr/local/bin/jamf policy -trigger "$cocoaDialogTrigger"
			/bin/echo
		else
			/bin/echo
			/bin/echo "CocoaDialog is already installed on this computer. Continuing."
			/bin/echo
	fi
}


getConsoleUser ()
{
	# Get Console User by piping the output of ls of the console virtual device into an array. Then pulling the array value with the username into the consoleUser variable, which will be used by the rest of the script.
	lsDevConsole=($(ls -l /dev/console)) 
	consoleUser=${lsDevConsole[2]}
	/bin/echo "Current Console User is:" "${consoleUser}"
}


createFileVaultUser ()
{
	# Use dscl to create a user with no shell access and no user directory. This user will be able to unlock FileVault, but will have no other rights.

	random_Pass=$(/bin/date +%s | /usr/bin/shasum -a 512 | /usr/bin/base64 | /usr/bin/head -c 24)

	/usr/bin/dscl . -create /Users/fvunlock
	/usr/bin/dscl . -create /Users/fvunlock uid 300
	/usr/bin/dscl . -create /Users/fvunlock gid 300
	/usr/bin/dscl . -create /Users/fvunlock NFSHomeDirectory /var/empty
	/usr/bin/dscl . -create /Users/fvunlock UserShell /usr/bin/false
	/usr/bin/dscl . -create /Users/fvunlock RealName "fvunlock"
	/usr/bin/dscl . -passwd /Users/fvunlock "${random_Pass}"

	/usr/bin/logger -s -p6 "FileVault Sync: fvunlock created"
}


deleteFVUnlockUser ()
{
	checkDSforfvunlock=($(/usr/bin/dscl . -read /Users/fvunlock | /usr/bin/grep RecordName))
	fvunlockRecordName="${checkDSforfvunlock[1]}"
	if [[ "${fvunlockRecordName}" == "fvunlock" ]]
		then
			removeUnlockUserFromFV
			/usr/bin/dscl . -delete /Users/fvunlock
			/usr/bin/logger -s -p6 "FileVault Sync: fvunlock user removed"
		else
			/bin/echo "fvunlock is not present. Continuing."
	fi
}


isComputerBound ()
{
	# The RecordName is the User Name in AD. So basically, this function just asks for the user name's user name. If they match, then it continues. Dead simple.
	queryADResults=($(/usr/bin/dscl "${activeDirectory}" -read /Users/"${consoleUser}" RecordName))
	queryADResultsRecordName="${queryADResults[1]}"

	if [[ "${queryADResultsRecordName}" == "${consoleUser}" ]]
		then
			computerBound="Yes"
		else
			computerBound="No"
	fi
}


checkLoginPassword ()
{
	unset numberTries
	unset loginPasswordError
	until [[ "$numberTries" == "3" ]]
		do
			numberTries=$(($numberTries + 1))
			if [[ "$numberTries" == "1" ]]
				then
					getCurrentLoginPassword=($("$cocoaDialogPath" inputbox --title "FileVault Password Sync" \
						--icon gear --no-show --informative-text "Please enter your newest password. This is attempt number "$numberTries"." \
						--button1 "OK" --button2 "Cancel" --width 430 --float))
					getCurrentLoginPasswordButton="${getCurrentLoginPassword[0]}"
					if [[ "$getCurrentLoginPasswordButton" == "2" ]]
						then
							/bin/echo "The user clicked Cancel at the password dialog. Failing because this MUST be fixed."
							"$cocoaDialogPath" msgbox --title "FileVault Password Sync" \
								--icon gear --no-show --text "Confused?" \
								--informative-text "We're looking for the password you use to log in." \
								--button1 "OK" --width 430 --float
							exit 1
					fi
				else
					getCurrentLoginPassword=($("$cocoaDialogPath" inputbox --title "FileVault Password Sync" \
						--icon gear --no-show --informative-text "That Password was incorrect. Please enter your network password. This is attempt number "$numberTries"." \
						--button1 "OK" --button2 "Cancel" --width 430 --float))
					getCurrentLoginPasswordButton="${getCurrentLoginPassword[0]}"
					if [[ "$getCurrentLoginPasswordButton" == "2" ]]
						then
							/bin/echo "The user clicked Cancel at the password dialog. Failing because this MUST be fixed."
							"$cocoaDialogPath" msgbox --title "FileVault Password Sync" \
								--icon gear --no-show --text "Confused?" \
								--informative-text "We're looking for the password you use to log in." \
								--button1 "OK" --width 430 --float
							exit 1
					fi
			fi
			/bin/echo "The user has tried entering their login password" "$numberTries" "times."
			currentLoginPassword="${getCurrentLoginPassword[1]}"
			
			#
			# This is the meat of this function. It tries the password against the AD. No news is good news.
# # # # # # #
			
			checkCurrentLoginPassword=$(2>&1 /usr/bin/dscl "${activeDirectory}" -authonly "$consoleUser" "$currentLoginPassword")
			
# # # # # # #
			#
			#
			if [[ "$checkCurrentLoginPassword" == *"eDSRecordNotFound"* ]]
				then
					/bin/echo "$consoleUser" "does not exist in the Active Directory Service"
					/usr/bin/logger -s -p6 "FileVault Sync [ERROR]:" "$consoleUser" "does not exist in the Active Directory Service"
					"$cocoaDialogPath" msgbox --title "FileVault Password Sync" \
						--icon gear --no-show --text "Account does not exist." \
						--informative-text "Please contact the Help Desk Immediately." \
						--button1 "OK" --width 430
					exit 1
			elif [[ "$checkCurrentLoginPassword" == *"eDSAuthAccountExpired"* ]]
				then
					/usr/bin/logger -s -p6 "FileVault Sync [ERROR]:" "$consoleUser" "appears to be locked out."
					"$cocoaDialogPath" msgbox --title "FileVault Password Sync" \
						--icon gear --no-show --text "Expired or Locked Out Account" \
						--informative-text "Your account has either expired or is currently locked out. Please contact the Help Desk Immediately." \
						--button1 "OK" --width 430
					exit 1
			elif [[ "$checkCurrentLoginPassword" == *"eDSAuthFailed"* ]]
				then
					/bin/echo "That was not the correct password. Trying again."
			elif [[ ! -z "$checkCurrentLoginPassword" ]] && [[ "$checkCurrentLoginPassword" != *"eDSAuthFailed"* ]] && [[ "$checkCurrentLoginPassword" != *"eDSAuthAccountExpired"* ]] && [[ "$checkCurrentLoginPassword" != *"eDSRecordNotFound"* ]]
				then
					/bin/echo "Unknown error occured. Prompting again."
					loginPasswordError=$(($loginPasswordError + 1))
			elif [[ "${loginPasswordError}" -ge "3" ]] && [[ ! -z "$checkCurrentLoginPassword" ]] && [[ "$checkCurrentLoginPassword" != *"eDSAuthFailed"* ]] && [[ "$checkCurrentLoginPassword" != *"eDSAuthAccountExpired"* ]] && [[ "$checkCurrentLoginPassword" != *"eDSRecordNotFound"* ]]
				then
					/bin/echo "Unknown error occured on third password prompt. Throwing up an error and exiting."
					"$cocoaDialogPath" msgbox --title "FileVault Password Sync" \
						--icon gear --no-show --text "Unknown Error" \
						--informative-text "An unknown error has occurred. Please contact the Help Desk for further assistance." \
						--button1 "OK" --width 430				
			elif [[ -z "$checkCurrentLoginPassword" ]]
				then
					/bin/echo "The user entered the correct network password! If the password matches the local password, we can continue. Checking that now."
					hasClientChangedPasswordandNotRestarted=$(/usr/bin/dscl /Search -authonly "$consoleUser" "$currentLoginPassword")
					if [[ -z "$hasClientChangedPasswordandNotRestarted" ]]
						then
							/bin/echo "The Client entered the correct password and has restarted since changing it!"
							numberTries=3
							loginPasswordCorrect="Yes"
						else
							"$cocoaDialogPath" inputbox --title "FileVault Password Sync" \
								--icon gear --no-show --informative-text "You have not restarted your computer since you changed your password. Your computer will now restart. Please re-run this policy once it's complete." \
								--button1 "OK" --button2 "Cancel" --width 430 --float
							rebootNow
					fi
			fi
		done
}


checkFVstatus ()
{ 
	fvStatus="$(/usr/bin/fdesetup status)"
}


userFVEnabled ()
{
	unset fvUsers
	fvUsers="$(/usr/bin/fdesetup list)"
	if [[ "$fvUsers" != *"${consoleUser}"* ]]
		then
			isFVEnabled="No"
	fi
}

checkFVPassword ()
{
	unset numberTries
	until [[ "$numberTries" == "3" ]]
		do
			numberTries=$(($numberTries + 1))
			if [[ "$numberTries" == "1" ]]
				then
					getFVPassword=($("$cocoaDialogPath" inputbox --title "FileVault Password Sync" \
						--icon gear --no-show --informative-text "Please enter the password you use after you turn on your computer. This is most likely an old password. This is attempt number "$numberTries"." \
						--button1 "OK" --button2 "Cancel" --width 430))
					getFVPasswordButton="${getFVPassword[0]}"
					if [[ "$getFVPasswordButton" == "2" ]]
						then
							/bin/echo "The User clicked Cancel at the password dialog. Failing because this MUST be fixed."
							"$cocoaDialogPath" msgbox --title "FileVault Password Sync" \
								--icon gear --no-show --text "Confused?" \
								--informative-text "We're looking for the password you use after you turn on your computer." \
								--button1 "OK" --width 430
							deleteFVUnlockUser
							exit 1
					fi
				else
					getFVPassword=($("$cocoaDialogPath" inputbox --title "FileVault Password Sync" \
						--icon gear --no-show --informative-text "That Password was incorrect. Please enter the password you use to unlock your computer at startup. This is attempt number "$numberTries"." \
						--button1 "OK" --button2 "Cancel" --width 430))
					getFVPasswordButton="${getFVPassword[0]}"
					if [[ "$getFVPasswordButton" == "2" ]]
						then
							/bin/echo "The User clicked Cancel at the password dialog. Failing because this MUST be fixed."
							"$cocoaDialogPath" msgbox --title "FileVault Password Sync" \
								--icon gear --no-show --text "Confused?" \
								--informative-text "We're looking for the password you use to log in." \
								--button1 "OK" --width 430
							exit 1
					fi
			fi
			/bin/echo "The User has attempted their password sync" "$numberTries" "times."
			fvPassword="${getFVPassword[1]}"
			# Scrubbing passwords for characters that don't play with with XML.
			fvPassXML=$(echo "$fvPassword" | sed -e 's~&~\&amp;~g' -e 's~<~\&lt;~g' -e 's~>~\&gt;~g' -e 's~\"~\&quot;~g' -e "s~\'~\&apos;~g" )
			random_PassXML=$(echo "$random_Pass" | sed -e 's~&~\&amp;~g' -e 's~<~\&lt;~g' -e 's~>~\&gt;~g' -e 's~\"~\&quot;~g' -e "s~\'~\&apos;~g" )
			
			#
			# This is the meat of this function. It's important to know that bash reads the script out-of-order--looking for redirects before binaries and syntax.
			# Therefore we can put the redirect first so that we redirect stderr to stdout so we can read the output of the binary, which likes to use stderr for errors.
# # # # # # #
			
			checkFVPassword="$(2>&1 fdesetup add -inputplist <<-CHECKFVPASSWORD_HERE_DOC
				<?xml version="1.0" encoding="UTF-8"?>
				<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
				<plist version="1.0">
				<dict>
				<key>Username</key>
				<string>$consoleUser</string>
				<key>Password</key>
				<string>$fvPassXML</string>
				<key>AdditionalUsers</key>
				<array>
					<dict>
						<key>Username</key>
						<string>fvunlock</string>
						<key>Password</key>
						<string>$random_PassXML</string>
					</dict>
					</array>
				</dict>
				</plist>
				CHECKFVPASSWORD_HERE_DOC
				)"
				
# # # # # # #
			#
			#
			
			if [[ "$checkFVPassword" == "Error: Authentication of FileVault failed." ]]
				then
					/bin/echo "fdesetup command output: " "$checkFVPassword"
					/bin/echo "The User entered the incorrect FileVault Password. Trying again."
			fi
			if [[ -z "$checkFVPassword" ]]
				then
					/bin/echo "The User entered the correct password! Let's get out of these nested loops."
					fvPasswordCorrect="Yes"
					numberTries=3
			fi
		done
}

unlockAccountFVEnabled ()
{
	unset fvUsers
	fvUsers="$(/usr/bin/fdesetup list)"
	if [[ "$fvUsers" != *'fvunlock'* ]]
		then
			isUnlockAccountFVEnabled="No"
	fi
}

removeConsoleUserFromFV ()
{
	fdesetup remove -user "$consoleUser"
}

removeUnlockUserFromFV ()
{
	fdesetup remove -user fvunlock
}

readdConsoleUsertoFV ()
{
	currentLoginPasswordXML=$(echo "$currentLoginPassword" | sed -e 's~&~\&amp;~g' -e 's~<~\&lt;~g' -e 's~>~\&gt;~g' -e 's~\"~\&quot;~g' -e "s~\'~\&apos;~g" )
	random_PassXML=$(echo "$random_Pass" | sed -e 's~&~\&amp;~g' -e 's~<~\&lt;~g' -e 's~>~\&gt;~g' -e 's~\"~\&quot;~g' -e "s~\'~\&apos;~g" )
	readdConsoleUserCheck="$(2>&1 fdesetup add -inputplist <<-READDCONSOLEUSER_HERE_DOC
		<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">
		<dict>
		<key>Username</key>
		<string>fvunlock</string>
		<key>Password</key>
		<string>$random_PassXML</string>
		<key>AdditionalUsers</key>
		<array>
			<dict>
				<key>Username</key>
				<string>$consoleUser</string>
				<key>Password</key>
				<string>$currentLoginPasswordXML</string>
			</dict>
			</array>
		</dict>
		</plist>
		READDCONSOLEUSER_HERE_DOC
		)"
}



rebootNow ()
{
	#------------------
	# Reboot
	#------------------
	# Let the user know we are about to restart, then restart.

	/usr/local/bin/jamf reboot -minutes 0 -message "Rebooting now. Please save your work. You should only have to enter your password one time now." -background
	exit 0
}


####################################################
#--------------------------------------------------#
# Script Logic
#--------------------------------------------------#
####################################################

if [[ "$cocoaDialogInstalledByThisPolicy" == "No" ]]
	then
		installCocoaDialog
fi

deleteFVUnlockUser

# Get whoever is logged into the Window session on the machine. If it is the login Window or any of the system accounts for any reason, exit with an error.
getConsoleUser

if [[ "$consoleUser" == "admin" ]] || [[ "$consoleUser" == "root" ]] || [[ "$consoleUser" == "daemon" ]] || [[ "$consoleUser" == "guest" ]] || [[ "$consoleUser" == "nobody" ]]
	then
		/usr/bin/logger -s -p6 "FileVault Sync Error: System user found"
		"$cocoaDialogPath" msgbox --title "FileVault Password Sync" \
			--icon gear --no-show --text "System Login Detected" \
			--informative-text "Please logout and login under the User's account." \
			--button1 "OK" --width 430
		exit 1
fi


# 1. Verify AD connection
isComputerBound

if [[ "$computerBound" == "No" ]]
	then
		/usr/bin/logger -s -p6 "FileVault Sync Error: Computer not Bound to Active Directory"
		"$cocoaDialogPath" msgbox --title "FileVault Password Sync" \
			--icon gear --no-show --text "Computer is not Bound." \
			--informative-text "This computer is not bound to the Active Directory. Please unbind and rebind." \
			--button1 "OK" --width 430
		exit 1
fi


# 2. Verify FileVault is on and account is FV2 enabled
checkFVstatus

if [[ "$fvStatus" == *'Encryption in progress'* ]]
	then
		/usr/bin/logger -s -p6 "FileVault Sync [ERROR]: The encryption process is still in progress."
		/usr/bin/logger -s -p6 "$fvStatus"
		"$cocoaDialogPath" msgbox --title "FileVault Password Sync" \
			--icon gear --no-show --text "Encryption is incomplete." \
			--informative-text "This computer is still in the process of encrypting. Please wait until encryption is complete to add a new FileVault user." \
			--button1 "OK" --width 430
		exit 1
elif [[ "$fvStatus" == *'FileVault is Off'* ]]
	then
		/usr/bin/logger -s -p6 "FileVault Sync [ERROR]: Encryption is not active."
		/usr/bin/logger -s -p6 "$fvStatus"
		"$cocoaDialogPath" msgbox --title "FileVault Password Sync" \
			--icon gear --no-show --text "FileVault is Off" \
			--informative-text "FileVault is not on. There is no need to sync the password." \
			--button1 "OK" --width 430
		exit 1
elif [[ "$fvStatus" != *'FileVault is On'* ]]
	then
		/usr/bin/logger -s -p6 "FileVault Sync [ERROR]: Unable to determine encryption status."
		/usr/bin/logger -s -p6 "$fvStatus"
		"$cocoaDialogPath" msgbox --title "FileVault Password Sync" \
			--icon gear --no-show --text "Unable to determine FileVault Status" \
			--informative-text "This automated process cannot determine the status of encryption on this computer. Please use other tools to determine what is happening and to complete this process." \
			--button1 "OK" --width 430
		exit 1
fi

userFVEnabled
if [[ "$isFVEnabled" == "No" ]]
	then
		/usr/bin/logger -s -p6 "FileVault Sync [ERROR]:" "$consoleUser" "is not on the list of FileVault enabled users:"
		/usr/bin/logger -s -p6 "FileVault Sync [ERROR]:" "$fvUsers"
		"$cocoaDialogPath" msgbox --title "FileVault Password Sync" \
			--icon gear --no-show --text "User is not in FileVault" \
			--informative-text "The currently logged-in user is not on the list for FileVault users. Please log in with an account that can unlock this computer." \
			--button1 "OK" --width 430
		exit 1
fi


# 3. Prompt user for newest password & validate it
checkLoginPassword

if [[ "$loginPasswordCorrect" != "Yes" ]]
	then
		"$cocoaDialogPath" msgbox --title "FileVault Password Sync" \
			--icon gear --text "Incorrect Password" --informative-text "This password should be the newest one you have. Please double-check and re-run this policy from Self Service." \
			--button1 "OK" --button2 "Cancel" --width 430 --float
		exit 1
fi

# 4. Create a temporary FileVault user and authorize for FileVault
# 5. Prompt user for FV2 password
#
#    These are intertwined. The only way to check if the FileVault password is 
#    correct is to try to use it to add a new FileVault user. So these steps combine.
createFileVaultUser
checkFVPassword

if [[ "$fvPasswordCorrect" != "Yes" ]]
	then
		"$cocoaDialogPath" msgbox --title "FileVault Password Sync" \
			--icon gear --text "Incorrect Password" --informative-text "This should be the same password you use when you start up your computer. It is most likely an old password. Please double-check and re-run this policy from Self Service." \
			--button1 "OK" --button2 "Cancel" --width 430 --float
		exit 1
fi

# 6. Verify service unlock account is enabled
unlockAccountFVEnabled
if [[ "$isUnlockAccountFVEnabled" == "No" ]]
	then
		/usr/bin/logger -s -p6 "FileVault Sync [ERROR]: fvunlock is not on the list of FileVault enabled users:"
		/usr/bin/logger -s -p6 "FileVault Sync [ERROR]:" "$fvUsers"
		"$cocoaDialogPath" msgbox --title "FileVault Password Sync" \
			--icon gear --no-show --text "Unlock account is not in FileVault" \
			--informative-text "The temporary unlock account is not on the list for FileVault users. Please restart this process as that account is necessary." \
			--button1 "OK" --width 430
		exit 1
fi


# 7. Use temp user to remove/re-add user with 
#    the newest password
removeConsoleUserFromFV
readdConsoleUsertoFV
userFVEnabled
if [[ "$isFVEnabled" == "No" ]]
	then
		/usr/bin/logger -s -p6 "FileVault Sync [ERROR]:" "$consoleUser" "is not on the list of FileVault enabled users after attempting to readd:"
		/usr/bin/logger -s -p6 "FileVault Sync [ERROR]:" "$fvUsers"
		"$cocoaDialogPath" msgbox --title "FileVault Password Sync" \
			--icon gear --no-show --text "User is not in FileVault" \
			--informative-text "The currently logged-in user is not on the list for FileVault users after. If this has occurred, please contact the Help Desk immediately and do not shut down your computer." \
			--button1 "OK" --width 430
		exit 1
fi

deleteFVUnlockUser
rebootNow


# This script should never reach this point. Exiting with an error.
exit 64

