#!/bin/bash
source ./common_funcs.sh

check_root

# conventional values that we'll use throughout the script
APPNAME=$1
DOMAINNAME=$2
SUBDOMEN=$3

# check appname was supplied as argument
if [ "$APPNAME" == "" ] || [ "$DOMAINNAME" == "" ]; then
	echo "Usage:"
	echo "  $ create_django_project_run_env <project> <domain>"
	exit 1
fi

echo "+++++++++++++++++++++++++++"
echo "INSTALLING OS REQUIRMENTS"
echo "+++++++++++++++++++++++++++"
./install_os_prereq.sh || error_exit "Error setting up OS prerequisites."
echo "+++++++++++++++++++++++++++"
echo "    INSTALLING PROJECT     "
echo "+++++++++++++++++++++++++++"
./deploy_django_project.sh $APPNAME $DOMAINNAME $SUBDOMEN
