; vim:set ts=8 sw=8 noet:
cpu 8086
org 100h

; if non-zero, print all NFS direntries as {...} and prints +/- depending if they were accepted
%define DEBUG_REDIR_DIRLIST 0

; if non-zero, show open/create requests
%define DEBUG_REDIR_OPENCREATE 0

; if non-zero, show read requests
%define DEBUG_REDIR_READ 0

; if non-zero, show write requests
%define DEBUG_REDIR_WRITE 0

; if non-zero, print all INT 2F/AX=11xx function numbers as (xx)
%define REDIR_DEBUG_CALLS 0

; if non-zero, show an indicator if waiting for a reply
%define RPC_SHOW_INDICATOR 1

; 0 = keep case as/is (bad idea), 1 = force uppercase, 2 = force lowercase
%define NFS_CASE 1

%macro pushm 1-*
%rep %0
    push %1
%rotate 1
%endrep
%endmacro

%macro popm 1-*
%rep %0
    pop %1
%rotate 1
%endrep
%endmacro


section .text

        jmp main

%include "net.asm"
%include "rpc.asm"
%include "nfs.asm"
%include "redir.asm"
%include "helper.asm"
%include "print.asm"

%include "main.asm"
