#!/bin/sh

URLBASIC="https://plex.tv/api/downloads/5.json"
DOWNLOADPATH="/Plex"
LOGPATH="/Plex"
LOGFILE="PMS_Updater.log"
PMSPARENTPATH="/usr/local/share"
PMSLIVEFOLDER="plexmediaserver"
PMSBAKFOLDER="plexmediaserver.bak"
CERTFILE="/usr/local/share/certs/ca-root-nss.crt"
AUTOUPDATE=1
FORCEUPDATE=0
VERBOSE=1
REMOVE=1
LOGGING=1
#PLEXPASS="/Plex/plexpass.txt"
PLEXPASS=0
#PLEXTOKEN="$(sed -n 's/.*PlexOnlineToken="//p' "${PREFS}" | sed 's/\".*//')"
TOKENURL="$BASEURL?channel=plexpass&X-Plex-Token=$PLEXTOKEN"
PMSPATTERN="PlexMediaServer-[0-9]*.[0-9]*.[0-9]*.[0-9]*-[0-9,a-f]*-FreeBSD-amd64.tar.bz2"
# Try to find the Preferences.xml in all possible folders to fetch the token for downloads of PlexPass versions.
if [ -f /Plex\ Media\ Server/Preferences.xml ]; then
        PREFS="/Plex Media Server/Preferences.xml"
elif
        [ -f /usr/local/plex/Plex\ Media\ Server/Preferences.xml ]; then
        PREFS="/usr/local/plex/Plex Media Server/Preferences.xml"
elif
        [ -f /usr/local/plexdata/Plex\ Media\ Server/Preferences.xml ]; then
        PREFS="/usr/local/plexdata/Plex Media Server/Preferences.xml"
elif
        [ -f /usr/local/plexdata-plexpass/Plex\ Media\ Server/Preferences.xml ]; then
        PREFS="/usr/local/plexdata-plexpass/Plex Media Server/Preferences.xml"
else
   echo "Preferences.xml not found. This will likely prevent the script from downloading the latest version of Plex. You can still manually download Plex and run PMS_Updater.sh with the -l flag."
fi

# Initialize CURRENTVER to the script max so if reading the current version fails
# for some reason we don't blindly clobber things
CURRENTVER=9999.9999.9999.9999.9999

usage()
{
cat << EOF
usage: $0 options

This script will search the plex.tv download site for a download link
and if it is newer than the currently installed version the script will
download and optionaly install the new version.

OPTIONS:
   -u      PlexPass username
             If -u is specified without -p then the script will
             prompt the user to enter the password when needed
   -p      PlexPass password
   -c      PlexPass user/password file
             When wget is run with username and password on the
             command line, that information is displayed in the
             process list for all to see.  A more secure method
             is to create a file readable only by root that is
             formatted like this:
               user={Your Username Here}
               password={Your Password Here}
   -l      Local file to install instead of latest from Plex.tv
   -d      download folder (default /tmp) Ignored if -l is used
   -a      Auto Update to newer version
   -f      Force Update even if version is not newer
   -r      Remove update packages older than current version
             Done before any update actions are taken.
   -v      Verbose
   -n      Use normal version (not PlexPass) version
EOF
}


##  LogMsg()
##  READS:     STDIN (Piped input) $1 (passed in string) $LOGPATH $LOGFILE
##  MODIFIES:  NONE
##
##  Writes log entries to $LOGGINGPATH/$LOGGINGFILE
LogMsg()
{
    if [ "$1" = "-n" ]; then SWITCH="-n"; fi
    while read IN; do
      tdStamp=`date +"%Y-%m-%d %H:%M.%S"`
      if [ $LOGGING = 1 ]; then echo "$tdStamp  $IN" >> $LOGPATH/$LOGFILE; fi
      if [ $VERBOSE = 1 ] || [ "$1" = "-f" ]; then echo $SWITCH $IN; fi
    done
}

##  verNum()
##  READS:    $1 (passed in string)
##  MODIFIES: NONE
##
##  Converts the Plex version string to a mathmatically comparable
##      number by removing non numericals and padding each section with zeros
##      so v0.9.9.10.485 becomes 00000009000900100485
##      NOTE: Plex version numbers appear to have changed from something like
##      v0.9.14.4.1556-a10e3c2
##      to
##      v1.0.0.2261-a17e99e
##      Unfortunately this makes the new 1.X versions appear to be an older
##      version than the 0.9.X versions. This sed hack will append a .0 version
##      to the 1.X version so that it will now behave correctly. The new 1.X will
##      now looks omething like:
##      1.0.0.2261.0-a17e99e
##      And will convert it to the proper long form such as:
##      00010000000022610000
verNum()
{
    echo "$@" | sed -e 's/^.*[^\.]\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)\([^\.]\)/\1.0\2/' | awk -F. '{ printf("%04d%04d%04d%04d%04d", $1,$2,$3,$4,$5)}'
}


##  removeOlder()
##  READS:    $DOWNLOADPATH $PMSPATTERN $CURRENTVER $VERBOSE $LOGGING
##  MODIFIES: NONE
##
##  Searches $DOWNLOADPATH for PMS install packages and removes versions older
##  than $CURRENTVER
removeOlder()
{
    for FOUNDINSTALLFILE in `ls $DOWNLOADPATH/$PMSPATTERN 2>/dev/null`
    do {
        if [ $(verNum `basename $FOUNDINSTALLFILE`) -lt $(verNum $CURRENTVER) ]; then {
            echo Removing $FOUNDINSTALLFILE | LogMsg
            rm -f $FOUNDINSTALLFILE 2>&1 | LogMsg
        } fi
    } done
}



##  webFetch()
##  READS:    $1 (URL) $DOWNLOADPATH $USERPASSFILE $USERNAME $PASSWORD $VERBOSE $LOGGING
##  MODIFIES: NONE
##
##  invoke wget with configured account info
webFetch()
{
    local LOGININFO=""
    local QUIET="-q"

    # Check if PlexPass is set and handle user/pass file or direct credentials
    if [ $PLEXPASS = 1 ]; then
        if [ ! "x$USERPASSFILE" = "x" ] && [ -e $USERPASSFILE ]; then
            LOGININFO="--config=$USERPASSFILE"
        elif [ ! "x$USERNAME" = "x" ]; then
            if [ "x$PASSWORD" = "x" ]; then
                LOGININFO="--http-user=$USERNAME --ask-password"
            else
                LOGININFO="--http-user=$USERNAME --http-password=$PASSWORD"
            fi
        fi
    fi

    # Adjust verbosity
    if [ $VERBOSE = 1 ]; then QUIET=""; fi

    # Log and execute the fetch command
    echo "Downloading $1..." | LogMsg
    fetch $QUIET $LOGININFO -o "$DOWNLOADPATH/$(basename "$1")" "$1"
    
    # Check for errors during download
    if [ $? -ne 0 ]; then
        echo "Error downloading $1" | LogMsg
        echo
        exit 1
    fi
    echo "Download Complete" | LogMsg
    echo
}

##  findLatest()
##  READS:    $URLBASIC $URLPLEXPASS $DOWNLOADPATH $PMSPATTERN $VERBOSE $lOGGING
##  MODIFIES: $DOWNLOADURL
##
##  connects to the Plex.tv download site and scrapes for the latest download link
findLatest() {
    if [ $PLEXPASS = 1 ]; then local URL=$URLPLEXPASS; else local URL=$URLBASIC; fi
    if [ $VERBOSE = 1 ]; then echo; echo Using URL $URL ;fi
    SCRAPEFILE="$DOWNLOADPATH/plex_downloads.json"
    echo 
    echo Searching $URL for the FreeBSD download URL .....; echo | LogMsg -n
    fetch -o "$SCRAPEFILE" "$URLBASIC"

    if [ $? -ne 0 ]; then
        echo "Failed to download Plex version info." | LogMsg
        exit 1
    fi

    DOWNLOADURL=$(jq -r '.computer.FreeBSD.releases[0].url' "$SCRAPEFILE")

    if [ -z "$DOWNLOADURL" ]; then {
        echo "Could not find a FreeBSD download link in JSON data" | LogMsg -f
        exit 1
    } else {
        echo; echo "Found FreeBSD download URL: $DOWNLOADURL"; echo | LogMsg
    } fi
}

##  applyUpdate()
##  READS:    $PMSPARENTPATH $PMSLIVEFOLDER $PMSBAKFOLDER $LOCALINSTALLFILE $VERBOSE $LOGGING
##  MODIFIES: NONE
##
##  Removes anything in the specified backup location, stops
##    Plex, moves the current to backup, then tries to extract the new zip
##    to the live location.  If there is an error while unpacking the files
##    are deleted and the backup is moved back.  Plex is then started.
##    It could be possible to check status after starting a new plex and
##    rolling back if it does not start, should check that it is running
##    properly before hand to avoid constantly trying to update a broken
##    install
applyUpdate()
{

    echo Removing previous PMS Backup ..... | LogMsg -n
    rm -rf $PMSPARENTPATH/$PMSBAKFOLDER 2>&1 | LogMsg
    echo Done. | LogMsg -f
    echo 
    echo Stopping Plex Media Server .....| LogMsg -n
    service plexmediaserver stop 2>&1
    echo Done. | LogMsg -f
    echo 
    echo Moving current Plex Media Server to backup location .....| LogMsg -n
    mv $PMSPARENTPATH/$PMSLIVEFOLDER/ $PMSPARENTPATH/$PMSBAKFOLDER/ 2>&1 | LogMsg
    echo Done. | LogMsg -f
    echo 
    echo Extracting $LOCALINSTALLFILE .....| LogMsg -n
    mkdir $PMSPARENTPATH/$PMSLIVEFOLDER/ 2>&1 | LogMsg
    tar -xj --strip-components 1 --file $LOCALINSTALLFILE --directory $PMSPARENTPATH/$PMSLIVEFOLDER/ 2>&1 | LogMsg -f
    if [ $? -ne 0 ]; then {
        echo Error exctracting $LOCALINSTALLFILE. Rolling back to previous version. | LogMsg -f
        rm -rf $PMSPARENTPATH/$PMSLIVEFOLDER/ 2>&1 | LogMsg -f
        mv $PMSPARENTPATH/$PMSBAKFOLDER/ $PMSPARENTPATH/$PMSLIVEFOLDER/ 2>&1 | LogMsg -f
    } else {
        echo 
        echo Done. | LogMsg -f
    } fi
    ln -s $PMSPARENTPATH/$PMSLIVEFOLDER/Plex\ Media\ Server $PMSPARENTPATH/$PMSLIVEFOLDER/Plex_Media_Server 2>&1 | LogMsg
    ln -s $PMSPARENTPATH/$PMSLIVEFOLDER/libpython2.7.so.1 $PMSPARENTPATH/$PMSLIVEFOLDER/libpython2.7.so 2>&1 | LogMsg
    echo Starting Plex Media Server .....| LogMsg -n
    service plexmediaserver start
#    if ! service plexmediaserver status; then
#    if ! ps aux | grep plexmediaserver; then
#    echo "Plex did not start correctly. Rolling back to previous version." | LogMsg -f
    # Rollback logic here
#   fi
    echo Done. | LogMsg -f
    echo 
}

while getopts x."u:p:c:l:d:afvrn" OPTION
do
     case $OPTION in
         u) USERNAME=$OPTARG ;;
         p) PASSWORD=$OPTARG ;;
         c) USERPASSFILE=$OPTARG ;;
         l) LOCALINSTALLFILE=$OPTARG ;;
         d) DOWNLOADPATH=$OPTARG ;;
         a) AUTOUPDATE=1 ;;
         f) FORCEUPDATE=1 ;;
         v) VERBOSE=1 ;;
         r) REMOVE=1 ;;
         n) PLEXPASS=0 ;;
         ?) usage; exit 1 ;;
     esac
done

# Get the current version
CURRENTVER=`export LD_LIBRARY_PATH=$PMSPARENTPATH/$PMSLIVEFOLDER; $PMSPARENTPATH/$PMSLIVEFOLDER/Plex\ Media\ Server --version`
if [ $REMOVE = 1 ]; then removeOlder; fi

if [ "x$LOCALINSTALLFILE" = "x" ]; then {
    #  No local source provided, check the web
    findLatest || exit $?
    if [ $FORCEUPDATE = 1 ] || [ $(verNum `basename $DOWNLOADURL`) -gt $(verNum $CURRENTVER) ]; then {
        webFetch "$DOWNLOADURL"  || exit $?
        LOCALINSTALLFILE="$DOWNLOADPATH/`basename $DOWNLOADURL`"
    } else {
        echo Already running latest version $CURRENTVER, Use -f to force reinstall. | LogMsg
        
        exit
    } fi
} elif [ ! $FORCEUPDATE = 1 ] &&  [ $(verNum `basename $LOCALINSTALLFILE`) -le $(verNum $CURRENTVER) ]; then {
    echo Already running version $CURRENTVER | LogMsg
    echo Use -f to force install $LOCALINSTALLFILE | LogMsg
    echo 
    exit
} fi


# If either update flag is set then verify archive integrity and install
if [ $FORCEUPDATE = 1 ] || [ $AUTOUPDATE = 1 ]; then {
        echo Verifying $LOCALINSTALLFILE ..... | LogMsg -n
    bzip2 -t $LOCALINSTALLFILE
    if [ $? -ne 0 ]; then {
        echo $LOCALINSTALLFILE is not a valid archive, cannot update with this file. | LogMsg -f
    } else {
        echo Done | LogMsg -f
        applyUpdate
    } fi
} fi
