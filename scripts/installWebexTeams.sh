#!/bin/bash
#
#  installWebexTeams.sh
#
#  Created 05/18/2018   primalcurve
#               
###############################################################################
#-----------------------------------------------------------------------------#
#   Table of Contents
#-----------------------------------------------------------------------------#
#
#   The purpose of this script is to install Webex Teams in the user's 
#   Applications folder. This should allow them to auto-update the Application
#   as they will own the installation folder.
#
#-----------------------------------------------------------------------------#
###############################################################################


###############################################################################
#-----------------------------------------------------------------------------#
#   Arrays and Lists
#-----------------------------------------------------------------------------#
###############################################################################

#--------------------------------------------------#
#       Constants
#--------------------------------------------------#

# Setting global settings for bash.
# No match if it doesn't glob.
shopt -s nullglob

# Explicitly declare the PATH environment variable so that absolute paths are not required in scripts. This improves syntactical highlighting in bash IDEs.
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

downloadWebexTeamsURL=''
unset userInitiatedUpdate revertWebexTeams upgradeWebexTeams expectedWebexTeamsVersion

JAMF_HELPER_PATH='/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper'
ICON_PATH='/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertCautionIcon.icns'
TEAM_IDENTIFIER='DE8Y96K9QP'

# CHANGE THESE
LOG_LABEL='com.github.primalcurve'
CORPORATE_PROXY='yourproxy.proxy.com'
CORPORATE_PROXY_PORT='1234'
CURL_USER_AGENT='Macintosh'
DOMAIN_CONTROLLER='ad.yourdomain.com'
DOCKUTIL_PATH='/usr/local/bin/dockutil'
YO_PATH='/usr/local/bin/yo.app/Contents/MacOS/yo'

#--------------------------------------------------#
#       Variables
#--------------------------------------------------#

if [[ -n "${4}" ]] && [[ -z "${downloadWebexTeamsURL}" ]]
    then
        downloadWebexTeamsURL="${4}"
    else
        parameterError+=('Please pass a URL to the downloadWebexTeamsURL Parameter.')
fi

if [[ -n "${5}" ]] && [[ -z "${userInitiatedUpdate}" ]]
    then
        userInitiatedUpdate="${5}"
        regexYes='^[y Y][e E][s S]$'
        regexNo='^[n N][o O]$'
        if [[ "${userInitiatedUpdate}" =~ ${regexNo} ]]
            then
                userInitiatedUpdate='No'
        elif [[ "${userInitiatedUpdate}" =~ ${regexYes} ]]
            then
                userInitiatedUpdate='Yes'
            else
                parameterError+=('Please pass a yes or a no to the User Initiated Update Parameter.')
        fi
    else
        parameterError+=('The User Initiated Update Parameter is not optional.')
fi

if [[ -n "${6}" ]] && [[ -z "${revertWebexTeams}" ]]
    then
        revertWebexTeams="${6}"
        regexSpark='^[c C][i I][s S][c C][o O] [s S][p P][a A][r R][k K]$'
        regexWebex='^[w W][e E][b B][e E][x X] [t T][e E][a A][m M][s S]$'
        regexNo='^[n N][o O]$'
        if [[ "${revertWebexTeams}" =~ ${regexNo} ]]
            then
                revertWebexTeams='No'
        elif [[ "${revertWebexTeams}" =~ ${regexSpark} ]]
            then
                revertWebexTeams='Cisco Spark'
        elif [[ "${revertWebexTeams}" =~ ${regexWebex} ]]
            then
                revertWebexTeams='Webex Teams'
            else
                parameterError+=('Please pass an app name to the Revert Parameter.')
        fi
    else
        parameterError+=('The Revert Parameter is not Optional.')
fi

if [[ -n "${7}" ]] && [[ -z "${upgradeWebexTeams}" ]]
    then
        upgradeWebexTeams="${7}"
        regexYes='^[y Y][e E][s S]$'
        regexNo='^[n N][o O]$'
        if [[ "${upgradeWebexTeams}" =~ ${regexNo} ]]
            then
                upgradeWebexTeams='No'
        elif [[ "${upgradeWebexTeams}" =~ ${regexYes} ]]
            then
                upgradeWebexTeams='Yes'
            else
                parameterError+=('Please pass a yes or a no to the upgradeWebexTeams Parameter.')
        fi
    else
        parameterError+=('The upgradeWebexTeams Parameter is not optional.')
fi

if [[ -n "${8}" ]] && [[ -z "${expectedWebexTeamsVersion}" ]]
    then
        expectedWebexTeamsVersion="${8}"
fi

# Get the name of the script for logging purposes.
thisScriptName="$(basename "${0}")"

###############################################################################
#-----------------------------------------------------------------------------#
#   Bash Functions
#-----------------------------------------------------------------------------#
###############################################################################

function getConsoleUser
{
    #Get Console User and Console User's UUID
    read CONSOLE_USER CONSOLE_USER_UID CONSOLE_USER_GID < <(python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username, uid, gid = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None]); username = [username,""][username in ["loginwindow", None, u""]]; sys.stdout.write(username + " " + str(uid) + " " + str(gid));')
    logItNow loud "Function getConsoleUser: ${CONSOLE_USER} with UUID ${CONSOLE_USER_UID} is logged in."
}

function logItNow
{
    # Usage: logItNow <quiet-or-loud> Sentences, arrays, etc. Pretty much anything now.
    # Concatenates log messages for the logWriter.
    # Quiet or loud determines if the output will be piped to stdout or to just the
    # logfile/Unified Logging.
    if [[ "$#" == "0" ]]
        then
            printf '%s\n' "${FUNCNAME[0]}"': Please indicate what you would like to Log.'
            return 1
    fi
    if [[ "${1}" == 'quiet' ]] || [[ "${1}" == 'loud' ]]
        then
            quietOrLoud="${1}"
            shift # Move past the "quiet or loud" part and start reading parameters.
        else
            quietOrLoud='loud'
    fi
    while (( "$#" ))
        do
            concatenatedMessage+=("${1}")
            # Move positional parameters to the left, making 1 into 0
            # and 2 into 1, etc.
            shift
        done
    if [[ "${0}" == '-bash' ]]
        then
            # Function is being called from tty. Renaming.
            scriptSource='Testing Environment'
        else
            scriptSource="$(basename "${0}")"
    fi
    logWriter "${quietOrLoud}" "${scriptSource}" "${concatenatedMessage[*]}"
    unset quietOrLoud concatenatedMessage scriptSource
}

function logWriter
{
    # Usage: logWriter <quiet-or-loud> <tag> <log-message>
    # Gets a log message a tag and passes writes to the syslog, logFiles,
    # and a simplified form to stdout for the jamf log.
    if [[ "$#" == "0" ]]
        then
            printf '%s\n' "${FUNCNAME[0]}"': No parameters passed to this function.'
            return 1
    fi
    printOut="${1}"
    logTag="${2}"
    logMessage="${3}"
    # Write to Apple Unified Logs. Not great but it gets it stored on the system.
    # Do not write out to stdout as we do not want to see the messy output.
    logger -s -t "${logTag} " "${logMessage}" > /dev/null 2>&1
    # Write to logFiles. This will be handled by the logFileHandler
    logFileHandler "${logTag}" "${logMessage}"
    # Write to stdout for testing purposes and to make the output in the
    # Jamf Pro Server logs more readable, but only if we want it.
    if [[ "${printOut}" == "loud" ]]
        then
            printf '%s\n' "${logMessage}"
    fi
    unset printOut logTag logMessage
}

function logItNowHeader
{
    # Usage: logItNowHeader <script-name>
    # Write to logfile header that separates this script from others.
    if [[ "$#" == "0" ]]
        then
            printf '%s\n' "${FUNCNAME[0]}"': No parameters passed to this function.'
            return 1
    fi
    scriptName="${1}"
    scriptNameLength="${#scriptName}"; padding="$(printf '%0.1s' " "{1..43})"
    logItNow quiet ' '
    logItNow quiet '┌──────────────────────────────────────────────────────────────────────┐'
    logItNow quiet '│  This begins the '"$(printf '%s script %s │' "${scriptName}" "${padding:$scriptNameLength}")"
    unset scriptName scriptNameLength padding
}

function logItNowFooter
{
    # Usage: logItNowFooter <script-name>
    # Write to logfile footer that separates this script from others. Use before
    # every exit-state.
    if [[ "$#" == "0" ]]
        then
            printf '%s\n' "${FUNCNAME[0]}"': No parameters passed to this function.'
            return 1
    fi
    scriptName="${1}"
    scriptNameLength="${#scriptName}"; padding="$(printf '%0.1s' " "{1..45})"
    logItNow quiet '│  This ends the '"$(printf '%s script %s │' "${scriptName}" "${padding:$scriptNameLength}")"
    logItNow quiet '└──────────────────────────────────────────────────────────────────────┘'
    unset scriptName scriptNameLength padding
}

function logFileHandler
{
    # Usage: logFileHandler <log-tag> <log-message>
    if [[ "$#" == "0" ]]
        then
            printf '%s\n' "${FUNCNAME[0]}"': No parameters passed to this function.'
            return 1
    fi
    logFileFolder='/usr/local/var/log/'
    logFileTag="${1}"
    logFileMessage="${2}"
    read yearNow monthNow dayNow < <(date '+%Y %m %d')
    dateNow="${yearNow}-${monthNow}-${dayNow}"
    timeNow="$(date '+%H:%M:%S')"
    if [[ -f "${logFileFolder}/${LOG_LABEL}.scriptlog${dateNow}.log" ]]
        then
            # Append to today's logfile if it already exists and return.
            printf '%s %s - %s:\t%s\n' "${dateNow}" "${timeNow}" "${logFileTag}" "${logFileMessage}" >> "${logFileFolder}/${LOG_LABEL}.scriptlog${dateNow}.log"
            unset logFileFolder logFileTag logFileMessage yearNow monthNow dayNow dateNow timeNow
            return
        else
            # Create the log archive if it does not exist.
            if [[ ! -d "${logFileFolder}"'archive/' ]]
                then
                    mkdir -p "${logFileFolder}"'/archive/' > /dev/null 2>&1
            # Create the log archive for this year if it does not exist.
            elif [[ ! -f "${logFileFolder}archive/${LOG_LABEL}.logarchive.${yearNow}.zip" ]]
                then
                    touch "${logFileFolder}archive/${LOG_LABEL}.logarchive.${yearNow}.zip"
            fi
            # Check for old logfiles. If they exist, then compress them into 
            # logarchive folder and create today's logfile.
            while IFS= read -r -d $'\0' nullByte
                do
                    fileName="$(basename "${nullByte}")"
                    # Get the year and month the file was created in from the
                    # fileName.
                    fileYear="${fileName#*scriptlog}"; fileYear="${fileYear%%-*}"
                    fileMonth="${fileName#*-}"; fileMonth="${fileMonth%%-*}"
                    # If the archive for the year in which the file was create
                    # does not exist, then we create the archive.
                    if [[ ! -f "${logFileFolder}archive/${LOG_LABEL}.logarchive.${fileYear}.zip" ]]
                        then
                            touch "${logFileFolder}archive/${LOG_LABEL}.logarchive.${fileYear}.zip"
                    fi
                    # Zip file into /month/filename but into the correct year's
                    # filename. So files created in 2313 are filed into 2313 
                    # even if the current year is 2314.
                    /System/Library/Frameworks/Python.framework/Versions/Current/bin/python -c 'import zipfile as zf, sys; z=zf.ZipFile(sys.argv[1], "a"); z.write(sys.argv[2], sys.argv[3]); z.close()' "${logFileFolder}archive/${LOG_LABEL}.logarchive.${fileYear}.zip" "${nullByte}" "${fileMonth}/${fileName}"
                    # Remove the file now that we've backed it up into a
                    # compressed folder.
                    rm "${nullByte}" > /dev/null 2>&1
                    unset fileName fileMonth fileYear
                done < <(find -E "${logFileFolder}" -regex '.*\.scriptlog[0-9]+-[0-9]+-[0-9]+\.log' -print0 -depth 0)
            # Create or append to today's logfile.
            printf '%s %s - %s:\t\t%s\n' "${dateNow}" "${timeNow}" "${logGileTag}" "${logFileMessage}" >> "${logFileFolder}/${LOG_LABEL}.scriptlog${dateNow}.log"
            unset logFileFolder logFileTag logFileMessage yearNow monthNow dayNow dateNow timeNow
            return
    fi
    unset logFileFolder logFileTag logMessage yearNow monthNow dayNow dateNow timeNow
}

function installDependency
{
    # Usage: installDependency "<jamf-trigger>" "<expected-path>"
    if [[ "$#" == "0" ]]
        then
            logItNow loud "${FUNCNAME[0]}: No parameters passed to this function."
            return 1
    fi
    jamfTrigger="${1}"
    expectedPath="${2}"
    if [[ ! -e "${expectedPath}" ]]
        then
            logItNow loud "${FUNCNAME[0]}: Dependency is missing from this computer. Invoking the ${jamfTrigger} trigger."
            jamf policy -trigger "${jamfTrigger}" > /dev/null 2>&1
            if [[ -e "${expectedPath}" ]]
                then
                    logItNow quiet "${FUNCNAME[0]}"': Sucessfull installation of '"${jamfTrigger}"' See that log for further details.'
                    printf '%s\n' "${expectedPath}"
                else
                    logItNow loud "${FUNCNAME[0]}: Dependency is still missing even after trigger was invoked. Since this is a dependency, we will quit now."
                    logItNowFooter "${thisScriptName}"
                    exit 1
            fi
        else
            # Dockutil is already installed on this computer. Return the Path.
            printf '%s\n' "${expectedPath}"
    fi
    unset jamfTrigger expectedPath
}

function onNetwork
{
    # Check to see if the proxy or the domain controller are reachable. 
    # If so, adding the proxy info.
    pingResults=("$(ping -o "${CORPORATE_PROXY}")"); pingResults+=("$(ping -o "${DOMAIN_CONTROLLER}")")
    if [[ "${pingResults[*]}" == *'1 packets transmitted, 1 packets received'* ]]
        then
            logItNow quiet "${FUNCNAME[0]}: Client is on the network. Adding proxy info."
            proxyOn
        else
            # Client is most likely not on the network. No proxy info will be provided.
            proxyOff
    fi
}

function proxyOn
{
    export HTTP_PROXY="${CORPORATE_PROXY}":"${CORPORATE_PROXY_PORT}"
    export HTTPS_PROXY="${HTTP_PROXY}"
    #export FTP_PROXY="${HTTP_PROXY}"
    #export SOCKS_PROXY="${HTTP_PROXY}"

    # Get the search domains of all the network devices. Add them to NO_PROXY 
    # so that the proxy is bypassed when interacting with things on the
    # network.
    while IFS=$'\n' read -r networkService
        do
            case "${networkService}" in
                'An asterisk (*) denotes that a network service is disabled.' )
                    continue
                    ;;
                *'FireWire'* )
                    continue
                    ;;
            esac
            while IFS=$'\n' read -r searchDomain
                do
                    if [[ "${uniqueDomains[*]}" != *"${searchDomain}"* ]] && [[ "${searchDomain}" != *"There aren't any Search Domains set on"* ]]
                        then
                            uniqueDomains+=("${searchDomain}")
                    fi
                done < <(networksetup -getsearchdomains "${networkService}")
        done < <(networksetup -listallnetworkservices)
    # Now we add the exclusions.
    if [[ -z "${uniqueDomains[@]}" ]]
        then
            export NO_PROXY="localhost,127.0.0.1"
        else
            export NO_PROXY="localhost,127.0.0.1$(printf ',%s' "${uniqueDomains[@]}")"
    fi

    # Used when other functions need proxy info.
    curlUserAgent=(-H "user-agent: ${CURL_USER_AGENT}")
    curlProxy=(--proxy "${CORPORATE_PROXY}:${CORPORATE_PROXY_PORT}")

    unset uniqueDomains
}

function proxyOff
{
    unset HTTP_PROXY HTTPS_PROXY FTP_PROXY SOCKS_PROXY NO_PROXY curlUserAgent curlProxy
}

function removeItems
{
    # Usage: removeItems "<loud-or-quiet>" "quotedFolderPath1" "quotedFolderPath2" ... etc
    protectedFolderRegex='(^\/$|^\/Users\/?$|^\/Users\/\w+\/?|^\/Users\/.+\/(Applications|Desktop|Documents|Downloads|Library|Movies|Music|Pictures|Public)\/?$|^\/Library\/?$|^\/Applications\/?$|^\/Network\/?$|^\/System.*|^\/Volumes\/?$|^\/bin.*|^\/cores.*|^\/dev.*|^\/etc\/?$|^\/private\/etc\/?$|^\/home\/?$|^\/net\/?$|^\/opt\/?$|^\/private\/?$|^\/sbin.*|^\/tmp\/?$|^\/private\/tmp\/?$|^\/usr\/?$|^\/var\/?$|^\/private\/var\/?$)'
    if [[ "$#" == "0" ]]
        then
            logItNow loud "${FUNCNAME[0]}"': Please pass a filepath to this function.'
            return 1
    fi
    if [[ "${1}" == "quiet" ]]
        then
            removeLoud='No' # Keeping things quiet.
    elif [[ "${1}" == "loud" ]]
        then
            removeLoud='Yes' # Not being quiet about it.
    fi
    shift # Move up one positional parameter so that the next loop works.
    while (( "$#" ))
        do
            if [[ "${1}" =~ ${protectedFolderRegex} ]]
                then
                    # We will not be quiet about this error.
                    logItNow loud "${FUNCNAME[0]}"': Fatal Error: Function was passed a protected folder.'
                    break
            fi
            if [[ -d "${1}" ]] || [[ -f "${1}" ]] || [[ -L "${1}" ]]
                then
                    if [[ "${removeLoud}" == 'Yes' ]]
                        then
                            logItNow loud "${FUNCNAME[0]}: Removing file or folder located at path ${1}"
                    fi
                    rm -rf "${1}" > /dev/null
                else
                    # Here is where we want to be quiet.
                    if [[ "${removeLoud}" == 'Yes' ]]
                        then
                            logItNow loud "${FUNCNAME[0]}: Warning: No file or folder located at ${1}"
                        else
                            logItNow quiet "${FUNCNAME[0]}: Warning: No file or folder located at ${1}"
                    fi
            fi
            shift # Move positional parameters to the left, making 1 into 0
                  # and 2 into 1, etc.
        done
    unset removeLoud
}

function appInstalledVersion
{
    # Usage: appInstalledVersion "<path-to-app>"
    appPath="${1}"
    if [[ -d "${appPath}" ]]
        then
            appVersion=$(defaults read "${appPath}"'/Contents/Info.plist' CFBundleShortVersionString)
            printf '%s\n' "${appVersion}"
        else
            printf '%s\n' 'NotInstalled'
    fi
    unset appPath appVersion
}

function getRunningApps
{
    # Usage: getRunningApps <user>
    getAppsUser="${1}"
    sudo -u "${getAppsUser}" python -c 'import sys; from AppKit import NSWorkspace; apps = [str(app.localizedName()) for app in NSWorkspace.sharedWorkspace().runningApplications()]; sys.stdout.write("\n".join(apps));'
}

function killSignedProcess
{
    # Usage: killSignedProcess <process-name> <team-identifier>
    if [[ -z "${1}" ]] || [[ -z "${2}" ]]
        then
            logItNow loud "${FUNCNAME[0]}"': Please pass a process name and a Team Identifier'
            return 1
    fi
    processName="${1}"
    teamIdentifier="${2}"
    if [[ "${processName}" == 'None' ]]
        then
            return 0
    fi
    logItNow loud "${FUNCNAME[0]}: Attempting to quit any Application with name containing ${processName} with a Team Identifier of ${teamIdentifier}"
    while IFS=$'\n' read -r processID
        do
            while IFS=$'\n' read -r codesignLine
                do
                    if [[ "${codesignLine}" == *"TeamIdentifier=${teamIdentifier}"* ]]
                        then
                            fullProcessPath="$(ps "${processID}" -o comm)"
                            fullProcessPath="${fullProcessPath#COMM$'\n'}"
                            logItNow quiet "${FUNCNAME[0]}: $(basename "${fullProcessPath}") running. Passing process to gentlyKill function."
                            gentlyKill "$(basename "${fullProcessPath}")"
                    fi
                done < <(codesign --display --verbose=4 "${processID}" 2>&1)
        done < <(pgrep -f "${processName}")
    unset processName teamIdentifier fullProcessPath
}

function gentlyKill
{
    # Usage: gentlyKill "<process-name>"
    if [[ -z "${1}" ]]
        then
            logItNow loud "${FUNCNAME[0]}"': Please pass a process name.'
            return 1
    fi
    appToKill="${1}"
    ascendingSeverity=(\
        'osascript -e "tell application \"${appToKill}\" to quit"' \
        'pkill 2 "${1}"' \
        'pkill 15 "${1}"' \
        'pkill 9 "${1}"' \
        )
    for severity in "${!ascendingSeverity[@]}"
        do
            if [[ -n "$(pgrep -f "${appToKill}")" ]]
                then
                    logItNow quiet "Attempting to quit ${appToKill} with command: ${ascendingSeverity[${severity}]}."
                    eval ${ascendingSeverity[${severity}]} \> /dev/null 2\>\&1
                    sleep 10
                else
                    logItNow quiet "${appToKill} is no longer running."
                    return 1
            fi
        done
    unset ascendingSeverity appToKill
}

function addAppToDock
{
    # Usage: addAppToDock <user> "<app-name>" "<app-path>" <refresh>
    if [[ "$#" == "0" ]]
        then
            logItNow loud "${FUNCNAME[0]}"': Please pass a user and app name to this function.'
            return 1
    fi
    userName="${1}"
    appName="${2}"
    appPath="${3}"
    reFresh="${4}"
    isAppInDock=$("${dockutilPath}" --find "${appName}" /Users/"${userName}")
    if [[ "${isAppInDock}" == *"${appName} was found"* ]]
        then
            logItNow quiet "${appName} is already in the dock."
            if [[ "${reFresh}" == 'refresh' ]]
                then
                    logItNow quiet "Refreshing dock icon." 
                    sudo -u "${userName}" "${dockutilPath}" --add "${appPath}" --replacing "${appName}" '/Users/'"${userName}" 
            fi
        else
            logItNow loud "${appName} is not in the dock. Adding to the end of the dock."
            sudo -u "${userName}" "${dockutilPath}" --add "${appPath}" '/Users/'"${userName}" 
    fi
    unset userName appName appPath reFresh isAppInDock
}

function fileCopy
{
    # Usage: fileCopy <source> <destination> <update-or-overwrite>
    fileSource="${1}"
    fileDestination="${2}"
    updateOrOverwrite="${3}"
    # Check input to make sure it makes sense.
    regexUpdate='^[u U][p P][d D][a A][t T][e E]$'
    regexOverwrite='^[o O][v V][e E][r R][w W][r R][i I][t T][e E]$'
    if [[ ! -d "${fileSource}" ]]
        then
            logItNow loud "${FUNCNAME[0]}"': Error, source directory does not exist.'
            return 1
    elif [[ "${fileDestination}" != *'/'* ]]
        then
            logItNow loud "${FUNCNAME[0]}"': Error, destination directory does not appear to be a filepath.'
    elif [[ "${updateOrOverwrite}" =~ ${regexUpdate} ]]
        then
            rsycCommand=(rsync -avzhi --update)
    elif [[ "${updateOrOverwrite}" =~ ${regexOverwrite} ]]
        then
            rsycCommand=(rsync -rlvzhi --checksum)
        else
            logItNow loud "${FUNCNAME[0]}"': Error, please pass update or overwrite to this function.'
            return 1
    fi
    newlineSummaryRegex='sent .* bytes  received .* bytes  .* bytes\/sec'
    newlineTotalRegex='total size is .*  speedup is .*'
    # Copy files and read the output of rsync. Use this to create a summary.
    # rsync switches are based on above input. Overwrite means that the files
    # are checksummed and any file that deviates from the source is overwritten.
    # Update means that only files that are newer at the source get overwritten.s
    while IFS=$'\n' read -r newLine
        do
            if [[ "${newLine}" =~ ${newlineSummaryRegex} ]]
                then
                    summaryLine="${newLine}"
                    continue
            elif [[ "${newLine}" =~ ${newlineTotalRegex} ]]
                then
                    totalLine="${newLine}"
                    continue
            elif [[ "${newLine}" != *'building file list ... done'* ]] && [[ -n "${newLine}" ]] && [[ "${newLine}" != *'skipping'* ]]
                then
                    newfileCount+=("${newLine}")
            fi
        done < <("${rsycCommand[@]}" "${fileSource}" "${fileDestination}")
    summaryLine="${summaryLine##*sent }" && summaryLine="${summaryLine%%  received *}"
    totalLine="${totalLine##total size is }" && totalLine="${totalLine%%  speedup is *}"
    if [[ ${#newfileCount[@]} != 0 ]]
        then
            logItNow loud "Transfer from $(basename "${fileSource}") to $(basename "${fileDestination}"): ${#newfileCount[@]} files updated. Copied ${totalLine} total."
    fi
    unset fileSource fileDestination summaryLine totalLine newfileCount
}

function addLoginItem
{
    # Usage: addLoginItem <user> "<app-name>" "<app-path>" <refresh>
    if [[ "$#" == "0" ]]
        then
            logItNow loud "${FUNCNAME[0]}"': Please pass a user and app name to this function.'
            return 1
    fi
    userID="${1}"
    appName="${2}"
    appPath="${3}"
    reFresh="${4}"
    loginItems=$(launchctl asuser "${userID}" osascript -e 'tell application "System Events" to get the name of every login item')
    if [[ "${loginItems}" == *"${appName}"* ]]
        then
            logItNow quiet "${appName} is already in the Login Items."
            if [[ "${reFresh}" == 'refresh' ]]
                then
                    launchctl asuser "${userID}" osascript -e 'tell application "System Events" to delete login item "'"${appName}"'"' > /dev/null 2>&1
                    launchctl asuser "${userID}" osascript -e 'tell application "System Events" to make login item at end with properties {name:"'"${appName}"'", path:"'"${appPath}"'", kind:"Application", hidden:false}' > /dev/null 2>&1
            fi
            unset userName appName appPath reFresh loginItems
            return
        else
            logItNow loud "${appName} is not in the Login Items. Adding now."
            launchctl asuser "${userID}" osascript -e 'tell application "System Events" to make login item at end with properties {name:"'"${appName}"'", path:"'"${appPath}"'", kind:"Application", hidden:false}' > /dev/null 2>&1
    fi
    unset userID appName appPath reFresh loginItems
}

function changeOwnership
{
    # Usage: changeOwnership <folder>
    folderToChange="${1}"
    chmod -R 755 "${folderToChange}" > /dev/null 2>&1
    chownResults=$(chown -R "${CONSOLE_USER}":'CP\Domain Users' "${folderToChange}")
    if [[ "${chownResults}" == *'illegal group name'* ]]
        then
            logItNow quiet 'chown is rejecting the CP\Domain Users group. Using staff instead.'
            chown -R "${CONSOLE_USER}":staff "${folderToChange}"
    fi
    unset folderToChange
}

function spawnJamfHelperOKWindow
{
    # Usage: spawnJamfHelperOKWindow "<title>" "<heading>" "<description>"
    # Generic OK Info Window. 
    if [[ "$#" == "0" ]]
        then
            logItNow loud "${FUNCNAME[0]}"': No parameters passed to this function.'
            return 1
    fi
    windowTitle="${1}"
    windowHeading="${2}"
    windowDescription="${3}"
    launchctl asuser "${CONSOLE_USER_UID}" "${JAMF_HELPER_PATH}" -windowType utility \
        -title "${windowTitle}" -heading "${windowHeading}" \
        -description "${windowDescription}" -button1 'OK' -icon "${ICON_PATH}" \
        -iconSize 120 -alignDescription natural -timeout 300 > /dev/null 2>&1
    unset windowTitle windowHeading windowDescription
}

function installSuccessYo
{
    # Usage: installSuccessYo "<app-name>" "<version-number>"
    appName="${1}"
    appVersion="${2}"
    if [[ -e "${yoPath}" ]] && [[ -n "${appName}" ]] && [[ -n "${appVersion}" ]]
        then
            launchctl asuser "${CONSOLE_USER_UID}" "${yoPath}" -t "${appName} Installation" -s 'Mac Support' -n "${appName} version ${appVersion} installed." > /dev/null 2>&1
        else
            logItNow quiet "${FUNCNAME}"': Yo is not installed or no values were passed to this function.'
    fi
    unset appName appVersion
}

function launchApp
{
    # Usage: launchApp "<app-path>"
    if [[ "$#" == "0" ]] || [[ ! -e "${1}" ]]
        then
            logItNow loud 'Function: launchApp: Please pass a filepath to this function.'
            return 1
    fi
    appPath="${1}"
    launchctl asuser "${CONSOLE_USER_UID}" open "${appPath}"
    unset appPath
}

function installAppFrom
{
    # Usage: "<path-to-source>" "<path-to-destination"
    if [[ "$#" == "0" ]] || [[ ! -d "${1}" ]]
        then
            logItNow loud 'Function: installAppFrom: Please pass parameters to this function.'
            return 1
    fi
    # Remove trailing slashes if they were passed to the parameter.
    appSource="${1/.app\//.app}"
    appDestination="${2/.app\//.app}"
    appBase="$(basename "${appSource}")"
    appComplete="${appDestination}/${appBase}"
    if [[ -d "${appSource}" ]]
        then
            if [[ -d "${appComplete}" ]]
                then
                    logItNow quiet 'Making backup of old installation.'
                    fileCopy "${appComplete}" "/private/tmp/${appBase}.backup" overwrite > /dev/null
                    removeItems quiet "${appComplete}" > /dev/null
            fi
            fileCopy "${appSource}" "${appDestination}" overwrite > /dev/null
            changeOwnership "${appComplete}" > /dev/null
        else
            printf '%s\n' 'NoSource'
            return 1
    fi
    changeOwnership "${appComplete}" > /dev/null
    appDestinationVersion="$(appInstalledVersion "${appComplete}")"
    if [[ "${appDestinationVersion}" == 'NotInstalled' ]] && [[ -d "/private/tmp/${appBase}.backup" ]]
        then
            printf '%s\n' 'Fallback'
            removeItems quiet "${appComplete}" > /dev/null
            fileCopy "/private/tmp/${appBase}.backup" "${appDestination}" > /dev/null
            changeOwnership "${appComplete}" > /dev/null
            return 1
    fi
    printf '%s\n' "${appDestinationVersion}"
    removeItems quiet "/private/tmp/${appBase}.backup" > /dev/null
    unset appSource appDestination appBase appDestinationVersion appComplete
}

function checkSignature
{
    # Usage: checkSignature "<path-to-app>" "<team-identifier>"
    appPath="${1}"
    teamIdentifier="${2}"
    signatureStatus=$(codesign -d -vvvv "${appPath}" 2>&1)
    if [[ "${signatureStatus[*]}" == *"${teamIdentifier}"* ]]
        then
            printf '%s\n' 'Valid'
        else
            printf '%s\n' 'NotValid'
    fi
    unset appPath teamIdentifier signatureStatus
}

###############################################################################
#-----------------------------------------------------------------------------#
#   Script Logic
#-----------------------------------------------------------------------------#
###############################################################################

# Print a newline at the beginning of the script to provide cleaner output.
printf '\n'
# Then output standardized header with thisScriptName as its title.
logItNowHeader "${thisScriptName}"

# Install needed third party utilities. The installDependency function will just
# return the path passed to it if it is either installed successfully or already
# exists. If not, it will quit the script entirely.
dockutilPath="$(installDependency installdockutil "${DOCKUTIL_PATH}")"
yoPath="$(installDependency installyo "${YO_PATH}")"
getConsoleUser
onNetwork

if [[ -n "${parameterError[*]}" ]]
    then
        logItNow loud 'The following errors occured while reading in the positional parameters:'
        for error in "${parameterError[@]}"
            do
                logItNow loud "${error}"
            done
        logItNowFooter "${thisScriptName}"
        exit 1
fi

declare -a webexTeamsUserFiles=(\
    '/Users/'"${CONSOLE_USER}"'/Library/Application Support/Cisco Spark' \
    '/Users/'"${CONSOLE_USER}"'/Library/Application Support/Cisco-Systems.Spark' \
    '/Users/'"${CONSOLE_USER}"'/Library/Caches/Cisco-Systems.Spark' \
    '/Users/'"${CONSOLE_USER}"'/Library/Caches/com.crashlytics.data/Cisco-Systems.Spark' \
    '/Users/'"${CONSOLE_USER}"'/Library/Caches/io.fabric.sdk.mac.data/Cisco-Systems.Spark' \
    '/Users/'"${CONSOLE_USER}"'/Library/Cookies/Cisco-Systems.Spark.binarycookies' \
    '/Users/'"${CONSOLE_USER}"'/Library/Logs/SparkMacDesktop' \
    '/Users/'"${CONSOLE_USER}"'/Library/Preferences/Cisco-Systems.Spark.plist' \
    '/Users/'"${CONSOLE_USER}"'/Library/Saved Application State/Cisco-Systems.Spark.savedState' \
    '/Users/'"${CONSOLE_USER}"'/Library/WebKit/Cisco-Systems.Spark' \
    )

if [[ "$(getRunningApps "${CONSOLE_USER}")" == *'Cisco Spark'* ]]
    then
        runningApp='Cisco Spark'
elif [[ "$(getRunningApps "${CONSOLE_USER}")" == *'Webex Teams'* ]]
    then
        runningApp='Webex Teams'
    else
        runningApp='None'
fi

if [[ -d '/Applications/Cisco Spark.app/' ]] || [[ -d '/Applications/Webex Teams.app' ]]
    then
        killSignedProcess "${runningApp}" "${TEAM_IDENTIFIER}"
        removeItems quiet '/Applications/Cisco Spark.app' '/Applications/Webex Teams.app' > /dev/null
fi

declare -a appsInstalled=(\
            '/Users/'"${CONSOLE_USER}"'/Applications/Webex Teams'*'.app' \
            '/Users/'"${CONSOLE_USER}"'/Applications/Cisco Spark'*'.app' \
            )

if [[ "${appsInstalled}" == *'Cisco Spark'* ]]
    then
        appInstalled='Cisco Spark'
elif [[ "${appsInstalled}" == *'Webex Teams'* ]]
    then
        appInstalled='Webex Teams'
fi

webexTeamsInstalled="$(appInstalledVersion '/Users/'"${CONSOLE_USER}"'/Applications/'"${appInstalled}"'.app')"

if [[ "${webexTeamsInstalled}" == "${expectedWebexTeamsVersion}" ]] && [[ -n "${expectedWebexTeamsVersion}" ]]
    then
        logItNow loud 'Webex Teams is already expected version. Exiting now.'
        logItNowFooter "${thisScriptName}"
        exit 0
fi

logItNow quiet "User Initiated Update is ${userInitiatedUpdate}, Revert Webex Teams is ${revertWebexTeams}, and Webex Teams Upgrade is ${upgradeWebexTeams}"

# If this script is passed the instruction to revert to an old version of the
# apps, then we will process that here and then exit. The revertWebexTeams
# parameter variable should contain the name of the app ('Cisco Spark' or
# 'Webex Teams') that we want to return to. This will be used throughout this
# section of the script.
if [[ "${revertWebexTeams}" != "No" ]] && [[ -n "${revertWebexTeams}" ]]
    then
        if [[ -d "/private/tmp/${revertWebexTeams}.app" ]]
            then
                killSignedProcess "${runningApp}" "${TEAM_IDENTIFIER}"
                installStatus="$(installAppFrom "/private/tmp/${revertWebexTeams}.app" '/Users/'"${CONSOLE_USER}"'/Applications/')"
            else
                logItNow loud "Error: Old version of ${revertWebexTeams} did not download. Exiting."
                logItNowFooter "${thisScriptName}"
                exit 1
        fi

        if [[ "${installStatus}" == 'Fallback' ]]
            then
                logItNow loud "Fatal error: ${revertWebexTeams} did not install. App was returned to previously installed version."
                launchApp '/Users/'"${CONSOLE_USER}"'/Applications/'"${revertWebexTeams}"'.app/'
                logItNowFooter "${thisScriptName}"
                exit 1
        fi

        if [[ "${installStatus}" != "${expectedWebexTeamsVersion}" ]]
            then
                logItNow loud 'App did not revert to the expected version.'
                launchApp '/Users/'"${CONSOLE_USER}"'/Applications/'"${revertWebexTeams}"'.app/'
                logItNowFooter "${thisScriptName}"
                exit 1
        fi

        logItNow loud "The ${revertWebexTeams} version for user ${CONSOLE_USER} is now" "${installStatus}"
        # Clean up user files in case there are issues with reverting to an old version.
        for file in "${webexTeamsUserFiles[@]}"
            do
                removeItems quiet "${file}"
            done
        addLoginItem "${CONSOLE_USER_UID}" "${revertWebexTeams}" '/Users/'"${CONSOLE_USER}"'/Applications/'"${revertWebexTeams}"'.app/' refresh
        launchApp '/Users/'"${CONSOLE_USER}"'/Applications/'"${revertWebexTeams}"'.app/'
        logItNowFooter "${thisScriptName}"
        exit 0

# If Webex Teams is already installed on this computer, and yet the Self Service
# Policy is used, we will assume someone wants a clean install of the app, and
# we will remove the existing applications and all support files and reinstall.
# Since this will effectively be a new install, we will only log the choice here
# and perform the rest of the operations later.
elif [[ "${webexTeamsInstalled}" != 'NotInstalled' ]] && [[ "${userInitiatedUpdate}" == 'Yes' ]]
    then
        logItNow loud 'Webex Teams is already installed, but user decided to' \
                'update from Self Service. No need to revert so initiating' \
                'standard reinstallation.'

# If this script was used as part of an automatic update, but we are not forcing
# an update to a specific version, we will simply note that nothing needs to be
# done and exit.
elif [[ "${appInstalled}" == 'Webex Teams' ]] && [[ "${webexTeamsInstalled}" != 'NotInstalled' ]] && [[ "${userInitiatedUpdate}" == 'No' ]] && [[ "${upgradeWebexTeams}" == 'No' ]]
    then
        logItNow loud 'Webex Teams is already installed. Exiting now.'
        logItNowFooter "${thisScriptName}"
        exit 0

# If Webex Teams is already installed, but we want to force an update (maybe 
# because the current version is stuck because of a bug), we will initiate this
# process now, but let the users know that we are going to be quitting the app
# as a courtesy.
elif [[ "${webexTeamsInstalled}" != 'NotInstalled' ]] && [[ "${userInitiatedUpdate}" == 'No' ]] && [[ "${upgradeWebexTeams}" == 'Yes' ]]
    then
        logItNow loud "App is already installed, but upgrade being forced by admin. Throwing up warning if app is running."
        if [[ "${runningApp}" != 'None' ]]
            then
                spawnJamfHelperOKWindow "${runningApp} Update" "${runningApp} must close" "An important update has been released for Cisco Spark. It will now be known as Webex Teams. Please press OK and Cisco Spark will close. Once the installation is complete, Webex Teams will appear in your Dock."
        fi

# If the app is not installed to begin with, then we will install it now.
elif [[ "${webexTeamsInstalled}" == 'NotInstalled' ]]
    then
        logItNow loud 'Webex Teams is not installed. Initializing installation.'
fi

logItNow loud "Downloading from ${downloadWebexTeamsURL}"

removeItems quiet '/tmp/WebexTeams.dmg' > /dev/null
curl -sS -L "${curlUserAgent[@]}" "${curlProxy[@]}" "${downloadWebexTeamsURL}" -o '/private/tmp/WebexTeams.dmg' > /dev/null

if [[ -e '/tmp/WebexTeams.dmg' ]]
    then
        mkdir '/private/tmp/WebexTeams' > /dev/null 2>&1
        hdiutil attach -nobrowse '/private/tmp/WebexTeams.dmg' -mountpoint '/private/tmp/WebexTeams' > /dev/null
    else
        logItNow loud "WebexTeams.dmg did not download. Exiting."
        logItNowFooter "${thisScriptName}"
        exit 1
fi

declare -a downloadedApps=(\
    '/private/tmp/WebexTeams/Cisco Spark'*'.app' \
    '/private/tmp/WebexTeams/Webex Teams'*'.app' \
    )

if [[ "${downloadedApps}" == *'Cisco Spark'* ]]
    then
        downloadedApp='Cisco Spark'
elif [[ "${downloadedApps}" == *'Webex Teams'* ]]
    then
        downloadedApp='Webex Teams'
fi

if [[ "$(checkSignature '/private/tmp/WebexTeams/'"${downloadedApp}"'.app' "${TEAM_IDENTIFIER}")" != 'Valid' ]]
    then
        logItNow loud "Fatal Error: Signature of downloaded app does not contain the TeamIdentifier ${TEAM_IDENTIFIER}. Exiting now."
        hdiutil detach '/private/tmp/WebexTeams' > /dev/null
        removeItems loud '/private/tmp/WebexTeams.dmg'
        logItNowFooter "${thisScriptName}"
        exit 1
fi

logItNow quiet 'Downloaded dmg contains a signed app. Killing the currently running app to continue the installation process.'
killSignedProcess "${runningApp}" "${TEAM_IDENTIFIER}"

installStatus="$(installAppFrom '/private/tmp/WebexTeams/'"${downloadedApp}"'.app' '/Users/'"${CONSOLE_USER}"'/Applications/')"

hdiutil detach '/private/tmp/WebexTeams' > /dev/null
removeItems quiet '/private/tmp/WebexTeams.dmg' '/private/tmp/WebexTeams'

if [[ "${installStatus}" == 'Fallback' ]]
    then
        logItNow loud "Fatal error: Webex Teams did not install. App was returned to previously installed version."
        launchApp '/Users/'"${CONSOLE_USER}"'/Applications/'"${appInstalled}"'.app/'
        logItNowFooter "${thisScriptName}"
        exit 1
elif [[ "${installStatus}" == 'NotInstalled' ]]
    then
        logItNow loud'Fatal error: Webex Teams did not install.'
        logItNowFooter "${thisScriptName}"
        exit 1
fi

logItNow quiet "The Webex Teams version for user ${CONSOLE_USER} is now ${installStatus}"
for file in "${webexTeamsUserFiles[@]}"
    do
        removeItems quiet "${file}"
    done

# If we've updated to Webex Teams, let's clean up Cisco Spark.
if [[ "${downloadedApp}" == 'Webex Teams' ]]
    then
        removeItems quiet '/Users/'"${CONSOLE_USER}"'/Applications/Cisco Spark.app/'
fi

addAppToDock "${CONSOLE_USER}" "${downloadedApp}" '/Users/'"${CONSOLE_USER}"'/Applications/'"${downloadedApp}"'.app/' refresh
addLoginItem "${CONSOLE_USER_UID}" "${downloadedApp}" '/Users/'"${CONSOLE_USER}"'/Applications/'"${downloadedApp}"'.app/' refresh

launchApp '/Users/'"${CONSOLE_USER}"'/Applications/'"${downloadedApp}"'.app'

logItNow loud "The ${downloadedApp} version installed is now ${installStatus}"
installSuccessYo "${downloadedApp}" "${installStatus}"


logItNowFooter "${thisScriptName}"

exit 0
