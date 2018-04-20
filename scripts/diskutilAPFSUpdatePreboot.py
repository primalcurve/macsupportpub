#!/usr/bin/python

import plistlib
import subprocess
import re
from SystemConfiguration import SCDynamicStoreCopyConsoleUser


def getconsoleuser():
    cfuser = SCDynamicStoreCopyConsoleUser(None, None, None)
    return cfuser[0]

diskutilPath = "/usr/sbin/diskutil"
consoleUser = getconsoleuser()

# Use diskutil command to get all apfs volumes on the system.
# Return as plist for parsing.
try:
    cmd = [diskutilPath, 'apfs', 'list', '-plist']
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (diskutilAPFSList, stderr) = proc.communicate()
    if proc.returncode:
        print 'Error: ', stderr
except OSError as error:
    print error.errno
    print error.filename
    print error.strerror

# Parse the Plist data returned by the diskutil command above.
# Iterate through volumes and select the DeviceIdentifier of the
# encrypted volume.
diskutilAPFSListPlist = plistlib.readPlistFromString(diskutilAPFSList)
diskutilVolumes = diskutilAPFSListPlist['Containers'][0]['Volumes']
for volume in diskutilVolumes:
    if volume['Encryption']:
        print('Encrypted vol: '
              + volume['Name']
              + ' - '
              + volume['DeviceIdentifier'])
        encryptedDev = volume['DeviceIdentifier']

# Use diskutil command to get the UUID of all users able to decrypt
# the local disk. Return as plist for parsing.
try:
    cmd = [diskutilPath, 'apfs', 'listUsers', encryptedDev, '-plist']
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (diskutilAPFSListUsers, stderr) = proc.communicate()
    if proc.returncode:
        print 'Error: ', stderr
except OSError as error:
    print error.errno
    print error.filename
    print error.strerror

# Parse the Plist data returned by the diskutil command above.
# Iterate through users and select the UUID of the OD user.
diskutilListUsersPlist = plistlib.readPlistFromString(diskutilAPFSListUsers)
diskutilUsers = diskutilListUsersPlist['Users']
for user in diskutilUsers:
    if user['APFSCryptoUserType'] == 'LocalOpenDirectory':
        print 'AD User UUID: ' + user['APFSCryptoUserUUID']
        odCryptoUUID = user['APFSCryptoUserUUID']

# Now that we know which device file references the encrypted volume
# we can send the updatePreboot command to it. This will trigger the
# system to update its OD password, etc.
try:
    cmd = [diskutilPath, 'apfs', 'updatePreboot', encryptedDev]
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (diskutilUpdatePrebootResults, stderr) = proc.communicate()
    if proc.returncode:
        print 'Error: ', stderr
except OSError as error:
    print error.errno
    print error.filename
    print error.strerror

regularExpressionUUID = r".*\n.*" + odCryptoUUID + r".*\n.*"
uuidSearch = re.findall(regularExpressionUUID, diskutilUpdatePrebootResults)
print("\n".join(uuidSearch))

regularExpressionFinish = (r".*UpdatePreboot: Exiting Update Preboot operation"
                           + r" with overall error=\(ZeroMeansSuccess\)=.*")
finishSearch = re.findall(regularExpressionFinish,
                          diskutilUpdatePrebootResults)
print("\n".join(finishSearch))
