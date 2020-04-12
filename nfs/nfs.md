# NFSv3 client for DOS

Allow you to conveniently use a NFSv3 server from your DOS machine.

# Features

- NFSv3 based file sharing
- Uses the network redirector API, so you'll get a drive letter for the NFS share
- Uses only 8086/8088 instructions
- Automatically hides entries that do not conform to 8.3 DOS filename convention
- Fits in roughly 11KB base memory while resident
- Supports DHCP or fixed IP address
- Supports ICMP echo/response

## Building
Simply run ``build.sh`` - you need to have nasm and mtools installed.

The output is a 1.44MB floppy disk image, ``floppy.img``, which contains a ``n.com`` which is the NFS client.

## Usage

Basic use is ``n.com server_ip:path`` to mount nfs://server_ip/path to the first available drive letter. Only IP adresses are supported for the server name!

Supported arguments:
- /? or /h - show help
- /p:xx - use XX as packet driver interrupt (default: detect)
- /ip:x.x.x.x - use x.x.x.x as the IPv4 address (default: DHCP)

## Options
The source code has some knobs you can tweak, with their current defaults:

- RPC_SHOW_INDICATOR (=1): if non-zero, show a 'N' in the top-right corner while active
- NFS_CASE (=1): controls the expected case on the server. 1 = uppercase, 2 = lowercase, 0 = any case

Note that DOS tends to uppercase/lowercase requests as it pleases, using NFS_CASE=0 is a bad idea.

And a lot of flags used while developing:

- DEBUG_REDIR_DIRLIST (=0): if non-zero, logs NFS readdir entries and whether they are accepted or not to the console
- DEBUG_REDIR_DIRLIST (=0): if non-zero, logs NFS open/create requests/results to the console
- DEBUG_REDIR_READ (=0): if non-zero, logs NFS read requests/results to the console
- DEBUG_REDIR_WRITE (=0): if non-zero, logs NFS write requests/results to the console
- REDIR_DEBUG_CALLS (=0): if non-zero, logs INT 2F redir command numbers to the console

## Source code organisation
``nfspkt.asm`` is the assembler input file with all options which includes most of the other files. Files that end with a 2 (like net2.asm) are never resident in memory.

## Caveats / TODO

- UDP fragmentation is not supported
- Server and client must be in the same subnet (no gateway support)
- Retries need to be implemented
- Still some bugs left (some functions don't return the exact same result as DOS expects)
- User ID/group ID can't be changed
- Swapping to EMS/XMS
- DNS is not supported
- Lack of proper input validation (use only on trusted networks)
- Not all redir commands are implemented
