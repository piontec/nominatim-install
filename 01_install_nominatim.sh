#!/bin/bash
# Script to install Nominatim on Ubuntu
# Tested on 14.04 (View Ubuntu version using 'lsb_release -a') using Postgres 9.3
#
# Based on OSM Nominatim wiki:
# http://wiki.openstreetmap.org/wiki/Nominatim/Installation
# Synced with: Latest revision as of 21:43, 21 May 2015


#set -x

VER=2.4.0
PG_VER=9.3

### CREDENTIALS ###
# Name of the credentials file
configFile=.config.sh
sql_force=force-utf8.sql

# Generate your own credentials file by copying from .config.sh.template
if [ ! -e ./${configFile} ]; then
    echo "#	The config file, ${configFile}, does not exist - copy your own based on the ${configFile}.template file." 1>&2
    exit 1
fi 

# Load the credentials
. ./${configFile} 

echo "Changing dir to $BASE_DIR"
if [ ! -d $BASE_DIR ]; then
    mkdir -p $BASE_DIR
fi 

nomInstalDir=$BASE_DIR/install
if [ ! -d $nomInstalDir ]; then
	mkdir $nomInstalDir
fi

cp ./config*.sh $nomInstalDir
cp ./${sql_force} $nomInstalDir
cd $BASE_DIR

WG="wget --retry-connrefused --waitretry=1 --read-timeout=20 --timeout=15 -t 16"
NOM_UP_LOGDIR=$BASE_DIR/log/nominatim
# Announce start
export DEBIAN_FRONTEND=noninteractive
echo "#	$(date)	Nominatim installation"

# Ensure this script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "#	This script must be run as root." 1>&2
    exit 1
fi

# Check if we are running in a Docker container
if grep --quiet docker /proc/1/cgroup; then
    dockerInstall=1
fi

# Bomb out if something goes wrong
set -e

# Ensure the system locale is UTF-8, to avoid Postgres install failure
echo "LANG=${utf8Language}.UTF-8" > /etc/default/locale
echo "LC_ALL=${utf8Language}.UTF-8" >> /etc/default/locale
sudo locale-gen ${utf8Language} ${utf8Language}.UTF-8
#dpkg-reconfigure locales
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Prepare the apt index; it may be practically non-existent on a fresh VM
apt-get update > /dev/null

# Install basic software
apt-get -y install sudo wget

# Check either planet or extract selected
if [ -z "${planetUrl}" -a -z "${geofabrikUrl}" ]; then
    # Report and fail
    echo "#	Configuration error, please specify either a full planet or a Geofabrik extract"
    exit 1
fi

# Check either planet or extract selected but not both
if [ -n "${planetUrl}" -a -n "${geofabrikUrl}" ]; then
    # Report and fail
    echo "#	Configuration error, please specify either a full planet or a Geofabrik extract, not both"
    echo "#	Planet: ${planetUrl}"
    echo "#	Extract: ${geofabrikUrl}"
    exit 1
fi

# Download
if [ -n "${planetUrl}" ]; then

    # Options for a full planet
    osmdatafilename=planet-latest.osm.pbf
    osmdatafolder=wholePlanet/
    osmdataurl=${planetUrl}${osmdatafilename}

else
    # Options for a Geofabrik Extract
    osmdatafilename=${osmdatacountry}-latest.osm.pbf
    osmdataurl=${geofabrikUrl}${osmdatafolder}${osmdatafilename}
    osmupdates=${geofabrikUrl}${osmdatafolder}${osmdatacountry}-updates
fi

echo "# downloading data: ${osmdatafilename}"

# Where the downloaded data is stored
osmdatapath=data/${osmdatafolder}${osmdatafilename}

## Osmosis
# Rather than the packaged version get the latest
#osmosisBinary=/usr/local/bin/osmosis

## Check Osmosis has been installed
if [ ! -L "${osmosisBinary}" ]; then

    # Announce Osmosis installation
    # !! Osmosis uses MySQL and that needs to be configured to use character_set_server=utf8 and collation_server=utf8_unicode_ci which is currently set up (machine wide) by CycleStreets website installation.
    echo "#	$(date)	CycleStreets / Osmosis installation"

    # Osmosis requires java
    apt-get -y install openjdk-7-jre libexpat1-dev lua5.2 liblua5.2-dev

    # Create folder
    mkdir -p /usr/local/osmosis

    # get the latest to here
    if [ ! -f /usr/local/osmosis/osmosis-latest.tgz ]; then
	$WG -O /usr/local/osmosis/osmosis-latest.tgz http://dev.openstreetmap.org/~bretth/osmosis-build/osmosis-latest.tgz
    fi

    # Create a folder for the new version
    mkdir -p /usr/local/osmosis/osmosis-latest

    # Unpack into it
    tar xzf /usr/local/osmosis/osmosis-latest.tgz -C /usr/local/osmosis/osmosis-latest

    # Remove the download archive
    rm -f /usr/local/osmosis/osmosis-latest.tgz

    # Repoint current to the new install
    rm -f /usr/local/osmosis/current

    # Link to it
    if [ -x /usr/local/bin/osmosis ]; then
        rm -f /usr/local/bin/osmosis
    fi
    ln -s /usr/local/osmosis/osmosis-latest/bin/osmosis /usr/local/bin/

    cp -a /usr/local/osmosis/ $BASE_DIR

    # Announce completion
    echo "#	Completed installation of osmosis"
fi
#

osmosisBinary=`which osmosis`
echo "Osmosis found at: ${osmosisBinary}"
#
### MAIN PROGRAM ###

# Ensure there is a nominatim user account
if id -u ${username} >/dev/null 2>&1; then
    echo "#	User ${username} exists already and will be used."
else
    echo "#	User ${username} does not exist: creating now."

    # Request a password for the Nominatim user account; see http://stackoverflow.com/questions/3980668/how-to-get-a-password-from-a-shell-script-without-echoing
    if [ ! ${password} ]; then
	stty -echo
	printf "Please enter a password that will be used to create the Nominatim user account:"
	read password
	printf "\n"
	printf "Confirm that password:"
	read passwordconfirm
	printf "\n"
	stty echo
	if [ $password != $passwordconfirm ]; then
	    echo "#	The passwords did not match"
	    exit 1
	fi
    fi

    # Create the nominatim user
    useradd -b $BASE_DIR -m -p $password $username
    echo "#	Nominatim user ${username} created"
fi

# Install software
# http://wiki.openstreetmap.org/wiki/Nominatim/Installation#Ubuntu.2FDebian
apt-get -y install build-essential libxml2-dev libgeos-dev libpq-dev libbz2-dev libtool automake libproj-dev
apt-get -y install libboost-dev libboost-system-dev libboost-filesystem-dev libboost-thread-dev
# Note: osmosis is removed from this next line (compared to wiki page) as it is installed directly
#apt-get -y install gcc proj-bin libgeos-c1 osmosis libgeos++-dev
apt-get -y install gcc proj-bin libgeos-c1 libgeos++-dev
apt-get -y install php5 php-pear php5-pgsql php5-json php-db
apt-get -y install postgresql postgis postgresql-contrib postgresql-9.3-postgis-2.1 postgresql-server-dev-9.3
apt-get -y install libprotobuf-c0-dev protobuf-c-compiler

#change postgresql data dir
/usr/bin/pg_dropcluster --stop $PG_VER main || true
/usr/bin/pg_createcluster -d $BASE_DIR/postgres --start $PG_VER main

# Additional packages
# bc is needed in configPostgresql.sh
apt-get -y install bc apache2 git autoconf-archive supervisor

## Install gdal, needed for US Tiger house number data
## !! More steps need to be added to this script to support that US data
#echo "#	$(date)	Installing gdal"
#apt-get -y install python-gdal

# Skip if doing a Docker install as kernel parameters cannot be modified
if [ -z "${dockerInstall}" ]; then
    # Tuning PostgreSQL
    echo "#	$(date)	Tuning PostgreSQL"
    ${nomInstalDir}/configPostgresql.sh ${postgresconfigmode} n ${override_maintenance_work_mem}
fi

# Restart postgres assume the new config
echo "#	$(date)	Restarting PostgreSQL"
service postgresql restart

# We will use the Nominatim user's homedir for the installation, so switch to that
NOM_HOME=$BASE_DIR/${username}
cd $NOM_HOME

# First Installation
# http://wiki.openstreetmap.org/wiki/Nominatim/Installation#First_Installation

# Get Nominatim software
# http://wiki.openstreetmap.org/wiki/Nominatim/Installation#Obtaining_the_Latest_Version
#if [ ! -d "/home/${username}/Nominatim/.git" ]; then
#    # Install
#    echo "#	$(date)	Installing Nominatim software"
#    sudo -u ${username} git clone --recursive https://github.com/twain47/Nominatim.git
#    cd Nominatim
#else
#    # Update
#    echo "#	$(date)	Updating Nominatim software"
#    cd Nominatim
#    sudo -u ${username} git pull
#    # Some of the schema is created by osm2pgsql which is updated by:
#    sudo -u ${username} git submodule update --init
#fi

echo "# Fetching nominatim"
if [ ! -f Nominatim-${VER}.tar.bz2 ]; then
   $WG http://www.nominatim.org/release/Nominatim-${VER}.tar.bz2
else 
   rm -rf Nominatim-${VER}
fi
tar xvf Nominatim-${VER}.tar.bz2
chown -R ${username} Nominatim-${VER}/
ln -s Nominatim-${VER} Nominatim
cd Nominatim

## Nominatim munin
apt-get -y install munin
## !! Look at the comments at the top of the nominatim_importlag file in the following and copy the setup section to a new file in: /etc/munin/plugin-conf.d/
if [ ! -L /etc/munin/plugins/nominatim_importlag ]; then
    ln -s "/${NOM_HOME}/Nominatim/munin/nominatim_importlag" '/etc/munin/plugins/nominatim_importlag'
    ln -s "/${NOM_HOME}/Nominatim/munin/nominatim_query_speed" '/etc/munin/plugins/nominatim_query_speed'
    ln -s "/${NOM_HOME}/Nominatim/munin/nominatim_nominatim_requests" '/etc/munin/plugins/nominatim_nominatim_requests'
fi


# Needed to help postgres munin charts work
apt-get -y install libdbd-pg-perl
sudo munin-node-configure --shell 2>&1 | grep postgres | sudo sh

sudo echo "
[nominatim_*] 
user www-data 
env.PGUSER www-data 
env.PGPORT 5432 
env.PGDATABASE nominatim 
env.age_warning 21600 
env.age_critical 86400 " >> /etc/munin/plugin-conf.d/munin-node 

sudo service munin-node restart

sed -e "s/^\ *Allow from localhost 127.0.0.0\/8 ::1/Allow from all\nRequire all granted/" /etc/munin/apache.conf > /tmp/munin.conf
sudo mv /tmp/munin.conf /etc/munin/apache.conf
sudo chown munin.munin /etc/munin/apache.conf
sudo service apache2 restart



# Compile Nominatim software
# http://wiki.openstreetmap.org/wiki/Nominatim/Installation#Compiling_the_Source
echo "#	$(date)	Compiling Nominatim software"
#sudo -u ${username} ./autogen.sh
sudo -u ${username} ./configure
sudo -u ${username} make

# Customization of the Installation
# http://wiki.openstreetmap.org/wiki/Nominatim/Installation#Customization_of_the_Installation

# Add local Nominatim settings
localNominatimSettings=/${NOM_HOME}/Nominatim/settings/local.php
cat > ${localNominatimSettings} << EOF
<?php
   // Paths
   @define('CONST_Postgresql_Version', '9.3');
   @define('CONST_Postgis_Version', '2.1');

   // Osmosis
   @define('CONST_Osmosis_Binary', '${osmosisBinary}');

   // Website settings
   @define('CONST_Website_BaseURL', '${urlsuffix}');
EOF

# By default, Nominatim is configured to update using the global minutely diffs
if [ -z "${planetUrl}" ]; then

    # When using GeoFabrik extracts append these lines to set up the update process
    cat >> ${localNominatimSettings} << EOF

   // Setting up the update process
   @define('CONST_Replication_Url', '${osmupdates}');
   @define('CONST_Replication_MaxInterval', '86400');     // Process each update separately, osmosis cannot merge multiple updates
   @define('CONST_Replication_Update_Interval', '86400');  // How often upstream publishes diffs
   @define('CONST_Replication_Recheck_Interval', '900');   // How long to sleep if no update found yet
EOF
fi

# Change settings file to Nominatim ownership
chown ${username}:${username} ${localNominatimSettings}


# Get Wikipedia data which helps with name importance hinting
echo "#	$(date)	Wikipedia data"

# These large files are optional, and if present take a long time to process by ./utils/setup.php later in the script.
# Download them if wanted by config and they are not already present.
if test -n "${includeWikipedia}" -a ! -r data/wikipedia_article.sql.bin; then
    sudo -u ${username} ${WG} --output-document=data/wikipedia_article.sql.bin http://www.nominatim.org/data/wikipedia_article.sql.bin
fi
if test -n "${includeWikipedia}" -a ! -r data/wikipedia_redirect.sql.bin; then
    sudo -u ${username} ${WG} --output-document=data/wikipedia_redirect.sql.bin http://www.nominatim.org/data/wikipedia_redirect.sql.bin
fi

# http://stackoverflow.com/questions/8546759/how-to-check-if-a-postgres-user-exists
# Creating the importer account in Postgres
echo "#	$(date)	Creating the importer account -s gives superuser rights"
sudo -u postgres psql postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='${username}'" | grep -q 1 || sudo -u postgres createuser -s $username

# Create website user in Postgres
echo "#	$(date)	Creating website user"
websiteUser=www-data
sudo -u postgres psql postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='${websiteUser}'" | grep -q 1 || sudo -u postgres createuser -SDR ${websiteUser}

# Nominatim module reading permissions
echo "#	$(date)	Nominatim module reading permissions"
chmod +x "$NOM_HOME"
chmod +x "$NOM_HOME/Nominatim"
chmod +x "$NOM_HOME/Nominatim/module"

# Ensure download folder exists
sudo -u ${username} mkdir -p data/${osmdatafolder}

# Download OSM data if not already present
if test ! -r ${osmdatapath}; then
	echo "#	$(date)	Download OSM data"
	sudo -u ${username} ${WG} --output-document=${osmdatapath} ${osmdataurl}
	
	# Verify with an MD5 match
	sudo -u ${username} ${WG} --output-document=${osmdatapath}.md5 ${osmdataurl}.md5
	if [ "$(md5sum ${osmdatapath} | awk '{print $1;}')" != "$(cat ${osmdatapath}.md5 | awk '{print $1;}')" ]; then
		echo "#	The md5 checksum for osmdatapath: ${osmdatapath} does not match, stopping."
		exit 1
	fi
	echo "#	$(date)	Downloaded OSM data integrity verified by md5 check."
fi


#idempotent
# Cannot make idempotent safely from here because that would require editing nominatim's setup scripts.
# Remove any pre-existing nominatim database
echo "#	$(date)	Remove any pre-existing nominatim database"
sudo -u postgres psql postgres -c "DROP DATABASE IF EXISTS nominatim"
sudo -u postgres psql -f ${nomInstalDir}/${sql_force}

# Import and index main OSM data
# http://wiki.openstreetmap.org/wiki/Nominatim/Installation#Import_and_index_OSM_data
cd ${NOM_HOME}/Nominatim/
echo "#	$(date)	Starting import and index OSM data"
echo "#	sudo -u ${username} ./utils/setup.php ${osm2pgsqlcache} --osm-file ${NOM_HOME}/Nominatim/${osmdatapath} --all 2>&1 | tee setup.log"
# Should automatically use one fewer than the number of threads: https://github.com/twain47/Nominatim/blob/master/utils/setup.php#L67
sudo -u ${username} ./utils/setup.php ${osm2pgsqlcache} --osm-file ${NOM_HOME}/Nominatim/${osmdatapath} --all 2>&1 | tee setup.log
# Note: if that step gets interrupted for some reason it can be resumed using:
# If the reported rank is 26 or higher, you can also safely add --index-noanalyse.
# sudo -u ${username} ./utils/setup.php --index --index-noanalyse --create-search-indices
echo "#	$(date)	Done Import and index OSM data"

# Add special phrases
echo "#	$(date)	Starting special phrases"
sudo -u ${username} ./utils/specialphrases.php --countries > data/specialphrases_countries.sql
sudo -u ${username} psql -d nominatim -f data/specialphrases_countries.sql
sudo -u ${username} rm -f specialphrases_countries.sql
sudo -u ${username} ./utils/specialphrases.php --wiki-import > data/specialphrases.sql
sudo -u ${username} psql -d nominatim -f data/specialphrases.sql
sudo -u ${username} rm -f specialphrases.sql
echo "#	$(date)	Done special phrases"

# Set up the website for use with Apache
sudo mkdir -pm 755 ${wwwNominatim}
sudo chown ${username} ${wwwNominatim}
sudo -u ${username} ./utils/setup.php --create-website ${wwwNominatim}

# Write out a robots file to keep search engines out
sudo -u ${username} cat > ${wwwNominatim}/robots.txt <<EOF
User-agent: *
Disallow: /
EOF

# Create a VirtualHost for Apache
echo "#	$(date)	Create a VirtualHost for Apache"
cat > /etc/apache2/sites-available/${nominatimVHfile} << EOF
<VirtualHost *:80>
        Alias /nominatim ${wwwNominatim}
        ServerName ${websiteurl}
        ServerAdmin ${emailcontact}
        DocumentRoot ${wwwNominatim}
        CustomLog \${APACHE_LOG_DIR}/nominatim-access.log combined
        ErrorLog \${APACHE_LOG_DIR}/nominatim-error.log
        LogLevel warn
        <Directory ${wwwNominatim}>
                Options FollowSymLinks MultiViews
                AddType text/html .php
                AllowOverride None
                Require all granted
        </Directory>
</VirtualHost>
EOF

# Enable the VirtualHost and restart Apache
a2ensite ${nominatimVHfile}
a2dissite 000-default.conf
# skip if doing a Docker install
if [ -z "${dockerInstall}" ]; then
    service apache2 reload
fi

echo "#	$(date)	Nominatim website created"

# Setting up the update process
rm -f ${NOM_HOME}/Nominatim/settings/configuration.txt
sudo -u ${username} ./utils/setup.php --osmosis-init
echo "#	$(date)	Done setup"

# Enabling hierarchical updates
sudo -u ${username} ./utils/setup.php --create-functions --enable-diff-updates
echo "#	$(date)	Done enable hierarchical updates"

## Adust PostgreSQL to do disk writes
echo "#	$(date)	Retuning PostgreSQL for disk writes"
${nomInstalDir}/configPostgresqlDiskWrites.sh

# Skip if doing a Docker install
if [ -z "${dockerInstall}" ]; then
    # Reload postgres assume the new config
    echo "#	$(date)	Reloading PostgreSQL"
    service postgresql reload
fi
echo "#	$(date)	Nominatim installation completed."

### Updating Nominatim
### Using two threads for the update will help performance, by adding this option: --index-instances 2
### Going much beyond two threads is not really worth it because the threads interfere with each other quite a bit.
### If your system is live and serving queries, keep an eye on response times at busy times, because too many update threads might interfere there, too.
### Skip if doing a Docker install
#if [ -z "${dockerInstall}" ]; then 
#    echo "#	Preparing supervisor for update of Nominatim data in PostgreSQL"
#    if [ ! -d $NOM_UP_LOGDIR ]; then
#        mkdir -p $NOM_UP_LOGDIR
#    fi
#    cat > /etc/supervisor/conf.d/nominatim-up.conf << EOF
#[program:nominatim-up]
#command=${NOM_HOME}/Nominatim/utils/update.php --import-osmosis-all --no-npi ${osm2pgsqlcache}
#directory=${NOM_HOME}/Nominatim
#autostart=true
#autorestart=true
#startretries=3
#stderr_logfile=${NOM_UP_LOGDIR}/update.err.log
#stdout_logfile=${NOM_UP_LOGDIR}/update.out.log
#user=nominatim
#EOF
# 
#    service supervisor restart 
#fi
##
## Done
#
## End of file
