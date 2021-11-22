#!/bin/bash

gitbin="$AUTOUPDATE_GIT_BIN"
if [ -z $gitbin ]; then
    if command -v /usr/bin/git > /dev/null; then
        gitbin="/usr/bin/git"
    elif command -v /usr/local/git/bin/git > /dev/null; then
        gitbin="/usr/local/git/bin/git"
    elif command -v /opt/bin/git > /dev/null; then
        gitbin="/opt/bin/git"
    else
        echo "[WARN][autoUpdate] Git not found, define env-var 'AUTOUPDATE_GIT_BIN' to use autoupdate."
        gitbin=""
    fi
fi

# run auto-update daily, not if file disableAutoUpdate exists or env AUTOUPDATE_DISABLE is set
if [ ! -z "${gitbin}" ] && [ ! -f "$(dirname "$0")/disableAutoUpdate" ] && [ -z "$AUTOUPDATE_DISABLE" ] && [ -d "$(dirname "$0")/.git" ]; then
    gitBranch=${AUTOUPDATE_BRANCH:=main}
    scriptName=$(basename "$0")
    today=$(date +'%Y-%m-%d')
    autoUpdateStatusFile="/tmp/.${scriptName}-autoUpdate"
    if [ -n "${AUTOUPDATE_CHECK_EVERY_TIME}" ] || [ ! -f "$autoUpdateStatusFile" ] || [ "${today}" != "$(date -r ${autoUpdateStatusFile} +'%Y-%m-%d')" ]; then
        echo "[autoUpdate] Checking git-updates of ${scriptName}..."
        touch "$autoUpdateStatusFile"
        cd "$(dirname "$0")" || exit 1
        $gitbin fetch
        commits=$(git rev-list HEAD...origin/"$gitBranch" --count)
        if [ $commits -gt 0 ]; then
            echo "[WARN][autoUpdate] Found updates ($commits commits)..."
            [ -z "${AUTOUPDATE_NO_LOCAL_RESET}" ] && $gitbin reset --hard 
            $gitbin pull --force
            echo "[autoUpdate] Executing new version..."
            exec "$(pwd -P)/${scriptName}" "$@"
            # In case executing new fails
            echo "[ERR][autoUpdate] Executing new version failed."
            exit 1
        fi
        echo "[autoUpdate] No updates available."
    else
        echo "[autoUpdate] Already checked for updates today."
    fi
fi

ionCubeTool-print-usage() {
    echo "manage ionCube-PHP-Zend-Extension"
    echo "  -d  --download                   get latest ionCube to separate 'Dev'-Folder"
    echo "  -l  --listVersions               list local installed Versions"
    echo "  -c  --createVersion [Version]    mark downloaded source as [Version]"
    echo "  -u  --useVersion [Version]       use [Version]"
    echo "  -mw --moveWizzard [web-folder]   move wizzard to [web-folder]"
    echo "  -rw --removeWizzard [web-folder] remove wizzard from [web-folder]"
}

# controlVars
serviceRestart=0
retState=0

doPatch=1
doDownload=0
doList=0
doCreate=0
doUseVersion=0
doMove=0
doRemove=0
while [ $# -gt 0 ]; do
    case "$1" in
        "-d" | "--download" )
            doDownload=1
            doPatch=0
            ;;
        "-l" | "--listVersions" )
            doList=1
            doPatch=0
        "-c" | "--createVersion" )
            doCreate=1
            doPatch=0
            [ -z "$2" ] && { echo "param 'createVersion' needs a Version-String"; exit 1; }
            shift
            ;;
        "-u" | "--useVersion" )
            doUseVersion=1
            [ -z "$2" ] && { echo "param 'useVersion' needs a existing Version-String"; doList=1; doUseVersion=0; doPatch=0; }
            shift
            ;;
        "-mw" | "--moveWizzard" )
            doMove=1
            doPatch=0
            [ -z "$2" ] && { echo "param 'moveWizzard' needs a Folder under /var/services/web"; exit 1; }
            shift
            ;;
        "-rw" | "--removeWizzard" )
            doRemove=1
            doPatch=0
            [ -z "$2" ] && { echo "param 'removeWizzard' needs a under /var/services/web"; exit 1; }
            shift
            ;;
        * )
            ionCubeTool-print-usage
            exit 0
            ;;
    esac
    shift
done

USED_PHP_VERSION=${IONCUBE_PHP_VERSION:-74}
CONFIG_CHANGED_RETURN_STATE=${IONCUBE_RETURN_STATE_IF_CHANGED:-3}

IONCUBE_DOWNLOAD_BASE_URL=https://downloads.ioncube.com/loader_downloads
IONCUBE_DOWNLOAD_TAR=ioncube_loaders_lin_armv7l.tar.gz
VERSION_DIR='ionCubeSrc'

phpVersionWithDot="${USED_PHP_VERSION:0:1}.${USED_PHP_VERSION:1:1}"
ioncubeLoaderlib="ioncube_loader_lin_${phpVersionWithDot}.so"
phpFpmIniFile="/volume1/@appstore/PHP${phpVersionWithDot}/misc/php-fpm.ini"

# check if run as root if patching should be done
if [ "$doPatch" -gt 0 ] && [ $(id -u "$(whoami)") -ne 0 ]; then
    echo "ionCubeTool needs to run as root, if the config should be patched!"
    exit 1
fi

if [ "$doDownload" -gt 0 ]; then
    [ ! -d "$VERSION_DIR/DEV" ] || mkdir "$VERSION_DIR/DEV"
    cd "$VERSION_DIR/DEV"
	rm -f *
    wget "${IONCUBE_DOWNLOAD_BASE_URL}/${IONCUBE_DOWNLOAD_TAR}"
    tar xvfz "${IONCUBE_DOWNLOAD_TAR}"
fi

if [ "$doList" -gt 0 ]; then
    ls -la "$VERSION_DIR"
fi

# Check if zend-extension exists in file
if [ "$doPatch" -gt 0 ]; then
    # TODO add use
    if ! grep -q "${ioncubeLoaderlib}" "$phpFpmIniFile"; then
        echo "adding zend_extension /usr/local/lib/php${USED_PHP_VERSION}/modules/${ioncubeLoaderlib} to $phpFpmIniFile"
        sed -i "1 i\zend_extension = /usr/local/lib/php${USED_PHP_VERSION}/modules/${ioncubeLoaderlib}" "$phpFpmIniFile"
        ((serviceRestart++))
        retState=$CONFIG_CHANGED_RETURN_STATE
    fi
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
exit $retState
