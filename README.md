# syno-PHPIonCube
 * Tool to use the [ionCubeLoader](https://www.ioncube.com/) on a synology
 * Downloads the latest ionCubeLoader and install it by patching the php-fpm.ini in appstore

## available Options
 * -d  --download  
 Download and use the latest ionCube
 * -r or --revertToLastDownload  
 Revert the used Version to the latest downloaded Version
 * -dp or --disablePatch  
 Remove the Patch
 * -uw or --useWizzard [web-folder]  
 Move the ionCube - Loader-Wizzard to a [web-folder]
 * -rw or --removeWizzard [web-folder]  
 Remove the ionCube - Loader-Wizzard from a [web-folder]

## available Config via ENV
 * IONCUBE_PHP_VERSION  
 set the PHP-Version which should use ionCubeLoader, default 74
 * IONCUBE_RETURN_STATE_IF_CHANGED  
 set the shell-return-state if the config was changed, default 3
 * [ENV-Vars from autoUpdate-Template V 1.0.0](https://github.com/joe128/autoupdateBashScript/blob/v1.0.0/README.md)
