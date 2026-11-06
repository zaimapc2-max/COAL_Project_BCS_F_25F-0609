@echo off
nasm -f bin src\mario.asm -o MARIO.COM
if errorlevel 1 (echo BUILD FAILED) else (echo BUILD OK)