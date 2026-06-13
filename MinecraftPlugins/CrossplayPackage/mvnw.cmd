@echo off
setlocal

set MAVEN_VERSION=3.9.6
set MAVEN_DIR=%~dp0.mvn\wrapper\apache-maven-%MAVEN_VERSION%
set MAVEN_ZIP=%TEMP%\apache-maven-%MAVEN_VERSION%-bin.zip
set MAVEN_URL=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/%MAVEN_VERSION%/apache-maven-%MAVEN_VERSION%-bin.zip

if not exist "%MAVEN_DIR%\bin\mvn.cmd" (
    echo Maven not found. Downloading Apache Maven %MAVEN_VERSION%...
    powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%MAVEN_URL%' -OutFile '%MAVEN_ZIP%'"
    if errorlevel 1 ( echo ERROR: Download failed. Check your internet connection. & exit /b 1 )
    powershell -NoProfile -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; [IO.Compression.ZipFile]::ExtractToDirectory('%MAVEN_ZIP%', '%~dp0.mvn\wrapper')"
    if errorlevel 1 ( echo ERROR: Extraction failed. & exit /b 1 )
    del "%MAVEN_ZIP%" 2>nul
    echo Maven %MAVEN_VERSION% ready.
)

"%MAVEN_DIR%\bin\mvn.cmd" %*
endlocal
