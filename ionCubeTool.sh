#!/bin/bash

USED_PHP_VERSION=74

IONCUBE_DOWNLOAD_BASE_URL=https://downloads.ioncube.com/loader_downloads
IONCUBE_DOWNLOAD_TAR=ioncube_loaders_lin_armv7l.tar.gz

phpVersionWithDot="${USED_PHP_VERSION:0:1}.${USED_PHP_VERSION:1:1}"
ioncubeLoaderlib="ioncube_loader_lin_${phpVersionWithDot}.so"
phpFpmIniFile="/volume1/@appstore/PHP${phpVersionWithDot}/misc/php-fpm.ini"

# check if run as root
if [ $(id -u "$(whoami)") -ne 0 ]; then
	echo "enableFileRunPHPionCube needs to run as root!"
	exit 1
fi

# service restart needed?
serviceRestart=0

# Check if tar is downloaded
if [ ! -d "/usr/local/lib/php${USED_PHP_VERSION}/modules/ioncube" ]; then
	cd "/usr/local/lib/php${USED_PHP_VERSION}/modules/"
	wget "${IONCUBE_DOWNLOAD_BASE_URL}/${IONCUBE_DOWNLOAD_TAR}"
	tar xvfz "${IONCUBE_DOWNLOAD_TAR}"
	((serviceRestart++))
fi

# Check if zend-extension exists
if ! grep -q "${ioncubeLoaderlib}" "$phpFpmIniFile"; then
#if [ ! -f /run/php-fpm/conf.d/filerun.ini ]; then
	echo "adding zend_extension /usr/local/lib/php${USED_PHP_VERSION}/modules/ioncube/${ioncubeLoaderlib} to /volume1/@appstore/PHP${phpVersionWithDot}/misc/php-fpm.ini"
	sed -i "1 i\zend_extension = /usr/local/lib/php74/modules/${ioncubeLoaderlib}" "$phpFpmIniFile"
	#((serviceRestart++))
fi

# Restart service if needed
if [ $serviceRestart -gt 0 ]; then
	echo "Config modified. Restarting PHP-${phpVersionWithDot} service..."
	if [ -x /usr/syno/sbin/synoservice  ]; then
	    synoservice --restart pkgctl-PHP${phpVersionWithDot}
	else
		echo "Could not restart PHP-${phpVersionWithDot} service! Please reboot or try to restart manually via Package Center."
		exit 1
	fi
	echo "PHP-${phpVersionWithDot} service restarted."
else
	echo "Config untouched."
fi
exit 0
