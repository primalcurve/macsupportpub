#!/bin/bash
# Created by primalcurve 04/26/2016
# Scrubbed for public distribution 08/08/2017

proxy=""
activeDirectory="/Active\ Directory/AD/All\ Domains"
knownADAccount="macUser"

# Is this machine on the network? If so, then continue. If not, exit immediately.
if [[ -n "${proxy}" ]]
	then
		pingProxy=$(/sbin/ping -o "${proxy}")
		if [[ "${pingProxy}" != *'1 packets transmitted, 1 packets received, 0.0% packet loss'* ]]
			then
				#Client is most likely not on the network. Exiting immediately.
				/bin/echo "<result>Not on Network at Recon</result>"
				exit 0
		fi
fi


lsDevConsole=($(ls -l /dev/console)) 
consoleUser=${lsDevConsole[2]}

if [[ "${consoleUser}" == "admin" ]] || [[ "${consoleUser}" == "root" ]] || [[ "${consoleUser}" == "daemon" ]] || [[ "${consoleUser}" == "guest" ]] || [[ "${consoleUser}" == "nobody" ]]
	then
		/bin/echo "<result>No console user at Recon</result>"
		exit 1
fi

# Try to query the AD. If successful, then the machine is properly bound. If not, then it has become unbound
queryADResults=($(/usr/bin/dscl "${activeDirectory}" -read /Users/"${consoleUser}" RecordName))
queryADResultsRecordName="${queryADResults[1]}"
	
if [[ "${queryADResultsRecordName}" == "${consoleUser}" ]]
	then
        /bin/echo "<result>YES</result>"
    else
		queryADResultsKnown=($(/usr/bin/dscl "activeDirectory" -read /Users/"${knownADAccount}" RecordName))
		queryADResultsRecordNameKnown="${queryADResultsKnown[1]}"
		if [[ "${queryADResultsRecordNameKnown}" == "${knownADAccount}" ]]
			then
				/bin/echo "<result>YES</result>"
			else
				/bin/echo "<result>NO</result>"
		fi
fi

exit 0