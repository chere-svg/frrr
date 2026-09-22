(* kernel/kmain.ml — OCamlOS Terminal Kernel Entry Point *)

(* ── Hardware FFI ── *)
external has_input    : unit   -> bool  = "caml_has_input"
external get_input    : unit   -> int   = "caml_get_input"
external poll_hardware : unit  -> unit  = "caml_poll_hardware"
external cpu_halt     : unit   -> unit  = "caml_cpu_halt"
external serial_write : string -> unit  = "caml_serial_write"
external vga_print    : string -> unit  = "caml_vga_print"
external vga_clear    : unit   -> unit  = "caml_vga_clear"

(* Unified terminal output helper: writes to both Serial and ANSI-aware VGA *)
let term_write s =
  serial_write s;
  vga_print s

(* ════════════════════════════════════════════════════════════════
   Boot Banner and Login Sequence
   ════════════════════════════════════════════════════════════════ *)

let boot_banner () =
  let banner =
    "\027[1;92m\n" ^
    "   ___  ____            _  ___  ____\n" ^
    "  / _ \\/ ___|__ _ _ __ | |/ _ \\/ ___|\n" ^
    " | | | \\___ / _` | '_ \\| | | | \\___ \\\n" ^
    " | |_| |___| (_| | | | | | |_| |___) |\n" ^
    "  \\___/|____\\__,_|_| |_|_|\\___/|____/\n" ^
    "\027[0m" ^
    "\027[96m  Bare-Metal OS in Pure OCaml  |  x86_64\n\027[0m" ^
    "\027[2m  Kernel 1.0.0  |  OCaml 4.14.2  |  128 MB RAM\n\027[0m\n"
  in
  term_write banner

let login_prompt () =
  let msg =
    "\027[1;92mocamlos\027[0m login: root\n" ^
    "Password: \n\n" ^
    "Last login: Mon Sep 22 00:00:00 UTC 2026 on tty1\n\n"
  in
  term_write msg

(* ════════════════════════════════════════════════════════════════
   Interactive Line Editor State
   ════════════════════════════════════════════════════════════════ *)

type editor = {
  mutable buf        : bytes;
  mutable len        : int;
  mutable cursor     : int;
  mutable tab_prefix : string;
  mutable tab_matches: string list;
  mutable tab_idx    : int;
}

let editor_max = 1024

let make_editor () = {
  buf         = Bytes.make editor_max ' ';
  len         = 0;
  cursor      = 0;
  tab_prefix  = "";
  tab_matches = [];
  tab_idx     = 0;
}

let editor_contents e =
  Bytes.sub_string e.buf 0 e.len

let editor_insert e ch =
  if e.len < editor_max - 1 then begin
    Bytes.blit e.buf e.cursor e.buf (e.cursor + 1) (e.len - e.cursor);
    Bytes.set e.buf e.cursor ch;
    e.len    <- e.len + 1;
    e.cursor <- e.cursor + 1
  end

let editor_backspace e =
  if e.cursor > 0 then begin
    Bytes.blit e.buf e.cursor e.buf (e.cursor - 1) (e.len - e.cursor);
    e.len    <- e.len - 1;
    e.cursor <- e.cursor - 1
  end

let editor_delete e =
  if e.cursor < e.len then begin
    Bytes.blit e.buf (e.cursor + 1) e.buf e.cursor (e.len - e.cursor - 1);
    e.len <- e.len - 1
  end

let editor_clear e =
  e.len    <- 0;
  e.cursor <- 0

(* Redraw the current line cleanly in place on both displays *)
let redraw_line e =
  let contents = editor_contents e in
  let line_str = "\r\027[2K" ^ Shell.prompt_str () ^ contents in
  term_write line_str;
  let right_of_cursor = e.len - e.cursor in
  if right_of_cursor > 0 then begin
    let back_str = "\027[" ^ string_of_int right_of_cursor ^ "D" in
    term_write back_str
  end

(* ════════════════════════════════════════════════════════════════
   Subsystem Initialization
   ════════════════════════════════════════════════════════════════ *)

let init_subsystems () =
  Baremetal_runtime.initialize_runtime ();
  let _f1 = Pmm.alloc_frame () in
  let _f2 = Pmm.alloc_frame () in
  let kspace = Vmm.create_kernel_space () in
  let _ = Heap.alloc 4096 in
  let _ = Pci.scan_bus () in
  let dummy () = () in
  let p1 = Process.create dummy kspace.Vmm.p4_addr in
  let p2 = Process.create dummy kspace.Vmm.p4_addr in
  Scheduler.add_process p1;
  Scheduler.add_process p2;
  Scheduler.schedule ();
  Ramfs.init ();
  let sock = Socket.create Socket.Stream in
  Socket.bind sock 80;
  Arp.update 0x0A000202l "\x52\x54\x00\x12\x34\x56";
  let conn = Tcp.create_conn 80 8080 in
  conn.Tcp.state <- Tcp.Established

(* ════════════════════════════════════════════════════════════════
   Interactive Shell Loop
   ════════════════════════════════════════════════════════════════ *)

let terminal_loop () =
  let ed = make_editor () in
  let uptime_tick = ref 0 in

  (* Display initial prompt *)
  Shell.prompt ();

  let rec loop () =
    poll_hardware ();

    if has_input () then begin
      let key = get_input () in
      ed.tab_matches <- [];

      (match key with

      (* ── Enter / Return ── *)
      | 10 | 13 ->
        let line = editor_contents ed in
        term_write "\n";
        editor_clear ed;
        ed.tab_matches <- [];
        let result = Shell.execute_line line in
        (match result with
         | Shell.Text s when s <> "" ->
           term_write s
         | Shell.Exit _ -> ()
         | _ -> ());
        Shell.prompt ();

      (* ── Backspace ── *)
      | 8 | 127 ->
        if ed.cursor > 0 then begin
          editor_backspace ed;
          redraw_line ed;
        end

      (* ── Ctrl+C ── *)
      | 3 ->
        term_write "^C\n";
        editor_clear ed;
        Shell.prompt ();

      (* ── Ctrl+D ── *)
      | 4 ->
        if ed.len = 0 then begin
          term_write "\nlogout\n";
          Shell.prompt ();
        end else begin
          editor_delete ed;
          redraw_line ed;
        end

      (* ── Ctrl+L / clear screen ── *)
      | 12 ->
        term_write "\027[2J\027[H";
        redraw_line ed;

      (* ── Tab Auto-Completion ── *)
      | 9 ->
        let line = editor_contents ed in
        let tokens = String.split_on_char ' ' line in
        let last   = match List.rev (List.filter (fun s -> s <> "") tokens) with
          | []    -> ""
          | t :: _ -> t
        in
        if ed.tab_matches = [] then begin
          ed.tab_prefix  <- last;
          ed.tab_matches <- Shell.complete_word last;
          ed.tab_idx     <- 0
        end;
        (match ed.tab_matches with
         | [] ->
           term_write "\007" (* Bell: no match *)
         | [single] ->
           let prefix_end = String.length line - String.length last in
           let new_line = String.sub line 0 prefix_end ^ single ^ " " in
           editor_clear ed;
           String.iter (fun c -> editor_insert ed c) new_line;
           redraw_line ed;
           ed.tab_matches <- []
         | matches ->
           let m = List.nth matches (ed.tab_idx mod List.length matches) in
           ed.tab_idx <- ed.tab_idx + 1;
           let prefix_end = String.length line - String.length last in
           let new_line = String.sub line 0 prefix_end ^ m in
           editor_clear ed;
           String.iter (fun c -> editor_insert ed c) new_line;
           redraw_line ed)

      (* ── Arrow Up: Command History Previous ── *)
      | 1001 ->
        let h = Shell.history_prev () in
        editor_clear ed;
        String.iter (fun c -> editor_insert ed c) h;
        redraw_line ed;

      (* ── Arrow Down: Command History Next ── *)
      | 1002 ->
        let h = Shell.history_next () in
        editor_clear ed;
        String.iter (fun c -> editor_insert ed c) h;
        redraw_line ed;

      (* ── Arrow Left ── *)
      | 1003 ->
        if ed.cursor > 0 then begin
          ed.cursor <- ed.cursor - 1;
          term_write "\027[D"
        end

      (* ── Arrow Right ── *)
      | 1004 ->
        if ed.cursor < ed.len then begin
          ed.cursor <- ed.cursor + 1;
          term_write "\027[C"
        end

      (* ── Home (Ctrl+A = 1) ── *)
      | 1 | 1005 ->
        let steps = ed.cursor in
        ed.cursor <- 0;
        if steps > 0 then
          term_write ("\027[" ^ string_of_int steps ^ "D")

      (* ── End (Ctrl+E = 5) ── *)
      | 5 | 1006 ->
        let steps = ed.len - ed.cursor in
        ed.cursor <- ed.len;
        if steps > 0 then
          term_write ("\027[" ^ string_of_int steps ^ "C")

      (* ── Delete Key ── *)
      | 1007 ->
        editor_delete ed;
        redraw_line ed;

      (* ── Printable Characters ── *)
      | k when k >= 32 && k <= 126 ->
        let ch = Char.chr k in
        editor_insert ed ch;
        if ed.cursor = ed.len then begin
          term_write (String.make 1 ch)
        end else begin
          redraw_line ed
        end

      | _ -> ())

    end else begin
      cpu_halt ();
    end;

    incr uptime_tick;
    if !uptime_tick mod 10000 = 0 then
      Shell.uptime_s := !(Shell.uptime_s) + 1;

    loop ()
  in
  loop ()

(* ════════════════════════════════════════════════════════════════
   Kernel Main Entry Point
   ════════════════════════════════════════════════════════════════ *)

let kmain () =
  init_subsystems ();
  vga_clear ();
  boot_banner ();
  login_prompt ();
  terminal_loop ()

let () = kmain ()
