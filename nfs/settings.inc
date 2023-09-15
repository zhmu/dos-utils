; if non-zero, print all NFS direntries as {...} and prints +/- depending if they were accepted
DEBUG_REDIR_DIRLIST equ 0

; if non-zero, show open/create requests
DEBUG_REDIR_OPENCREATE equ 0

; if non-zero, show read requests
DEBUG_REDIR_READ equ 0

; if non-zero, show write requests
DEBUG_REDIR_WRITE equ 0

; if non-zero, print all INT 2F/AX=11xx function numbers as (xx)
REDIR_DEBUG_CALLS equ 0

; if non-zero, show an indicator if waiting for a reply
RPC_SHOW_INDICATOR equ 1

; 0 = keep case as/is (bad idea), 1 = force uppercase, 2 = force lowercase
NFS_CASE equ 1
