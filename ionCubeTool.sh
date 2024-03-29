#!/bin/bash

# get installed git
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
if [ -n "${gitbin}" ] && [ ! -f "$(dirname "$0")/.autoUpdateDisable" ] && [ -z "$AUTOUPDATE_DISABLE" ] && [ -d "$(dirname "$0")/.git" ]; then
    [ -z "${AUTOUPDATE_NO_LOCAL_RESET}" ] && [ ! -f "$(dirname "$0")/.autoUpdateDisableHardReset" ] && doHardReset=1 || doHardReset=0
    scriptName=$(basename "$0")
    today=$(date +'%Y-%m-%d')
    autoUpdateStatusFile="/tmp/.${scriptName}-autoUpdate"
    if [ -n "${AUTOUPDATE_CHECK_EVERY_TIME}" ] || [ -f "$(dirname "$0")/.autoUpdateCheckEveryTime" ] || [ ! -f "$autoUpdateStatusFile" ] || [ "${today}" != "$(date -r ${autoUpdateStatusFile} +'%Y-%m-%d')" ]; then
        echo "[autoUpdate] Checking git-updates of ${scriptName}..."
        touch "$autoUpdateStatusFile"
        cd "$(dirname "$0")" || exit 1
        $gitbin fetch
        gitBranch=$(${gitbin} rev-parse --abbrev-ref HEAD)
        gitBranch=${gitBranch:=main}
        origin=$(${gitbin} for-each-ref --format='%(upstream:short)' "$(${gitbin} symbolic-ref -q HEAD)")
        [ -n "$origin" ] && commits=$(${gitbin} rev-list HEAD..."$origin" --count) || commits=0
        if [ $commits -gt 0 ]; then
            echo "[autoUpdate] Found updates ($commits commits)..."
            [ $doHardReset -gt 0 ] && $gitbin reset --hard
            $gitbin pull --force
            if [ $? -eq 0 ]; then
                localTip=$(${gitbin} show --abbrev-commit --format=oneline $(${gitbin} rev-list --max-count=1 @{u}) | head -1)
                echo "[autoUpdate] source is now at commit '$localTip'"

                echo "[autoUpdate] Executing new version..."
                exec "$(pwd -P)/${scriptName}" "$@"
            fi
            # In case there were an error (during pull or executing new)
            echo "[ERR][autoUpdate] Pulling or executing new version failed."
            exit 1
        fi
        echo "[autoUpdate] No updates available."
    else
        echo "[autoUpdate] Already checked for updates today."
    fi
fi

ionCubeTool-print-usage() {
    echo "manage ionCube-PHP-Zend-Extension"
    echo "  -d  --download                   use latest ionCube"
    echo "  -r  --revertToLastDownload       revert to latest downloaded version"
    echo "  -dp --disablePatch               remove ionCube-Patch"
    echo "  -uw --useWizzard [web-folder]    move wizzard to [web-folder]"
    echo "  -rw --removeWizzard [web-folder] remove wizzard from [web-folder]"
}

setGivenWebFolder() {
    [ -d "$1" ] && wizzardWebFolder="$1"
    [ -z "$wizzardWebFolder" ] && [ -d "/var/services/web/$1" ] && wizzardWebFolder="/var/services/web/$1"
}

# controlVars
serviceRestart=0
retState=0
wizzardWebFolder=''

doPatch=1
doDownload=0
doRevert=0
doDisablePatch=0
doUseWizz=0
doRemoveWizz=0
while [ $# -gt 0 ]; do
    case "$1" in
        "-d" | "--download" )
            doDownload=1
            ;;
        "-r" | "--revertToLastDownload" )
            doRevert=1
            ;;
        "-dp" | "--disablePatch" )
            doDisablePatch=1
            doPatch=0
            ;;
        "-uw" | "--useWizzard" )
            doUseWizz=1
            doPatch=0
            [ -z "$2" ] && { echo "[ERR] param 'useWizzard' needs a Folder under /var/services/web"; exit 1; }
            setGivenWebFolder $2
            [ -z "$wizzardWebFolder" ] && { echo "[ERR] Web-Folder '$2' not found!"; exit 1; }
            shift
            ;;
        "-rw" | "--removeWizzard" )
            doRemoveWizz=1
            doPatch=0
            [ -z "$2" ] && { echo "[ERR] param 'removeWizzard' needs a Folder under /var/services/web"; exit 1; }
            setGivenWebFolder $2
            [ -z "$wizzardWebFolder" ] && { echo "[ERR] Web-Folder '$2' not found!"; exit 1; }
            shift
            ;;
        * )
            ionCubeTool-print-usage
            exit 0
            ;;
    esac
    shift
done

USED_PHP_VERSION=${IONCUBE_PHP_VERSION:-81}
CONFIG_CHANGED_RETURN_STATE=${IONCUBE_RETURN_STATE_IF_CHANGED:-3}

IONCUBE_DOWNLOAD_BASE_URL=https://downloads.ioncube.com/loader_downloads
IONCUBE_DOWNLOAD_TAR=ioncube_loaders_lin_x86-64.tar.gz
DOWNLOAD_DIR="$(realpath $(dirname $0))/ionCubeSrc"
IONCUBE_LIB_DIR="$(realpath $(dirname $0))/ionCubeUsed"

phpVersionWithDot="${USED_PHP_VERSION:0:1}.${USED_PHP_VERSION:1:1}"
ioncubeLoaderlib="ioncube_loader_lin_${phpVersionWithDot}.so"
phpFpmIniFile="/volume1/@appstore/PHP${phpVersionWithDot}/misc/php-fpm.ini"
phpModules="/usr/local/lib/php${USED_PHP_VERSION}/modules"

[ -d $DOWNLOAD_DIR/ioncube ] || doDownload=1

# check if run as root if patching should be done
if [[ "$doPatch" -gt 0 || "$doDisablePatch" -gt 0 ]] && [ $(id -u "$(whoami)") -ne 0 ]; then
    echo "[ERR] ionCubeTool needs to run as root, if the config should be patched!"
    exit 1
fi

if [ "$doDownload" -gt 0 ]; then
    [ -f $IONCUBE_LIB_DIR/${ioncubeLoaderlib} ] && mv -f $IONCUBE_LIB_DIR/${ioncubeLoaderlib} $IONCUBE_LIB_DIR/${ioncubeLoaderlib}.last
    rm -f $DOWNLOAD_DIR/*
    wget "${IONCUBE_DOWNLOAD_BASE_URL}/${IONCUBE_DOWNLOAD_TAR}" -P $DOWNLOAD_DIR
    tar -xvzf $DOWNLOAD_DIR/${IONCUBE_DOWNLOAD_TAR} -C $DOWNLOAD_DIR 
    [ -f $DOWNLOAD_DIR/ioncube/${ioncubeLoaderlib} ] || { echo "[ERR] ${ioncubeLoaderlib} not found in download-folder $DOWNLOAD_DIR/ioncube"; exit 1; }
    [ -d $phpModules ] || { echo "[ERR] Folder to place ionCubeLib '$phpModules' not found!"; exit 1; }
    cp -fp $DOWNLOAD_DIR//ioncube/${ioncubeLoaderlib} $IONCUBE_LIB_DIR/${ioncubeLoaderlib}
    ((serviceRestart++))
fi

if [ "$doRevert" -gt 0 ]; then
    [ -f $IONCUBE_LIB_DIR/${ioncubeLoaderlib}.last ] || { echo "[ERR] No Backup-Version Found!"; exit 1; }
    echo "using Backup-Version `ls -al $IONCUBE_LIB_DIR/${ioncubeLoaderlib}.last`"
    cp -fp $IONCUBE_LIB_DIR/${ioncubeLoaderlib}.last $IONCUBE_LIB_DIR/${ioncubeLoaderlib}
    ((serviceRestart++))
fi

if [ "$doUseWizz" -gt 0 ]; then
    [ -f $DOWNLOAD_DIR/ioncube/loader-wizard.php ] || { echo "No Wizzard Found!"; exit 1; }
    cp -fp $DOWNLOAD_DIR/ioncube/loader-wizard.php $wizzardWebFolder
    echo "Wizzard copied to '$wizzardWebFolder'"
fi

if [ "$doRemoveWizz" -gt 0 ]; then
    [ -f $wizzardWebFolder/loader-wizard.php ] || { echo "[ERR] Wizzard wasn't copied to '$wizzardWebFolder'!"; exit 1; }
    rm -f $wizzardWebFolder/loader-wizard.php
    echo "Wizzard removed from '$wizzardWebFolder'"
fi

if [ "$doPatch" -gt 0 ]; then
    if [ ! -f $phpModules/${ioncubeLoaderlib} ] || [ `readlink -f $phpModules/${ioncubeLoaderlib}` != `realpath $IONCUBE_LIB_DIR/${ioncubeLoaderlib}` ]; then
        ln -fs `realpath $IONCUBE_LIB_DIR/${ioncubeLoaderlib}` $phpModules/${ioncubeLoaderlib}
        ((serviceRestart++))
    fi
    if ! grep -q "${ioncubeLoaderlib}" "$phpFpmIniFile"; then
        echo "adding zend_extension /usr/local/lib/php${USED_PHP_VERSION}/modules/${ioncubeLoaderlib} to $phpFpmIniFile"
        sed -i "1 i\zend_extension = /usr/local/lib/php${USED_PHP_VERSION}/modules/${ioncubeLoaderlib}" "$phpFpmIniFile"
        ((serviceRestart++))
    fi
fi

if [ "$doDisablePatch" -gt 0 ]; then
    rm -f $phpModules/${ioncubeLoaderlib}
    if grep -q "${ioncubeLoaderlib}" "$phpFpmIniFile"; then
        echo "removing zend_extension from $phpFpmIniFile"
        grep -v "zend_extension = /usr/local/lib/php${USED_PHP_VERSION}/modules/${ioncubeLoaderlib}" "$phpFpmIniFile" > tmp.fpmini && mv tmp.fpmini "$phpFpmIniFile"
        ((serviceRestart++))
    fi
fi

# Restart service if needed
if [ $serviceRestart -gt 0 ]; then
    echo "Config modified. Restarting PHP-${phpVersionWithDot} service..."
    if [ -x /usr/syno/sbin/synoservice  ]; then
        synoservice --restart pkgctl-PHP${phpVersionWithDot}
    elif [ -x /bin/systemctl  ]; then
        systemctl restart pkgctl-PHP${phpVersionWithDot}
    else
        echo "[ERR] Could not restart PHP-${phpVersionWithDot} service! Please reboot or try to restart manually via Package Center."
        exit 1
    fi
    echo "PHP-${phpVersionWithDot} service restarted."
    retState=$CONFIG_CHANGED_RETURN_STATE
else
    echo "Config untouched."
fi
exit $retState
