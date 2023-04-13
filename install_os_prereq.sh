#!/bin/bash

source ./common_funcs.sh

check_root

# Prerequisite standard packages. If any of these are missing,
# script will attempt to install it. If installation fails, it will abort.
# simple deploy with apache mod_wsgi
LINUX_PREREQ=('build-essential' 'python3-dev' 'python3-pip' 'python3-venv' 'apache2' 'libapache2-mod-wsgi-py3' 'postgresql-14' 'libpq-dev' )
# geo specific packages
LINUX_PREREQ+=('postgresql-14-postgis-3' 'postgresql-server-dev-14' 'python3-psycopg2' 'binutils' 'libproj-dev' 'gdal-bin' 'libgdal-dev')

# Test prerequisites
echo "Checking if required packages are installed..."
declare -a MISSING
for pkg in "${LINUX_PREREQ[@]}"
    do
        echo "Installing '$pkg'..."
        apt-get -y install $pkg
        if [ $? -ne 0 ]; then
            echo "Error installing system package '$pkg'"
            exit 1
        fi
    done

if [ ${#MISSING[@]} -ne 0 ]; then
    echo "Following required packages are missing, please install them first."
    echo ${MISSING[*]}
    exit 1
fi

echo "All required packages have been installed!"

