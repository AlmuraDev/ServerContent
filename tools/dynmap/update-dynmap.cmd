@echo off
rem Regenerates Dynmap's Almura render data from the content loader assets and installs it into a server's dynmap folder.
rem Usage: update-dynmap.cmd [dynmap folder]      (default: the dev server, x:\spongesrv\dynmap)
rem Run it after adding or changing blocks, block models or block textures, then /dynmap fullrender each world (or radiusrender to check).

setlocal
set JAVA=C:\Program Files\Java\jdk1.8.0_361\bin
set CONTENT=h:\almura 3.0\contentloader\3.0\fs_2\assets\almura
rem Vanilla parent models and textures come from the 1.12.2 client jar (BlueMap keeps a copy on the dev server)
set CLIENTJAR=x:\spongesrv\bluemap\minecraft-client-1.12.2.jar
set DYNMAP=%~1
if "%DYNMAP%"=="" set DYNMAP=x:\spongesrv\dynmap
set HERE=%~dp0

if not exist "%DYNMAP%\renderdata" (
    echo %DYNMAP% is not a dynmap folder.
    exit /b 1
)

echo Building the generator...
if not exist "%HERE%build" mkdir "%HERE%build"
"%JAVA%\javac" -nowarn -cp "%HERE%gson-2.8.0.jar" -d "%HERE%build" "%HERE%DynmapGen.java" || exit /b 1

echo Generating from %CONTENT%...
if exist "%HERE%out" rmdir /s /q "%HERE%out"
mkdir "%HERE%out"
"%JAVA%\java" -cp "%HERE%gson-2.8.0.jar;%HERE%build" DynmapGen "%CONTENT%" "%CLIENTJAR%" "%HERE%out" || exit /b 1

echo Installing into %DYNMAP%...
copy /y "%HERE%out\almura-models.txt" "%DYNMAP%\renderdata\" >nul || exit /b 1
copy /y "%HERE%out\almura-texture.txt" "%DYNMAP%\renderdata\" >nul || exit /b 1
robocopy "%HERE%out\pack" "%DYNMAP%\texturepacks\almura" /MIR /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 (
    echo Copying the texture pack failed.
    exit /b 1
)

echo Done. Restart the server (Dynmap reads these at startup), then /dynmap fullrender each world.
endlocal
