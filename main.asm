; bytecode vm for x86 (32 bit) cdecl libc (windows)
;
; file `out` always gets cleared at start
;
; ## registers
; there are at least 256 byte sized registers.
; most operations (arithm, comp, ...) operate on pairs of registers (to form a word)
;
; ## format
; [opcode: 1B] [arg0: 1B] [arg1: 1B]
;
; ## operations
; | ';' C   | indicates end of file; required!; C = exit code |
; | 'E' C   | exits the program; C = exit code |
; | 'I' R V | immediate into reg (1B) R value V |
; | '@' R   | output ascii char in reg R (1B) |
; | '?' R   | reads ascii char into reg R (1B) |
; | 'G' A B | jump to addr immediate A (low), B (high) |
; | 'C' R D | jump to addr D (low), 0 (high) IF value in register (2B) R is zero |
; | 'A' D S | (2B) D = (2B) D + (2B) S |
; | 'S' D S | (2B) D = (2B) D - (2B) S |
; | 'L' D S | (2B) D = (2B) D << (2B) S |
; | 'R' D S | (2B) D = (2B) D >> (2B) S |
; | 'N' D S | (2B) D = ~((2B) D & (2B) S) |
; | 'M' D S | (1B) D = (1B) S |
; | 'Z' D S | (2B) D = (1B) S ; zero extend source (source is low, 0 is high) |
; | '>' S   | reads file `in` into the data buffer and stores the amount of read bytes into register (2B) S |
; | `<` R   | appends value in register (1B) R into file `out` |
; | '=' O I | reads value in data buffer at pos [ value in reg (2B) I ] into register (1B) O |

  bits 32
  global main
  extern fopen
  extern fclose
  extern fread
  extern printf
  extern putchar
  extern fputc
  extern getchar
  extern exit

  section .text

;==========
main:
init_prog:
  push mode_write
  push outfile
  call fopen
  add esp, 8
  mov ebx, err_open
  test eax, eax
  jz error
  mov [prog_outf], eax

  push eax
  call fclose
  add esp, 4
;==========

;==========
read_prog:
  mov esi, file
  mov edi, prog_buf
  push dword prog_buf_len
  call read_file_into
  ; read bytes in eax
;==========

;==========
exec:
  movzx esi, word [prog_counter]

  movzx edi, byte [prog_buf + esi] ; opcode

  inc esi
  mov ax, [prog_buf + esi] ; (arg0, arg1)

  sub edi, ';'
  mov edi, [exec_lut + edi * 4]

  mov ebx, err_instr
  test edi, edi
  jz error

  mov bx, ax
  jmp edi
;==========

;======================
;======================

;==========
exitproc:
  ; close file
  push dword [prog_outf]
  call fclose
  add esp, 4

  push eax
  call exit

.loop:
  jmp .loop
;==========

;==========
; esi - file name
; edi - buffer ptr
; stack (dword) - buffer size
;rets 
; eax - read bytes
read_file_into:
  push ebx
  push ecx

  ; open file
  push mode_read
  push esi
  call fopen
  add esp, 8
  mov ebx, err_open
  test eax, eax
  jz error
  ; file handle in eax

  pop ecx ; buf size
  push eax

  ; read file
  push eax
  push dword 1
  push ecx
  push edi
  call fread
  add esp, 16
  mov ebx, eax

  ; handle on stack
  call fclose

  mov eax, ebx

  pop ecx
  pop ebx

  ret
;==========

;==========
error: ; ebx = error string 0 terminated
  push ebx
  call printf
  add esp, 4

  mov eax, 1
  jmp exitproc
;==========

;==========
exec_op_exit: ; bl = exit code; bh =
  movzx eax, bl
  jmp exitproc
;==========

;==========
inc_pc:
  add word [prog_counter], 3
  jmp exec
;==========

;==========
exec_op_imm: ; bl = reg; bh = value
  movzx edi, bl

  mov [prog_regs + edi], bh
  jmp inc_pc
;==========

;==========
exec_op_out: ; bl = reg; bh =
  movzx esi, bl

  movzx edi, byte [prog_regs + esi]
  push edi
  call putchar
  add esp, 4

  jmp inc_pc
;==========

;==========
exec_op_in: ; bl = reg; bh =
  call getchar

  movzx edi, bl
  mov [prog_regs + edi], al

  jmp inc_pc
;==========

;==========
exec_op_goto: ; bx = pc
  mov [prog_counter], bx
  jmp exec
;==========

;==========
exec_op_cond: ; bl = test reg; bh = zp address
  movzx esi, bl

  cmp word [prog_regs + esi], 0
  jne inc_pc

  mov bl, bh
  mov bh, 0
  mov [prog_counter], bx

  jmp exec
;==========

;==========
dyadic_args:
  movzx esi, bl
  mov ax, [prog_regs + esi]
  movzx edi, bh
  mov cx, [prog_regs + edi]
  ret
;==========

;==========
dyadic_post:
  movzx edi, bl
  mov [prog_regs + edi], ax

  jmp inc_pc
;==========

;==========
exec_op_add: ; bl = dest & src1; bh = src2
  call dyadic_args
  add ax, cx
  jmp dyadic_post
;==========

;==========
exec_op_sub: ; bl = dest & src1; bh = src2
  call dyadic_args
  sub ax, cx
  jmp dyadic_post
;==========

;==========
exec_op_lshift: ; bl = dest & src1; bh = src2
  call dyadic_args
  shl ax, cl
  jmp dyadic_post
;==========

;==========
exec_op_rshift: ; bl = dest & src1; bh = src2
  call dyadic_args
  shr ax, cl
  jmp dyadic_post
;==========

;==========
exec_op_bwnand: ; bl = dest & src1; bh = src2
  call dyadic_args
  and ax, cx
  not ax
  jmp dyadic_post
;==========

;==========
exec_op_mov: ; bl = dest; bh = src
  movzx esi, bh
  mov al, [prog_regs + esi]
  movzx edi, bl
  mov [prog_regs + edi], al

  jmp inc_pc
;==========

;==========
exec_op_zext: ; bl = dest; bh = src
  movzx esi, bh
  mov al, [prog_regs + esi]
  mov ah, 0

  movzx edi, bl
  mov [prog_regs + edi], ax

  jmp inc_pc
;==========

;==========
exec_op_append: ; bl = char reg
  movzx ebx, bl
  push dword [prog_outf]
  push ebx
  call fputc
  add esp, 8

  jmp inc_pc
;==========

;==========
exec_op_read: ; bl = amount of bytes out reg
  push bx

  mov esi, infile
  mov edi, prog_readr
  push dword prog_readr_len
  call read_file_into
  ; read bytes in eax

  pop bx
  movzx edi, bl
  mov [prog_regs +edi], ax

  jmp inc_pc
;==========

;==========
exec_op_index: ; bl = out reg; bh = index reg
  movzx esi, bh
  movzx esi, word [prog_regs + esi]
  mov al, [prog_readr + esi]
  movzx edi, bl
  mov [prog_regs + edi], al

  jmp inc_pc
;==========

;=======================================
;==                DATA               ==
;=======================================
  section .data

;==========
file:
  db "test.bin", 0
outfile:
  db "out", 0
infile:
  db "in", 0
;==========

;==========
mode_write:
  db "w", 0
mode_read:
  db "r", 0
;==========

;==========
err_open:
  db "could not open file", 10, 0
err_read:
  db "could not read file", 10, 0
err_instr:
  db "instr not found", 10, 0
;==========

;==========
exec_lut: ; usage: index opcode - ';'
  dd exec_op_exit   ; ';'
  dd exec_op_append ; '<'
  dd exec_op_index  ; '='
  dd exec_op_read   ; '>'
  dd exec_op_in     ; '?'
  dd exec_op_out    ; '@'
  dd exec_op_add    ; 'A'
  dd 0              ; 'B'
  dd exec_op_cond   ; 'C'
  dd 0              ; 'D'
  dd exec_op_exit   ; 'E'
  dd 0              ; 'F'
  dd exec_op_goto   ; 'G'
  dd 0              ; 'H'
  dd exec_op_imm    ; 'I'
  dd 0              ; 'J'
  dd 0              ; 'K'
  dd exec_op_lshift ; 'L'
  dd exec_op_mov    ; 'M'
  dd exec_op_bwnand ; 'N'
  dd 0              ; 'O'
  dd 0              ; 'P'
  dd 0              ; 'Q'
  dd exec_op_rshift ; 'R'
  dd exec_op_sub    ; 'S'
  dd 0              ; 'T'
  dd 0              ; 'U'
  dd 0              ; 'V'
  dd 0              ; 'W'
  dd 0              ; 'X'
  dd 0              ; 'Y'
  dd exec_op_zext   ; 'Z'
;==========

;==========
buf_byte:
  db 0
;==========

;==========
prog_counter:
  dw 0
prog_regs:
  times 256 db 0
prog_outf:
  dd 0
prog_buf: ; can be extended to any word indexable len
  times 512 db 0
prog_buf_len: equ $-prog_buf
prog_readr: ; can be extended to any word indexable len
  times 512 db 0
prog_readr_len: equ $-prog_readr
;==========
