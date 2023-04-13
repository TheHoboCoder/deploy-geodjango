# deploy-geodjango

A simple script to deploy geodjango on Ubuntu, based on harikvpy/deploy-django.
Designed mainly for personal use, so use it at your own risk.

# Changes

1. Using Apache and mod_wsgi
2. Dropped support for Python2
3. Using venv instead of virtualvenv

# Usage

1. clone this repository
2. clone your project. Your project rep and this rep must be in same dir. Also your project must contain requirements.txt file
3. run deploy script as root, with first argument equal to your project name
4. script will copy your project to /webapps/<project_name>_project folder and deploy everything.


