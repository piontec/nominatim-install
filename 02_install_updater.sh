#!/bin/bash

#set -x

# Ensure this script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "#     This script must be run as root." 1>&2
    exit 1
fi


## CREDENTIALS ###
# Name of the credentials file
configFile=.config.sh

# Generate your own credentials file by copying from .config.sh.template
if [ ! -e ./${configFile} ]; then
    echo "#	The config file, ${configFile}, does not exist - copy your own based on the ${configFile}.template file." 1>&2
    exit 1
fi 

# Load the credentials
. ./${configFile} 

## Updating Nominatim
### Using two threads for the update will help performance, by adding this option: --index-instances 2
### Going much beyond two threads is not really worth it because the threads interfere with each other quite a bit.
### If your system is live and serving queries, keep an eye on response times at busy times, because too many update threads might interfere there, too.
### Skip if doing a Docker install

# Check if we are running in a Docker container
if grep --quiet docker /proc/1/cgroup; then
    	echo "Not supported on docker"
	exit 1
fi

NOM_UP_LOGDIR=$BASE_DIR/log/nominatim
NOM_HOME=$BASE_DIR/${username}

apt-get -y install supervisor

# Bomb out if something goes wrong
set -e

echo "#	Preparing supervisor for update of Nominatim data in PostgreSQL"
if [ ! -d $NOM_UP_LOGDIR ]; then
    mkdir -p $NOM_UP_LOGDIR
fi
cat > /etc/supervisor/conf.d/nominatim-up.conf << EOF
[program:nominatim-up]
command=${NOM_HOME}/Nominatim/utils/update.php --import-osmosis-all --no-npi ${osm2pgsqlcache}
directory=${NOM_HOME}/Nominatim
autostart=true
autorestart=true
startretries=3
stderr_logfile=${NOM_UP_LOGDIR}/update.err.log
stdout_logfile=${NOM_UP_LOGDIR}/update.out.log
user=nominatim
EOF
 
service supervisor restart 
echo "#	$(date)	Nominatim updater installation completed."
#
## Done
#
## End of file
