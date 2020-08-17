@echo off
echo Do you wish to continue with local project content repo update? (everything)  Close if no....
echo.
pause
cls
echo Purging local project content repo directory...
c:
cd\
rmdir "c:\projects\almura\run\assets\fs_4\assets\almura" /s /q
cls
echo Updating local project content repo...
mkdir "c:\projects\almura\run\assets\fs_4\assets\almura"

xcopy "h:\almura 3.0\contentloader\3.0\fs_2\assets\almura" "c:\projects\almura\run\assets\fs_4\assets\almura\" /Q /S
echo Update complete.  Exiting...
pause