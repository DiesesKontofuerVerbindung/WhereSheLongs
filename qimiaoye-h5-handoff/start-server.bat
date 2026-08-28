@echo off
setlocal
cd /d "%~dp0"
echo Qimiaoye H5 server: http://localhost:8080/
echo Press Ctrl+C to stop the server.
python -m http.server 8080
endlocal
