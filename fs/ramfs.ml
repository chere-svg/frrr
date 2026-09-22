(* fs/ramfs.ml - OCamlOS RAM Filesystem — full hierarchy *)

let make_child parent node =
  Vfs.add_child parent node; node

let init () =
  (* ── /bin ── *)
  let bin = make_child Vfs.root (Vfs.make_dir "bin") in
  List.iter (fun n -> Vfs.add_child bin (Vfs.make_exec n))
    ["sh"; "ls"; "cat"; "echo"; "pwd"; "ps"; "free";
     "uname"; "uptime"; "ping"; "clear"; "dmesg"; "mount"];

  (* ── /sbin ── *)
  let sbin = make_child Vfs.root (Vfs.make_dir "sbin") in
  List.iter (fun n -> Vfs.add_child sbin (Vfs.make_exec n))
    ["init"; "shutdown"; "reboot"; "fdisk"; "mkfs"; "modprobe"];

  (* ── /usr ── *)
  let usr = make_child Vfs.root (Vfs.make_dir "usr") in
  let usr_bin = make_child usr (Vfs.make_dir "bin") in
  List.iter (fun n -> Vfs.add_child usr_bin (Vfs.make_exec n))
    ["grep"; "sed"; "awk"; "find"; "sort"; "wc"; "head"; "tail"; "diff"];
  let usr_lib = make_child usr (Vfs.make_dir "lib") in
  List.iter (fun n ->
      Vfs.add_child usr_lib (Vfs.make_file n ""))
    ["libc.so"; "libm.so"; "libpthread.so"];
  let usr_share = make_child usr (Vfs.make_dir "share") in
  let usr_share_man = make_child usr_share (Vfs.make_dir "man") in
  Vfs.add_child usr_share_man (Vfs.make_dir "man1");
  Vfs.add_child usr_share_man (Vfs.make_dir "man8");

  (* ── /etc ── *)
  let etc = make_child Vfs.root (Vfs.make_dir "etc") in
  Vfs.add_child etc (Vfs.make_file "hostname"
    "ocamlos\n");
  Vfs.add_child etc (Vfs.make_file "os-release"
    "NAME=\"OCamlOS\"\nVERSION=\"1.0.0\"\nID=ocamlos\nPRETTY_NAME=\"OCamlOS 1.0.0 (Bare-Metal)\"\nHOME_URL=\"https://github.com/ocamlos\"\n");
  Vfs.add_child etc (Vfs.make_file ~perm:Vfs.perm_priv "passwd"
    "root:x:0:0:root:/root:/bin/sh\ndaemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin\n");
  Vfs.add_child etc (Vfs.make_file ~perm:Vfs.perm_priv "shadow"
    "root:*:19000:0:99999:7:::\n");
  Vfs.add_child etc (Vfs.make_file "fstab"
    "# <fs>      <mount>  <type>  <opts>  <dump>  <pass>\ntmpfs       /tmp     tmpfs   defaults  0  0\n");
  Vfs.add_child etc (Vfs.make_file "mtab"
    "rootfs / ramfs rw 0 0\ntmpfs /tmp tmpfs rw 0 0\n");
  let etc_net = make_child etc (Vfs.make_dir "network") in
  Vfs.add_child etc_net (Vfs.make_file "interfaces"
    "auto lo\niface lo inet loopback\n\nauto eth0\niface eth0 inet dhcp\n");

  (* ── /dev ── *)
  let dev = make_child Vfs.root (Vfs.make_dir "dev") in
  List.iter (fun n -> Vfs.add_child dev (Vfs.make_dev n))
    ["tty0"; "tty1"; "ttyS0"; "null"; "zero"; "random"; "urandom";
     "sda"; "sda1"; "mem"; "kmem"; "console"];

  (* ── /proc ── *)
  let proc = make_child Vfs.root (Vfs.make_dir "proc") in
  Vfs.add_child proc (Vfs.make_file "cpuinfo"
    "processor\t: 0\nvendor_id\t: OCamlCPU\ncpu family\t: 6\nmodel name\t: OCamlOS Virtual x86_64\ncpu MHz\t\t: 3200.000\ncache size\t: 8192 KB\nflags\t\t: fpu vme de pse tsc msr pae mce apic sep pge mca cmov\n");
  Vfs.add_child proc (Vfs.make_file "meminfo"
    "MemTotal:       131072 kB\nMemFree:        115072 kB\nMemAvailable:   115072 kB\nBuffers:           512 kB\nCached:           2048 kB\nSwapTotal:           0 kB\nSwapFree:            0 kB\n");
  Vfs.add_child proc (Vfs.make_file "version"
    "OCamlOS version 1.0.0 (ocamlopt 4.14.2) #1 SMP Mon Sep 22 00:00:00 UTC 2026\n");
  Vfs.add_child proc (Vfs.make_file "uptime"
    "42.00 38.00\n");
  Vfs.add_child proc (Vfs.make_file "loadavg"
    "0.01 0.04 0.02 1/32 1\n");
  let proc_net = make_child proc (Vfs.make_dir "net") in
  Vfs.add_child proc_net (Vfs.make_file "dev"
    "Inter-|   Receive                                                |  Transmit\n face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n    lo:       0       0    0    0    0     0          0         0        0       0    0    0    0     0       0          0\n  eth0:    1024      16    0    0    0     0          0         0      512       8    0    0    0     0       0          0\n");

  (* ── /sys ── *)
  let sys = make_child Vfs.root (Vfs.make_dir "sys") in
  let sys_class = make_child sys (Vfs.make_dir "class") in
  let sys_net = make_child sys_class (Vfs.make_dir "net") in
  let sys_eth0 = make_child sys_net (Vfs.make_dir "eth0") in
  Vfs.add_child sys_eth0 (Vfs.make_file "mtu" "1500\n");
  Vfs.add_child sys_eth0 (Vfs.make_file "operstate" "up\n");

  (* ── /home ── *)
  let home = make_child Vfs.root (Vfs.make_dir "home") in
  let home_user = make_child home (Vfs.make_dir "user") in
  Vfs.add_child home_user (Vfs.make_file ".bashrc"
    "# ~/.bashrc\nexport PATH=/bin:/sbin:/usr/bin\nexport PS1='user@ocamlos:~$ '\nalias ll='ls -l'\n");
  Vfs.add_child home_user (Vfs.make_file ".profile"
    "# ~/.profile\n[ -f ~/.bashrc ] && . ~/.bashrc\n");

  (* ── /root ── *)
  let root_home = make_child Vfs.root (Vfs.make_dir "root") in
  Vfs.add_child root_home (Vfs.make_file ".bashrc"
    "# root's ~/.bashrc\nexport PATH=/bin:/sbin:/usr/bin:/usr/sbin\nexport PS1='root@ocamlos:~# '\nalias ll='ls -la'\n");
  Vfs.add_child root_home (Vfs.make_file "README"
    "Welcome to OCamlOS!\nThis is a bare-metal OS written in pure OCaml.\nType 'help' in the shell for available commands.\n");

  (* ── /tmp ── *)
  let _tmp = make_child Vfs.root (Vfs.make_dir "tmp") in

  (* ── /var ── *)
  let var = make_child Vfs.root (Vfs.make_dir "var") in
  let var_log = make_child var (Vfs.make_dir "log") in
  Vfs.add_child var_log (Vfs.make_file "kern.log"
    "Sep 22 00:00:00 ocamlos kernel: OCamlOS 1.0.0 starting up...\nSep 22 00:00:00 ocamlos kernel: CPU: x86_64, 3200 MHz\nSep 22 00:00:00 ocamlos kernel: Memory: 128 MB available\nSep 22 00:00:00 ocamlos kernel: VGA: 80x25 text mode initialized\nSep 22 00:00:00 ocamlos kernel: UART: COM1 @ 0x3F8, 38400 baud\nSep 22 00:00:00 ocamlos kernel: RamFS: mounted at /\nSep 22 00:00:00 ocamlos kernel: Network: eth0 initialized (10.0.2.15)\nSep 22 00:00:00 ocamlos kernel: All subsystems OK. Starting shell.\n");
  Vfs.add_child var_log (Vfs.make_file "syslog" "");
  let var_run = make_child var (Vfs.make_dir "run") in
  Vfs.add_child var_run (Vfs.make_file "utmp" "");

  (* ── /mnt ── *)
  let _mnt = make_child Vfs.root (Vfs.make_dir "mnt") in

  (* ── /lib ── *)
  let lib = make_child Vfs.root (Vfs.make_dir "lib") in
  List.iter (fun n -> Vfs.add_child lib (Vfs.make_file n ""))
    ["libc.so.6"; "libm.so.6"; "ld-linux-x86-64.so.2"]
