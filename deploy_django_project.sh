#!/bin/bash
# 
# simple deploy with mod_wsgi
# Usage:
#	$ deploy_django_project.sh <appname> <domain> <subdomen>
#   NOTE: domen without protocol
# assuming there's appname dir with django project next to this dir
# it will be copied to /webapps/appname_project/

source ./common_funcs.sh

check_root

# conventional values that we'll use throughout the script
APPNAME=$1
DOMAINNAME=$2
SUBDOMEN=$3

# check appname was supplied as argument
if [ "$APPNAME" == "" ] || [ "$DOMAINNAME" == "" ]; then
	echo "Usage:"
	echo "  $ create_django_project_run_env <project> <domain> [subdomen]"
	exit 1
fi

ROOTPATH=$SUBDOMEN

if [ "$SUBDOMEN" == "" ]; then
SUBDOMEN="/"
fi

GROUPNAME=webapps
# app folder name under /webapps/<appname>_project
APPFOLDER=$1_project
APPFOLDERPATH=/$GROUPNAME/$APPFOLDER

# ###################################################################
# Create the app folder
# ###################################################################
echo "Creating app folder '$APPFOLDERPATH'..."
mkdir -p /$GROUPNAME/$APPFOLDER || error_exit "Could not create app folder"

# test the group 'webapps' exists, and if it doesn't create it
getent group $GROUPNAME
if [ $? -ne 0 ]; then
    echo "Creating group '$GROUPNAME' for automation accounts..."
    groupadd --system $GROUPNAME || error_exit "Could not create group 'webapps'"
fi

# create the app user account, same name as the appname
grep "$APPNAME:" /etc/passwd
if [ $? -ne 0 ]; then
    echo "Creating automation user account '$APPNAME'..."
    useradd --system --gid $GROUPNAME --shell /bin/bash --home $APPFOLDERPATH $APPNAME || error_exit "Could not create automation user account '$APPNAME'"
fi

# change ownership of the app folder to the newly created user account
echo "Setting ownership of $APPFOLDERPATH and its descendents to $APPNAME:$GROUPNAME..."
chown -R $APPNAME:$GROUPNAME $APPFOLDERPATH || error_exit "Error setting ownership"
# give group execution rights in the folder;
chmod g+x $APPFOLDERPATH || error_exit "Error setting group execute flag"

# copy project to dir
echo "copying project to dir"
cp -R ../$APPNAME $APPFOLDERPATH/$APPNAME || error_exit "Error copying dir"
chown -R $APPNAME:$GROUPNAME $APPFOLDERPATH/$APPNAME
echo "remove git repository in $APPFOLDERPATH/$APPNAME"
rm -R $APPFOLDERPATH/$APPNAME/.git

# install python virtualenv in the APPFOLDER
echo "Creating environment setup for django app..."
su -l $APPNAME << EOF
pwd
echo "Setting up python virtualenv..."
/usr/bin/python3 -m venv $APPFOLDERPATH/django_venv || error_exit "Error installing Python 3 virtual environment to app folder"
EOF

# ###################################################################
# Generate Django production secret key
# ###################################################################
echo "Generating Django secret key..."
DJANGO_SECRET_KEY=`openssl rand -base64 48`
if [ $? -ne 0 ]; then
    error_exit "Error creating secret key."
fi
echo $DJANGO_SECRET_KEY > $APPFOLDERPATH/.django_secret_key
chown $APPNAME:$GROUPNAME $APPFOLDERPATH/.django_secret_key

# ###################################################################
# Generate DB password
# ###################################################################
echo "Creating secure password for database role..."
DBPASSWORD=`openssl rand -base64 32`
if [ $? -ne 0 ]; then
    error_exit "Error creating secure password for database role."
fi
echo $DBPASSWORD > $APPFOLDERPATH/.django_db_password
chown $APPNAME:$GROUPNAME $APPFOLDERPATH/.django_db_password

# ###################################################################
# Create the PostgreSQL database and associated role for the app
# Database and role name would be the same as the <appname> argument
# ###################################################################
echo "Creating PostgreSQL role '$APPNAME'..."
su postgres -c "createuser -S -D -R -w $APPNAME"
echo "Changing password of database role..."
su postgres -c "psql -c \"ALTER USER $APPNAME WITH PASSWORD '$DBPASSWORD';\""
echo "Creating PostgreSQL database '$APPNAME'..."
su postgres -c "createdb --owner $APPNAME $APPNAME"
echo "Activate PostGIS"
su postgres -c "psql $APPNAME -c \"CREATE EXTENSION postGIS\""


# ###################################################################
# Create the script that will init the virtual environment. T
# ###################################################################
echo "Creating virtual environment setup script..."
cat > /tmp/prepare_env.sh << EOF
DJANGODIR=$APPFOLDERPATH/$APPNAME          # Django project directory

export DJANGO_SETTINGS_MODULE=$APPNAME.settings.production # settings file for the app
export SECRET_KEY=`cat $APPFOLDERPATH/.django_secret_key`
export DB_PASSWORD=`cat $APPFOLDERPATH/.django_db_password`
export DJANGO_SUPERUSER_PASSWORD=changepassword
export DJANGO_SUPERUSER_EMAIL=example@examplemail.com

source ./django_venv/bin/activate
EOF
mv /tmp/prepare_env.sh $APPFOLDERPATH
chown $APPNAME:$GROUPNAME $APPFOLDERPATH/prepare_env.sh
chmod u+x $APPFOLDERPATH/prepare_env.sh

# ###################################################################
# Create the script that will install django req and run migrations
# ###################################################################
cat > /tmp/migrate.sh << EOF
#!/bin/bash
source ./prepare_env.sh
cd geoportal
# upgrade pip
pip install --upgrade pip
echo "installing app requirments"
echo "Installing psycopg2"
pip install psycopg2
echo "Installing other req"
pip install -r requirements.txt
echo "Verify installation..."
django-admin --version
python3 manage.py makemigrations 
python3 manage.py migrate
python3 manage.py collectstatic --no-input
EOF

mv /tmp/migrate.sh $APPFOLDERPATH
chown $APPNAME:$GROUPNAME $APPFOLDERPATH/migrate.sh
chmod u+x $APPFOLDERPATH/migrate.sh

chown $APPNAME:$GROUPNAME $APPFOLDERPATH/migrate.sh
chmod u+x $APPFOLDERPATH/migrate.sh

# ###################################################################
# In the new app specific virtual environment:
# 	1. Upgrade pip
#	2. Install app requirments
#	3. Create following folders:-
#		static -- Django static files (to be collected here)
#		media  -- Django media files
# ###################################################################

su -l $APPNAME << EOF
echo "Creating django static file folders..."
mkdir static media
# Change Django's default settings.py to use app/settings/{base.py|dev.py|production.py}
mv $APPNAME/$APPNAME/settings.py $APPNAME/$APPNAME/base.py
mkdir $APPNAME/$APPNAME/settings
mv $APPNAME/$APPNAME/base.py $APPNAME/$APPNAME/settings
EOF

echo "creating dev settings"
# save host ip, echo to remove whitespaces
IPHOST=$(echo $(hostname -I))
cat > $APPFOLDERPATH/$APPNAME/$APPNAME/settings/production.py << EOF
from .base import *

MEDIA_ROOT = "$APPFOLDERPATH/media/"
STATIC_ROOT = "$APPFOLDERPATH/static/"
STATIC_URL="static/"

def get_env_variable(var):
    '''Return the environment variable value or raise error'''
    try:
        return os.environ[var]
    except KeyError:
        error_msg = "Set the {} environment variable".format(var)
        raise ImproperlyConfigured(error_msg)

DEBUG = False

ALLOWED_HOSTS = ['$DOMAINNAME', '$IPHOST']
CORS_ORIGIN_ALLOW_ALL = False
DJANGO_VITE_DEV_MODE = False
CSRF_TRUSTED_ORIGINS = ['https://$DOMAINNAME', 'http://$DOMAINNAME']
CORS_ALLOWED_ORIGINS = CSRF_TRUSTED_ORIGINS
# uncomment to support https
# CSRF_COOKIE_SECURE = True
# SESSION_COOKIE_SECURE = True
# USE_X_FORWARDED_HOST = True 
# USE_X_FORWARDED_PORT = True
# SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')

# Get secret hash key from environment variable (set by ./prepre_env.sh)
SECRET_KEY = get_env_variable('SECRET_KEY')

# Get production DB password is from environment variable
DATABASES = {
    'default': {
        'ENGINE': 'django.contrib.gis.db.backends.postgis',
        'NAME': '$APPNAME',
        'USER': '$APPNAME',
        'PASSWORD': get_env_variable('DB_PASSWORD'),
        'HOST': 'localhost',
        'PORT': '',
    }
}

EOF
chown $APPNAME:$GROUPNAME $APPFOLDERPATH/$APPNAME/$APPNAME/settings/production.py


echo "Setting virtual environment for wsgi script..."
cat > $APPFOLDERPATH/$APPNAME/$APPNAME/prod_wsgi.py << EOF
import os

os.environ['DJANGO_SETTINGS_MODULE'] = '$APPNAME.settings.production'
os.environ['SECRET_KEY'] = '`cat $APPFOLDERPATH/.django_secret_key`'
os.environ['DB_PASSWORD'] = '`cat $APPFOLDERPATH/.django_db_password`'

from django.core.wsgi import get_wsgi_application
application = get_wsgi_application()
EOF


echo "final project setup"
su -l $APPNAME << EOF
./migrate.sh
source ./prepare_env.sh
cd $APPNAME
echo "creating superuser"
python3 manage.py createsuperuser --noinput --username admin
echo "load data dump"
python3 manage.py loaddata dump.json
echo "PROJECT SETUP DONE!"
EOF

# save apache config 
cp /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/000-default.conf.bak
echo "creating apache2 config"
cat > /etc/apache2/sites-available/000-default.conf << EOF
<VirtualHost *:80>

    Alias $ROOTPATH/static $APPFOLDERPATH/static
    <Directory $APPFOLDERPATH/static>
        Require all granted
    </Directory>

    Alias $ROOTPATH/media $APPFOLDERPATH/media
    <Directory $APPFOLDERPATH/media>
        Require all granted
    </Directory>

    <Directory $APPFOLDERPATH/$APPNAME>
        <Files prod_wsgi.py>
            Require all granted
        </Files>
    </Directory>

    WSGIDaemonProcess $DOMAINNAME python-path=$APPFOLDERPATH/$APPNAME python-home=$APPFOLDERPATH/django_venv
    WSGIProcessGroup $DOMAINNAME
    WSGIScriptAlias $SUBDOMEN $APPFOLDERPATH/$APPNAME/$APPNAME/prod_wsgi.py

</VirtualHost>
EOF

echo "set media group to www-data"
chown -R $APPNAME:www-data $APPFOLDERPATH/media
chmod -R g+w $APPFOLDERPATH/media



echo "DONE!"
