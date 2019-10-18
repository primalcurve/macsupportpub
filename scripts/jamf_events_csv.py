#!/System/Library/Frameworks/Python.framework/Versions/Current/bin/python
# -*- coding: utf-8 -*-
"""
jamf_events_csv
Call as many jamf policies as you want by their custom event triggers. You can
also flush the policy history if desired using the first position in the
first parameter.

The purpose of this script is to parse the parameter output of a jamf policy
in order to run policies by their custom event triggers. In order to maximize
the available space, each parameter is split along commas (hence csv).

If the parameter is in the following form: "eventName:background", then the
process will be run in the background and this script will not wait for its
output.
"""

import os
import argparse
import subprocess


# Paths to binaries
JAMF = ("/usr/local/bin/jamf")


def build_argparser():
    """
    Creates the argument parser
    """
    description = "Adds or removes printers by parameter."
    parser = argparse.ArgumentParser(description=description)

    # Collect parameters 1-3 into a list; we'll ignore them
    parser.add_argument("params", nargs=3)

    # Assign names to other passed parameters
    parser.add_argument("jamf_events4", nargs="?", default="",
                        help="""jamf event in csv form.
                        Use the following syntax:
                        installJamfThing1,installJamfThing2,etc""")
    parser.add_argument("jamf_events5", nargs="?", default="",
                        help="""jamf event in csv form.
                        Use the following syntax:
                        installJamfThing1,installJamfThing2,etc""")
    parser.add_argument("jamf_events6", nargs="?", default="",
                        help="""jamf event in csv form.
                        Use the following syntax:
                        installJamfThing1,installJamfThing2,etc""")
    parser.add_argument("jamf_events7", nargs="?", default="",
                        help="""jamf event in csv form.
                        Use the following syntax:
                        installJamfThing1,installJamfThing2,etc""")
    parser.add_argument("jamf_events8", nargs="?", default="",
                        help="""jamf event in csv form.
                        Use the following syntax:
                        installJamfThing1,installJamfThing2,etc""")
    parser.add_argument("jamf_events9", nargs="?", default="",
                        help="""jamf event in csv form.
                        Use the following syntax:
                        installJamfThing1,installJamfThing2,etc""")
    parser.add_argument("jamf_events10", nargs="?", default="",
                        help="""jamf event in csv form.
                        Use the following syntax:
                        installJamfThing1,installJamfThing2,etc""")
    parser.add_argument("jamf_events11", nargs="?", default="",
                        help="""jamf event in csv form.
                        Use the following syntax:
                        installJamfThing1,installJamfThing2,etc""")

    return parser.parse_known_args()[0]


def call_jamf_policy(event, background=False):
    """Calls jamf policy to install PPD.
    Args:
        (str) path: expected path of installed PPD.
        (str) event: jamf binary event (jamf policy -event custom_event)
    """
    print("\nProcessing requested jamf event " + event + "\n")
    cmd = [JAMF, 'policy', '-event', event]
    if background:
        print("%s was launched in the background." % event)
        _bkg_cmd(cmd)
    else:
        out, err = _ret_cmd(cmd)
        if err:
            print("A policy error occurred: %s\nOutput: %s\n" %
                  (err, out))
            return False
        elif 'No policies were found for the' in out:
            print(event + " is not scoped to this computer.\n")
            return True
        elif 'There was an error' in out:
            print(out + "\n")
            return False
        print(event + " was successful.\n")
    return True


def _bkg_cmd(cmd, *args):
    cmd.extend(args)
    _sp_popen(cmd)


def _ret_cmd(cmd, *args, **kwargs):
    cmd.extend(args)
    kwargs.update(stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = _sp_popen(cmd, **kwargs).communicate()
    return (stdout, stderr)


def _chk_cmd(cmd, *args, **kwargs):
    cmd.extend(args)
    # Shut up stderr and stdout regardless
    with open(os.devnull, 'w') as DEVNULL:
        kwargs.update(stdout=DEVNULL, stderr=DEVNULL)
        proc = _sp_popen(cmd, **kwargs)
    return proc.returncode


def _sp_popen(cmd, **kwargs):
    try:
        return subprocess.Popen(cmd, **kwargs)
    except OSError as err:
        return ("", err)


def flush_policy_history():
    """Flushes policy history using the jamf binary."""
    out, err = _ret_cmd([JAMF, 'flushPolicyHistory'])
    if err:
        print(
            "Unable to flush policy history.\n Error: %s\nCommand: %s\n" %
            (err, out))
        return False
    return True


def main():
    """Main program"""
    # Build the argparser
    args = build_argparser()

    # If the script is passed a "Flush" in its arguements,
    # flush the policy history.
    if args.jamf_events4.split(",")[0].lower() == "Flush".lower():

        if flush_policy_history():
            print("Policy history successfully flushed.")
        else:
            print("Policy history not flushed.")

    elif args.jamf_events4.split(",")[0].lower() in ["no", "false"]:
        args.jamf_events4 = ",".join(args.jamf_events4.split(",")[1:])
        print("Policy history flush not requested.")
    else:
        print("Policy history flush not requested.")

    # Iterate over the jamf_events attributes in args by number, then
    # create a dictionary per event that has whether or not the event is
    # to be spawned in the background.
    all_jamf_events = []
    for num in range(4, 12):
        for event in getattr(args, "jamf_events" + str(num)).split(","):
            name = event.split(":")[0]
            if not name:
                continue
            try:
                event.split(":")[1]
                background = True
            except IndexError:
                background = False
            # Create the list of dictionaries we will unpack below.
            all_jamf_events.append(dict(event=name, background=background))

    # The following function utilizes the ** magic operator for unpacking
    # mapping types into keyword arguments. See:
    # https://docs.python.org/2/library/stdtypes.html#typesmapping
    for event in all_jamf_events:
        call_jamf_policy(**event)


if __name__ == '__main__':
    main()
