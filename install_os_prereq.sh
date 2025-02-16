#!/bin/bash

source ./common_funcs.sh

check_root

# Prerequisite standard packages. If any of these are missing,
# script will attempt to install it. If installation fails, it will abort.
# simple deploy with apache mod_wsgi
LINUX_PREREQ=('build-essential' 'python3-dev' 'python3-pip' 'python3-venv' 'apache2' 'libapache2-mod-wsgi-py3' 'postgresql' 'libpq-dev' 'curl')
POSTGRES_V=`apt-cache search --names-only postgresql | grep -oP "^postgresql-\K13|14" | head -n 1`
echo "postgres_v = $POSTGRES_V"
# geo specific packages
LINUX_PREREQ+=("postgresql-$POSTGRES_V-postgis-3" "postgresql-server-dev-$POSTGRES_V" 'python3-psycopg2' 'binutils' 'libproj-dev' 'gdal-bin')

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

