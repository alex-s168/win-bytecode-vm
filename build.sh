: ${NASM:="nasm"}
: ${CC:="tcc"}

$NASM -felf32 main.asm -o main.o
$NASM -fbin test.asm -o test
$CC -m32 main.o -o main

