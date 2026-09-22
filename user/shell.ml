(* user/shell.ml — OCamlOS Comprehensive Linux Terminal Shell *)

(* ════════════════════════════════════════════════════════════════
   ANSI / VGA output helpers
   ════════════════════════════════════════════════════════════════ *)

let csi_reset    = "\027[0m"
let csi_bold     = "\027[1m"
let csi_dim      = "\027[2m"
let csi_green    = "\027[32m"
let csi_lgreen   = "\027[92m"
let csi_cyan     = "\027[36m"
let csi_lcyan    = "\027[96m"
let csi_yellow   = "\027[33m"
let csi_lyellow  = "\027[93m"
let csi_blue     = "\027[34;1m"
let csi_lblue    = "\027[94m"
let csi_red      = "\027[31m"
let csi_lred     = "\027[91m"
let csi_magenta  = "\027[35m"
let csi_white    = "\027[37m"
let csi_lwhite   = "\027[97m"
let csi_cl_line  = "\027[2K\r"
let csi_clear    = "\027[2J\027[H"
let csi_save     = "\027[s"
let csi_restore  = "\027[u"

(* Dual-write: serial and VGA *)
external serial_write   : string -> unit = "caml_serial_write"
external vga_print      : string -> unit = "caml_vga_print"
external cpu_halt       : unit   -> unit = "caml_cpu_halt"
external caml_reboot    : unit   -> unit = "caml_reboot"
external caml_poweroff  : unit   -> unit = "caml_poweroff"

let write s =
  serial_write s;
  vga_print s

let writeln s = write (s ^ "\n")

(* ════════════════════════════════════════════════════════════════
   State
   ════════════════════════════════════════════════════════════════ *)

let hostname  = ref "ocamlos"
let username  = ref "root"
let cwd       = ref "/"
let oldpwd    = ref "/"
let uptime_s  = ref 0  (* incremented by main loop *)

(* Environment variables *)
let env_vars : (string * string ref) list =
  [ "USER",  ref "root"
  ; "HOME",  ref "/root"
  ; "SHELL", ref "/bin/sh"
  ; "PATH",  ref "/bin:/sbin:/usr/bin:/usr/sbin"
  ; "TERM",  ref "vt100"
  ; "LANG",  ref "en_US.UTF-8"
  ]

let getenv k =
  match List.assoc_opt k env_vars with
  | Some r -> !r
  | None   -> ""

let setenv k v =
  match List.assoc_opt k env_vars with
  | Some r -> r := v
  | None   -> ()

(* Command history ring buffer *)
let history : string array = Array.make 200 ""
let hist_len  = ref 0
let hist_pos  = ref 0  (* browsing position *)

let history_add line =
  if line <> "" && ((!hist_len = 0) || history.((!hist_len - 1) mod 200) <> line) then begin
    history.(!hist_len mod 200) <- line;
    incr hist_len;
    hist_pos := !hist_len
  end

let history_prev () =
  if !hist_pos > 0 then begin
    decr hist_pos;
    history.(!hist_pos mod 200)
  end else if !hist_len > 0 then
    history.(0)
  else ""

let history_next () =
  if !hist_pos < !hist_len then begin
    incr hist_pos;
    if !hist_pos = !hist_len then "" else history.(!hist_pos mod 200)
  end else ""

(* Aliases *)
let aliases : (string * string) list ref = ref
  [ "ll",    "ls -la"
  ; "la",    "ls -a"
  ; "l",     "ls -lh"
  ; "...",   "cd ../.."
  ; "cls",   "clear"
  ; "quit",  "exit"
  ; "bye",   "exit"
  ]

(* ════════════════════════════════════════════════════════════════
   Path / string helpers
   ════════════════════════════════════════════════════════════════ *)

let pad_right s n =
  let l = String.length s in
  if l >= n then String.sub s 0 n
  else s ^ String.make (n - l) ' '

let pad_left s n =
  let l = String.length s in
  if l >= n then String.sub s 0 n
  else String.make (n - l) ' ' ^ s

let path_join base seg =
  if seg = "" then base
  else if seg.[0] = '/' then seg
  else if base = "/" then "/" ^ seg
  else base ^ "/" ^ seg

let canonicalize path =
  let parts = List.filter (fun s -> s <> "" && s <> ".")
               (String.split_on_char '/' path) in
  let rec resolve acc = function
    | []          -> acc
    | ".." :: rest -> resolve (match acc with [] -> [] | _ :: t -> t) rest
    | seg  :: rest -> resolve (seg :: acc) rest
  in
  match List.rev (resolve [] parts) with
  | []    -> "/"
  | parts -> "/" ^ String.concat "/" parts

let expand_tilde path =
  if path = "~" then getenv "HOME"
  else if String.length path >= 2 && path.[0] = '~' && path.[1] = '/' then
    getenv "HOME" ^ String.sub path 1 (String.length path - 1)
  else path

let expand_vars s =
  let buf = Buffer.create (String.length s) in
  let i = ref 0 in
  let len = String.length s in
  while !i < len do
    if s.[!i] = '$' && !i + 1 < len then begin
      incr i;
      let j = ref !i in
      while !j < len && (s.[!j] = '_' || (s.[!j] >= 'A' && s.[!j] <= 'Z')
                         || (s.[!j] >= 'a' && s.[!j] <= 'z')
                         || (s.[!j] >= '0' && s.[!j] <= '9')) do
        incr j
      done;
      let name = String.sub s !i (!j - !i) in
      (match name with
       | "PWD"  -> Buffer.add_string buf !cwd
       | "OLDPWD" -> Buffer.add_string buf !oldpwd
       | k      -> Buffer.add_string buf (getenv k));
      i := !j
    end else begin
      Buffer.add_char buf s.[!i];
      incr i
    end
  done;
  Buffer.contents buf

let resolve_path p =
  let p = expand_tilde (expand_vars p) in
  if p = "-" then !oldpwd
  else canonicalize (path_join !cwd p)

(* human-readable sizes *)
let human_size n =
  if n < 1024 then string_of_int n ^ "B"
  else if n < 1024*1024 then string_of_int (n/1024) ^ "K"
  else string_of_int (n/(1024*1024)) ^ "M"

(* uptime string *)
let fmt_uptime () =
  let s = !uptime_s in
  let h = s / 3600 in
  let m = (s mod 3600) / 60 in
  let sec = s mod 60 in
  if h > 0 then Printf.sprintf "%dh %02dm %02ds" h m sec
  else Printf.sprintf "%dm %02ds" m sec

(* ════════════════════════════════════════════════════════════════
   Node colorization
   ════════════════════════════════════════════════════════════════ *)

let node_color n =
  match n.Vfs.node_type with
  | Vfs.Directory -> csi_lblue ^ csi_bold
  | Vfs.Device    -> csi_lyellow
  | Vfs.Symlink   -> csi_lcyan
  | Vfs.File      ->
    if n.Vfs.perm.Vfs.owner_x then csi_lgreen
    else csi_lwhite

let node_vga_color n =
  match n.Vfs.node_type with
  | Vfs.Directory -> Vga.color_dir
  | Vfs.Device    -> Vga.color_dev
  | Vfs.Symlink   -> Vga.color_link
  | Vfs.File      ->
    if n.Vfs.perm.Vfs.owner_x then Vga.color_exec else Vga.color_normal

(* ════════════════════════════════════════════════════════════════
   Tokeniser (handles single/double quotes, $var expansion)
   ════════════════════════════════════════════════════════════════ *)

let tokenize line =
  let line = expand_vars line in
  let parts = ref [] in
  let cur   = Buffer.create 32 in
  let i     = ref 0 in
  let len   = String.length line in
  while !i < len do
    match line.[!i] with
    | ' ' | '\t' ->
      if Buffer.length cur > 0 then begin
        parts := Buffer.contents cur :: !parts;
        Buffer.clear cur
      end;
      incr i
    | '\'' ->
      incr i;
      while !i < len && line.[!i] <> '\'' do
        Buffer.add_char cur line.[!i];
        incr i
      done;
      if !i < len then incr i
    | '"' ->
      incr i;
      while !i < len && line.[!i] <> '"' do
        Buffer.add_char cur line.[!i];
        incr i
      done;
      if !i < len then incr i
    | c ->
      Buffer.add_char cur c;
      incr i
  done;
  if Buffer.length cur > 0 then parts := Buffer.contents cur :: !parts;
  List.rev !parts

(* ════════════════════════════════════════════════════════════════
   Output result type — supports optional redirect
   ════════════════════════════════════════════════════════════════ *)

type cmd_output =
  | Text   of string          (* normal output to terminal *)
  | Empty                     (* no output *)
  | Exit   of int             (* exit code *)

let ok s   = Text s
let empty  = Empty

(* ════════════════════════════════════════════════════════════════
   COMMAND IMPLEMENTATIONS
   ════════════════════════════════════════════════════════════════ *)

(* ── ls ── *)
let cmd_ls args =
  let long  = List.exists (fun a -> let s = String.length a in
               s > 1 && a.[0] = '-' && String.contains a 'l') args in
  let all   = List.exists (fun a -> let s = String.length a in
               s > 1 && a.[0] = '-' && String.contains a 'a') args in
  let human = List.exists (fun a -> let s = String.length a in
               s > 1 && a.[0] = '-' && String.contains a 'h') args in
  let one   = List.exists (fun a -> a = "-1") args in
  let _ = human in
  let paths = List.filter (fun a -> String.length a = 0 || a.[0] <> '-') args in
  let target = match paths with [] -> !cwd | p :: _ -> resolve_path p in
  match Vfs.ls_path target with
  | None ->
    ok (csi_red ^ "ls: cannot access '" ^ target ^ "': No such file or directory" ^ csi_reset ^ "\n")
  | Some nodes ->
    let nodes = if all then Vfs.make_dir "." :: Vfs.make_dir ".." :: nodes else nodes in
    if one then begin
      let buf = Buffer.create 256 in
      List.iter (fun n ->
        Buffer.add_string buf (node_color n ^ n.Vfs.name ^ csi_reset ^ "\n")
      ) nodes;
      ok (Buffer.contents buf)
    end else if long then begin
      let buf = Buffer.create 512 in
      Buffer.add_string buf (csi_dim ^ "total " ^ string_of_int (List.length nodes) ^ csi_reset ^ "\n");
      List.iter (fun n ->
        let sz = if n.Vfs.node_type = Vfs.Directory then "4096" else string_of_int (max n.Vfs.size 1) in
        Buffer.add_string buf
          (csi_dim ^ Vfs.perm_string n ^ "  1  "
           ^ pad_right n.Vfs.owner 5 ^ "  "
           ^ pad_right n.Vfs.group 5 ^ "  "
           ^ pad_left sz 6
           ^ "  Sep 22 00:00  " ^ csi_reset
           ^ node_color n ^ n.Vfs.name ^ csi_reset ^ "\n")
      ) nodes;
      ok (Buffer.contents buf)
    end else begin
      (* short: 5 per row *)
      let buf = Buffer.create 256 in
      let i = ref 0 in
      List.iter (fun n ->
        Buffer.add_string buf (node_color n ^ pad_right n.Vfs.name 16 ^ csi_reset);
        incr i;
        if !i mod 5 = 0 then Buffer.add_char buf '\n'
      ) nodes;
      if !i mod 5 <> 0 then Buffer.add_char buf '\n';
      ok (Buffer.contents buf)
    end

(* ── cd ── *)
let cmd_cd args =
  let target = match args with [] -> getenv "HOME" | p :: _ -> p in
  let full = if target = "-" then !oldpwd else resolve_path target in
  match Vfs.find_path full with
  | Some n when n.Vfs.node_type = Vfs.Directory ->
    oldpwd := !cwd; cwd := full;
    setenv "PWD" full;
    if target = "-" then ok (!cwd ^ "\n") else empty
  | Some _ -> ok (csi_red ^ "cd: " ^ target ^ ": Not a directory" ^ csi_reset ^ "\n")
  | None   -> ok (csi_red ^ "cd: " ^ target ^ ": No such file or directory" ^ csi_reset ^ "\n")

(* ── pwd ── *)
let cmd_pwd _args = ok (!cwd ^ "\n")

(* ── echo ── *)
let cmd_echo args =
  let no_newline = List.mem "-n" args in
  let words = List.filter (fun a -> a <> "-n" && a <> "-e") args in
  let s = String.concat " " words in
  if no_newline then ok s else ok (s ^ "\n")

(* ── cat ── *)
let cmd_cat args =
  let line_nums = List.mem "-n" args in
  let files = List.filter (fun a -> a <> "-n" && a <> "-b") args in
  match files with
  | [] -> ok "cat: missing operand\n"
  | _  ->
    let buf = Buffer.create 512 in
    List.iter (fun a ->
      let full = resolve_path a in
      match Vfs.find_path full with
      | None   -> Buffer.add_string buf (csi_red ^ "cat: " ^ a ^ ": No such file or directory" ^ csi_reset ^ "\n")
      | Some n when n.Vfs.node_type = Vfs.Directory ->
        Buffer.add_string buf (csi_red ^ "cat: " ^ a ^ ": Is a directory" ^ csi_reset ^ "\n")
      | Some n ->
        if line_nums then begin
          let lines = String.split_on_char '\n' n.Vfs.content in
          let lnum = ref 1 in
          List.iter (fun l ->
            Buffer.add_string buf (Printf.sprintf "%6d\t%s\n" !lnum l);
            incr lnum
          ) lines
        end else begin
          Buffer.add_string buf n.Vfs.content;
          if n.Vfs.content <> "" && n.Vfs.content.[String.length n.Vfs.content - 1] <> '\n' then
            Buffer.add_char buf '\n'
        end
    ) files;
    ok (Buffer.contents buf)

(* ── head / tail ── *)
let cmd_head args =
  let n = try
    let i = ref (-1) in
    List.iteri (fun idx a -> if a = "-n" then i := idx) args;
    if !i >= 0 then int_of_string (List.nth args (!i + 1)) else 10
  with _ -> 10 in
  let files = List.filter (fun a -> a <> "-n" && (try ignore (int_of_string a); false with _ -> true)) args in
  match files with
  | [] -> ok "head: missing operand\n"
  | _  ->
    let buf = Buffer.create 256 in
    List.iter (fun f ->
      match Vfs.find_path (resolve_path f) with
      | None -> Buffer.add_string buf (csi_red ^ "head: " ^ f ^ ": No such file" ^ csi_reset ^ "\n")
      | Some nd ->
        let lines = String.split_on_char '\n' nd.Vfs.content in
        let taken = ref 0 in
        List.iter (fun l ->
          if !taken < n then begin
            Buffer.add_string buf (l ^ "\n");
            incr taken
          end
        ) lines
    ) files;
    ok (Buffer.contents buf)

let cmd_tail args =
  let n = try
    let i = ref (-1) in
    List.iteri (fun idx a -> if a = "-n" then i := idx) args;
    if !i >= 0 then int_of_string (List.nth args (!i + 1)) else 10
  with _ -> 10 in
  let files = List.filter (fun a -> a <> "-n" && (try ignore (int_of_string a); false with _ -> true)) args in
  match files with
  | [] -> ok "tail: missing operand\n"
  | _  ->
    let buf = Buffer.create 256 in
    List.iter (fun f ->
      match Vfs.find_path (resolve_path f) with
      | None -> Buffer.add_string buf (csi_red ^ "tail: " ^ f ^ ": No such file" ^ csi_reset ^ "\n")
      | Some nd ->
        let lines = Array.of_list (String.split_on_char '\n' nd.Vfs.content) in
        let total = Array.length lines in
        let start = max 0 (total - n) in
        for i = start to total - 1 do
          Buffer.add_string buf (lines.(i) ^ "\n")
        done
    ) files;
    ok (Buffer.contents buf)

(* ── wc ── *)
let cmd_wc args =
  let count_l = List.mem "-l" args in
  let count_w = List.mem "-w" args in
  let count_c = List.mem "-c" args in
  let all = not count_l && not count_w && not count_c in
  let files = List.filter (fun a -> String.length a = 0 || a.[0] <> '-') args in
  match files with
  | [] -> ok "wc: missing operand\n"
  | _  ->
    let buf = Buffer.create 128 in
    List.iter (fun f ->
      match Vfs.find_path (resolve_path f) with
      | None -> Buffer.add_string buf (csi_red ^ "wc: " ^ f ^ ": No such file" ^ csi_reset ^ "\n")
      | Some nd ->
        let lines = List.length (String.split_on_char '\n' nd.Vfs.content) in
        let words = List.length (List.filter (fun s -> s <> "") (String.split_on_char ' ' nd.Vfs.content)) in
        let chars = String.length nd.Vfs.content in
        let parts = ref [] in
        if all || count_l then parts := string_of_int lines :: !parts;
        if all || count_w then parts := string_of_int words :: !parts;
        if all || count_c then parts := string_of_int chars :: !parts;
        Buffer.add_string buf (String.concat "\t" (List.rev !parts) ^ "\t" ^ f ^ "\n")
    ) files;
    ok (Buffer.contents buf)

(* ── grep ── *)
let cmd_grep args =
  let ignore_case = List.mem "-i" args in
  let show_line   = List.mem "-n" args in
  let invert      = List.mem "-v" args in
  let opts  = ["-i"; "-n"; "-v"; "-r"] in
  let plain = List.filter (fun a -> not (List.mem a opts)) args in
  match plain with
  | []         -> ok "grep: missing pattern\n"
  | pat :: fs  ->
    let match_fn haystack needle =
      let h = if ignore_case then String.lowercase_ascii haystack else haystack in
      let n = if ignore_case then String.lowercase_ascii needle   else needle in
      let lh = String.length h and ln = String.length n in
      if ln = 0 then true
      else if lh < ln then false
      else begin
        let found = ref false in
        for i = 0 to lh - ln do
          if String.sub h i ln = n then found := true
        done;
        !found
      end
    in
    let buf = Buffer.create 256 in
    List.iter (fun f ->
      match Vfs.find_path (resolve_path f) with
      | None -> Buffer.add_string buf (csi_red ^ "grep: " ^ f ^ ": No such file" ^ csi_reset ^ "\n")
      | Some nd ->
        let lines = String.split_on_char '\n' nd.Vfs.content in
        List.iteri (fun idx l ->
          let matched = match_fn l pat in
          if matched <> invert then begin
            if show_line then Buffer.add_string buf (string_of_int (idx + 1) ^ ":");
            Buffer.add_string buf (l ^ "\n")
          end
        ) lines
    ) fs;
    ok (Buffer.contents buf)

(* ── find ── *)
let cmd_find args =
  let name_pat = try
    let i = ref (-1) in
    List.iteri (fun idx a -> if a = "-name" then i := idx) args;
    if !i >= 0 && !i + 1 < List.length args then Some (List.nth args (!i + 1)) else None
  with _ -> None in
  let type_f = List.mem "-type" args in
  let _ = type_f in
  let roots = List.filter (fun a ->
    a <> "-name" && a <> "-type" && a <> "f" && a <> "d"
    && (match name_pat with Some p -> a <> p | None -> true)
  ) args in
  let root = match roots with [] -> !cwd | r :: _ -> resolve_path r in
  let buf = Buffer.create 256 in
  let rec walk path =
    (match Vfs.find_path path with
     | None -> ()
     | Some n ->
       let show = match name_pat with
         | None   -> true
         | Some p -> n.Vfs.name = p
       in
       if show then Buffer.add_string buf (path ^ "\n");
       if n.Vfs.node_type = Vfs.Directory then
         List.iter (fun child -> walk (path_join path child.Vfs.name)) (Vfs.ls_node n))
  in
  walk root;
  ok (Buffer.contents buf)

(* ── tree ── *)
let cmd_tree args =
  let root = match args with [] -> !cwd | p :: _ -> resolve_path p in
  let buf = Buffer.create 512 in
  Buffer.add_string buf (csi_lblue ^ csi_bold ^ root ^ csi_reset ^ "\n");
  let rec walk path prefix last_list =
    match Vfs.ls_path path with
    | None -> ()
    | Some nodes ->
      let count = List.length nodes in
      List.iteri (fun i n ->
        let is_last = i = count - 1 in
        let branch  = if is_last then "└── " else "├── " in
        Buffer.add_string buf (prefix ^ csi_dim ^ branch ^ csi_reset ^ node_color n ^ n.Vfs.name ^ csi_reset ^ "\n");
        if n.Vfs.node_type = Vfs.Directory then begin
          let child_prefix = prefix ^ (if is_last then "    " else "│   ") in
          let _ = last_list in
          walk (path_join path n.Vfs.name) child_prefix []
        end
      ) nodes
  in
  walk root "" [];
  ok (Buffer.contents buf)

(* ── stat ── *)
let cmd_stat args =
  match args with
  | [] -> ok "stat: missing operand\n"
  | _  ->
    let buf = Buffer.create 256 in
    List.iter (fun a ->
      let full = resolve_path a in
      match Vfs.find_path full with
      | None -> Buffer.add_string buf (csi_red ^ "stat: " ^ a ^ ": No such file" ^ csi_reset ^ "\n")
      | Some n ->
        let kind = match n.Vfs.node_type with
          | Vfs.File      -> "regular file"
          | Vfs.Directory -> "directory"
          | Vfs.Symlink   -> "symbolic link"
          | Vfs.Device    -> "character device"
        in
        Buffer.add_string buf
          (Printf.sprintf "  File: %s\n  Size: %-12d FileType: %s\n  Mode: (%s)  Uid: %s  Gid: %s\n  Access: Sep 22 00:00:00.000\n  Modify: Sep 22 00:00:00.000\n"
             full n.Vfs.size kind (Vfs.perm_string n) n.Vfs.owner n.Vfs.group)
    ) args;
    ok (Buffer.contents buf)

(* ── touch ── *)
let cmd_touch args =
  let buf = Buffer.create 64 in
  List.iter (fun a ->
    let full = resolve_path a in
    match Vfs.find_path full with
    | Some _ -> () (* already exists, update timestamp — we just no-op *)
    | None ->
      (* find parent directory and add child *)
      let parts = List.filter (fun s -> s <> "") (String.split_on_char '/' full) in
      (match List.rev parts with
       | [] -> ()
       | fname :: parent_parts ->
         let parent_path = match List.rev parent_parts with
           | [] -> "/"
           | pp -> "/" ^ String.concat "/" pp
         in
         match Vfs.find_path parent_path with
         | Some pn when pn.Vfs.node_type = Vfs.Directory ->
           Vfs.add_child pn (Vfs.make_file fname "")
         | _ ->
           Buffer.add_string buf (csi_red ^ "touch: " ^ a ^ ": No such directory" ^ csi_reset ^ "\n"))
  ) args;
  ok (Buffer.contents buf)

(* ── mkdir ── *)
let cmd_mkdir args =
  let parents = List.mem "-p" args in
  let dirs = List.filter (fun a -> a <> "-p") args in
  let buf = Buffer.create 64 in
  let mk_one full =
    let parts = List.filter (fun s -> s <> "") (String.split_on_char '/' full) in
    let rec ensure_path so_far = function
      | [] -> ()
      | seg :: rest ->
        let p = if so_far = "/" then "/" ^ seg else so_far ^ "/" ^ seg in
        (match Vfs.find_path p with
         | Some n when n.Vfs.node_type = Vfs.Directory -> ensure_path p rest
         | Some _ -> Buffer.add_string buf (csi_red ^ "mkdir: " ^ p ^ ": Not a directory" ^ csi_reset ^ "\n")
         | None ->
           match Vfs.find_path so_far with
           | Some pn when pn.Vfs.node_type = Vfs.Directory ->
             Vfs.add_child pn (Vfs.make_dir seg);
             ensure_path p rest
           | _ -> Buffer.add_string buf (csi_red ^ "mkdir: cannot create '" ^ p ^ "'" ^ csi_reset ^ "\n"))
    in
    if parents then ensure_path "/" parts
    else begin
      match List.rev parts with
      | [] -> ()
      | dname :: parent_parts ->
        let parent_path = match List.rev parent_parts with
          | [] -> "/"
          | pp -> "/" ^ String.concat "/" pp
        in
        match Vfs.find_path parent_path with
        | Some pn when pn.Vfs.node_type = Vfs.Directory ->
          if List.exists (fun c -> c.Vfs.name = dname) pn.Vfs.children then
            Buffer.add_string buf (csi_red ^ "mkdir: cannot create '" ^ full ^ "': File exists" ^ csi_reset ^ "\n")
          else
            Vfs.add_child pn (Vfs.make_dir dname)
        | _ -> Buffer.add_string buf (csi_red ^ "mkdir: '" ^ full ^ "': No such file or directory" ^ csi_reset ^ "\n")
    end
  in
  List.iter (fun d -> mk_one (resolve_path d)) dirs;
  ok (Buffer.contents buf)

(* ── rm ── *)
let cmd_rm args =
  let recursive = List.mem "-r" args || List.mem "-rf" args || List.mem "-fr" args in
  let files = List.filter (fun a -> a.[0] <> '-') args in
  let buf = Buffer.create 64 in
  let remove_from_parent full =
    let parts = List.filter (fun s -> s <> "") (String.split_on_char '/' full) in
    match List.rev parts with
    | [] -> Buffer.add_string buf (csi_red ^ "rm: cannot remove '/'" ^ csi_reset ^ "\n")
    | fname :: parent_parts ->
      let parent_path = match List.rev parent_parts with
        | [] -> "/"
        | pp -> "/" ^ String.concat "/" pp
      in
      match Vfs.find_path parent_path with
      | Some pn ->
        pn.Vfs.children <- List.filter (fun c -> c.Vfs.name <> fname) pn.Vfs.children
      | None -> Buffer.add_string buf (csi_red ^ "rm: " ^ full ^ ": No such file" ^ csi_reset ^ "\n")
  in
  List.iter (fun f ->
    let full = resolve_path f in
    match Vfs.find_path full with
    | None -> Buffer.add_string buf (csi_red ^ "rm: cannot remove '" ^ f ^ "': No such file or directory" ^ csi_reset ^ "\n")
    | Some n when n.Vfs.node_type = Vfs.Directory && not recursive ->
      Buffer.add_string buf (csi_red ^ "rm: cannot remove '" ^ f ^ "': Is a directory (use -r)" ^ csi_reset ^ "\n")
    | Some _ -> remove_from_parent full
  ) files;
  ok (Buffer.contents buf)

(* ── cp ── *)
let cmd_cp args =
  let files = List.filter (fun a -> String.length a = 0 || a.[0] <> '-') args in
  match files with
  | [src; dst] ->
    let sfull = resolve_path src in
    let dfull = resolve_path dst in
    (match Vfs.find_path sfull with
     | None -> ok (csi_red ^ "cp: cannot stat '" ^ src ^ "': No such file" ^ csi_reset ^ "\n")
     | Some sn when sn.Vfs.node_type = Vfs.Directory ->
       ok (csi_red ^ "cp: -r not specified; omitting directory '" ^ src ^ "'" ^ csi_reset ^ "\n")
     | Some sn ->
       let dname = List.nth (List.rev (List.filter (fun s -> s <> "") (String.split_on_char '/' dfull))) 0 in
       let parent_path =
         let parts = List.filter (fun s -> s <> "") (String.split_on_char '/' dfull) in
         match List.rev parts with
         | [] -> "/"
         | _ :: pp -> (match List.rev pp with [] -> "/" | p -> "/" ^ String.concat "/" p)
       in
       (match Vfs.find_path parent_path with
        | Some pn when pn.Vfs.node_type = Vfs.Directory ->
          pn.Vfs.children <- List.filter (fun c -> c.Vfs.name <> dname) pn.Vfs.children;
          Vfs.add_child pn (Vfs.make_file ~perm:sn.Vfs.perm dname sn.Vfs.content);
          empty
        | _ -> ok (csi_red ^ "cp: target directory not found" ^ csi_reset ^ "\n")))
  | _ -> ok "cp: missing operand\nUsage: cp <source> <dest>\n"

(* ── mv ── *)
let cmd_mv args =
  let files = List.filter (fun a -> String.length a = 0 || a.[0] <> '-') args in
  match files with
  | [src; dst] ->
    (match cmd_cp [src; dst] with
     | Text e when String.length e > 0 && e.[0] = '\027' -> ok e
     | _ -> cmd_rm [src])
  | _ -> ok "mv: missing operand\nUsage: mv <source> <dest>\n"

(* ── chmod / chown ── *)
let cmd_chmod args =
  match args with
  | _ :: file :: _ ->
    (match Vfs.find_path (resolve_path file) with
     | None -> ok (csi_red ^ "chmod: '" ^ file ^ "': No such file" ^ csi_reset ^ "\n")
     | Some _ -> empty)
  | _ -> ok "chmod: missing operand\n"

let cmd_chown args =
  match args with
  | owner_group :: files ->
    let _ = owner_group in
    let buf = Buffer.create 32 in
    List.iter (fun f ->
      match Vfs.find_path (resolve_path f) with
      | None -> Buffer.add_string buf (csi_red ^ "chown: '" ^ f ^ "': No such file" ^ csi_reset ^ "\n")
      | Some _ -> ()
    ) files;
    ok (Buffer.contents buf)
  | [] -> ok "chown: missing operand\n"

(* ── nano / edit ── *)
let cmd_nano args =
  match args with
  | [] -> ok "nano: missing file operand\n"
  | fname :: rest ->
    let full = resolve_path fname in
    let new_content = String.concat " " rest in
    if rest <> [] then begin
      (match Vfs.find_path full with
       | Some n -> n.Vfs.content <- new_content ^ "\n"
       | None ->
         let parts = List.filter (fun s -> s <> "") (String.split_on_char '/' full) in
         match List.rev parts with
         | [] -> ()
         | base :: pp ->
           let parent = match List.rev pp with [] -> "/" | p -> "/" ^ String.concat "/" p in
           match Vfs.find_path parent with
           | Some pn when pn.Vfs.node_type = Vfs.Directory ->
             Vfs.add_child pn (Vfs.make_file base (new_content ^ "\n"))
           | _ -> ());
      ok (csi_dim ^ "[ Wrote " ^ string_of_int (String.length new_content) ^ " bytes to " ^ fname ^ " ]" ^ csi_reset ^ "\n")
    end else begin
      let existing = match Vfs.find_path full with
        | Some n -> n.Vfs.content
        | None -> "[ New File ]\n"
      in
      let lines = String.split_on_char '\n' existing in
      let buf = Buffer.create 256 in
      Buffer.add_string buf (csi_bold ^ csi_lcyan ^ "  GNU nano 7.2                File: " ^ fname ^ csi_reset ^ "\n\n");
      List.iteri (fun idx l ->
        Buffer.add_string buf (Printf.sprintf "%4d | %s\n" (idx + 1) l)
      ) lines;
      Buffer.add_string buf ("\n" ^ csi_dim ^ "[ " ^ string_of_int (List.length lines) ^ " lines ]  (Tip: use 'echo text > file' or 'nano file text' to edit)" ^ csi_reset ^ "\n");
      ok (Buffer.contents buf)
    end

(* ── more / less ── *)
let cmd_more args = cmd_cat args

(* ── lsmod ── *)
let cmd_lsmod _args =
  ok ("Module                  Size  Used by\n\
       vga_text               16384  1\n\
       serial_16550           16384  1\n\
       ps2_kbd                16384  0\n\
       e1000                  32768  0\n\
       virtio_pci             24576  0\n\
       virtio_blk             20480  0\n\
       ramfs_vfs              32768  1\n\
       ocaml_runtime         131072  1\n")

(* ── diff ── *)
let cmd_diff args =
  let files = List.filter (fun a -> String.length a = 0 || a.[0] <> '-') args in
  match files with
  | [f1; f2] ->
    let read p = match Vfs.find_path (resolve_path p) with
      | Some n -> Some (String.split_on_char '\n' n.Vfs.content)
      | None   -> None
    in
    (match read f1, read f2 with
     | None, _ -> ok (csi_red ^ "diff: " ^ f1 ^ ": No such file" ^ csi_reset ^ "\n")
     | _, None -> ok (csi_red ^ "diff: " ^ f2 ^ ": No such file" ^ csi_reset ^ "\n")
     | Some l1, Some l2 ->
       let buf = Buffer.create 256 in
       let max_lines = max (List.length l1) (List.length l2) in
       let a1 = Array.of_list l1 and a2 = Array.of_list l2 in
       for i = 0 to max_lines - 1 do
         let s1 = if i < Array.length a1 then a1.(i) else "" in
         let s2 = if i < Array.length a2 then a2.(i) else "" in
         if s1 <> s2 then begin
           Buffer.add_string buf (csi_red ^ "< " ^ s1 ^ csi_reset ^ "\n");
           Buffer.add_string buf (csi_lgreen ^ "> " ^ s2 ^ csi_reset ^ "\n")
         end
       done;
       ok (Buffer.contents buf))
  | _ -> ok "diff: missing operand\nUsage: diff <file1> <file2>\n"

(* ── uname ── *)
let cmd_uname args =
  let all = List.mem "-a" args in
  let ker = List.mem "-r" args in
  let mch = List.mem "-m" args in
  let sys = List.mem "-s" args in
  if all then
    ok ("OCamlOS ocamlos 1.0.0 #1 SMP Mon Sep 22 00:00:00 UTC 2026 x86_64 OCaml/4.14.2\n")
  else if ker then ok "1.0.0\n"
  else if mch then ok "x86_64\n"
  else if sys then ok "OCamlOS\n"
  else ok "OCamlOS\n"

(* ── uptime ── *)
let cmd_uptime _args =
  ok (Printf.sprintf " %s up %s,  1 user,  load average: 0.00, 0.00, 0.00\n"
       "00:00" (fmt_uptime ()))

(* ── whoami / id ── *)
let cmd_whoami _args = ok (!username ^ "\n")
let cmd_id _args =
  ok (Printf.sprintf "uid=0(%s) gid=0(%s) groups=0(%s)\n" !username !username !username)

(* ── hostname ── *)
let cmd_hostname args =
  match args with
  | []    -> ok (!hostname ^ "\n")
  | h :: _ -> hostname := h; empty

(* ── date ── *)
let cmd_date _args =
  ok "Mon Sep 22 00:00:00 UTC 2026\n"

(* ── free ── *)
let cmd_free args =
  let human = List.mem "-h" args in
  let total  = 131072 in
  let used   =  16384 in
  let free_m = total - used in
  let buf    = 1024 in
  let avail  = free_m - buf in
  let fmt n  = if human then human_size (n * 1024) else string_of_int n in
  let hdr  = Printf.sprintf "              %-9s %-9s %-9s %-9s %-12s %s\n"
               "total" "used" "free" "shared" "buff/cache" "available" in
  let mem  = Printf.sprintf "Mem:      %-9s %-9s %-9s %-9s %-12s %s\n"
               (fmt total) (fmt used) (fmt free_m) (fmt 512) (fmt buf) (fmt avail) in
  let swap = "Swap:     0          0          0\n" in
  ok (hdr ^ mem ^ swap)

(* ── df ── *)
let cmd_df args =
  let human = List.mem "-h" args in
  let fmt n = if human then human_size (n * 1024) else string_of_int (n * 1024) in
  ok (Printf.sprintf "Filesystem      %s  %s  %s Use%% Mounted on\n\
       tmpfs       %s %s %s   0%% /\n\
       ramfs       %s %s %s   0%% /tmp\n"
    (pad_right "Size" 8) (pad_right "Used" 8) (pad_right "Avail" 8)
    (pad_right (fmt 131072) 8) (pad_right (fmt 16384) 8) (pad_right (fmt 114688) 8)
    (pad_right (fmt 16384) 8) (pad_right (fmt 0) 8) (pad_right (fmt 16384) 8))

(* ── du ── *)
let cmd_du args =
  let human = List.mem "-h" args in
  let target = match List.filter (fun a -> String.length a = 0 || a.[0] <> '-') args with
    | []    -> !cwd
    | p :: _ -> resolve_path p
  in
  let fmt n = if human then human_size n else string_of_int n in
  let buf = Buffer.create 128 in
  let rec walk path =
    match Vfs.find_path path with
    | None -> ()
    | Some n ->
      let sz = if n.Vfs.node_type = Vfs.Directory then 4096 else max n.Vfs.size 1 in
      Buffer.add_string buf (fmt sz ^ "\t" ^ path ^ "\n");
      if n.Vfs.node_type = Vfs.Directory then
        List.iter (fun c -> walk (path_join path c.Vfs.name)) (Vfs.ls_node n)
  in
  walk target;
  ok (Buffer.contents buf)

(* ── ps ── *)
let cmd_ps args =
  let full = List.mem "aux" args || List.mem "-e" args || List.mem "-ef" args in
  let hdr = if full
    then Printf.sprintf "%-6s %-8s %5s %5s %-5s %-4s %8s %s\n" "PID" "USER" "%CPU" "%MEM" "TTY" "STAT" "TIME" "COMMAND"
    else Printf.sprintf "  %-6s %-5s %-8s  %s\n" "PID" "TTY" "TIME" "CMD"
  in
  let procs = [
    (1,  "root",   "0.0", "0.1", "tty0",  "Ss", "00:00:01", "init");
    (2,  "root",   "0.0", "0.0", "tty0",  "S",  "00:00:00", "[kworker]");
    (3,  "root",   "0.0", "0.0", "tty0",  "S",  "00:00:00", "[ksoftirqd]");
    (4,  "root",   "0.0", "0.0", "tty0",  "S",  "00:00:00", "[kblockd]");
    (5,  "root",   "0.0", "0.0", "ttyS0", "S",  "00:00:00", "[kmain]");
    (6,  !username, "0.1", "0.2", "ttyS0", "S+", "00:00:07", "ocamlsh");
  ] in
  let buf = Buffer.create 256 in
  Buffer.add_string buf hdr;
  List.iter (fun (pid, user, cpu, mem, tty, stat, time, cmd) ->
    if full then
      Buffer.add_string buf
        (Printf.sprintf "%-6d %-8s %5s %5s %-5s %-4s %8s %s\n" pid user cpu mem tty stat time cmd)
    else
      Buffer.add_string buf
        (Printf.sprintf "  %-6d %-5s %-8s  %s\n" pid tty time cmd)
  ) procs;
  ok (Buffer.contents buf)

(* ── top (snapshot) ── *)
let cmd_top _args =
  let uptime = fmt_uptime () in
  ok (Printf.sprintf
    "%stop - %s up %s, 1 user, load average: 0.00, 0.00, 0.00%s\n\
     Tasks:   6 total,   1 running,   5 sleeping,   0 stopped\n\
     %%Cpu(s):  0.1 us,  0.0 sy,  0.0 ni, 99.9 id,  0.0 wa\n\
     MiB Mem:  128.0 total,  112.0 free,   12.5 used,   3.5 buff/cache\n\
     MiB Swap:    0.0 total,    0.0 free,    0.0 used\n\n\
     %s%s%-6s %-8s %5s %5s %-5s %-4s %8s %s%s\n\
       1 root      0.0  0.1 tty0  Ss 00:00:01 init\n\
       2 root      0.0  0.0 tty0  S  00:00:00 [kworker]\n\
       3 root      0.0  0.0 tty0  S  00:00:00 [ksoftirqd]\n\
       5 root      0.0  0.0 ttyS0 S  00:00:00 [kmain]\n\
       6 %s      0.1  0.2 ttyS0 S+ 00:00:07 ocamlsh\n"
    csi_bold "00:00" uptime csi_reset
    csi_bold csi_lblue "PID" "USER" "%CPU" "%MEM" "TTY" "STAT" "TIME" "COMMAND" csi_reset
    !username)

(* ── kill ── *)
let cmd_kill args =
  let pids = List.filter (fun a -> String.length a = 0 || a.[0] <> '-') args in
  let buf = Buffer.create 32 in
  List.iter (fun p ->
    (try
      let pid = int_of_string p in
      if pid <= 0 then raise Exit;
      if pid = 1 then
        Buffer.add_string buf (csi_red ^ "kill: cannot kill init (pid 1)" ^ csi_reset ^ "\n")
      else if pid = 6 then
        Buffer.add_string buf (csi_yellow ^ "kill: cannot kill yourself" ^ csi_reset ^ "\n")
      else
        Buffer.add_string buf (csi_dim ^ "(process " ^ p ^ " signalled)" ^ csi_reset ^ "\n")
    with _ ->
      Buffer.add_string buf (csi_red ^ "kill: " ^ p ^ ": Invalid PID" ^ csi_reset ^ "\n"))
  ) pids;
  ok (Buffer.contents buf)

(* ── dmesg ── *)
let cmd_dmesg _args =
  match Vfs.find_path "/var/log/kern.log" with
  | Some n -> ok n.Vfs.content
  | None   -> ok "(dmesg: log unavailable)\n"

(* ── mount ── *)
let cmd_mount _args =
  ok ("tmpfs on / type tmpfs (rw,relatime)\n"
    ^ "ramfs on /tmp type ramfs (rw,relatime)\n"
    ^ "proc on /proc type proc (ro,nosuid,nodev,noexec,relatime)\n"
    ^ "sysfs on /sys type sysfs (ro,nosuid,nodev,noexec,relatime)\n"
    ^ "devtmpfs on /dev type devtmpfs (rw,nosuid,size=65536k)\n")

(* ── lscpu ── *)
let cmd_lscpu _args =
  ok ("Architecture:        x86_64\n"
    ^ "CPU op-mode(s):      32-bit, 64-bit\n"
    ^ "Byte Order:          Little Endian\n"
    ^ "CPU(s):              1\n"
    ^ "Model name:          OCamlOS Virtual x86_64 CPU\n"
    ^ "CPU MHz:             3200.000\n"
    ^ "L1d cache:           32K\n"
    ^ "L1i cache:           32K\n"
    ^ "L2 cache:            256K\n"
    ^ "L3 cache:            8192K\n"
    ^ "Flags:               fpu vme de pse tsc msr pae mce apic mtrr pge mca cmov\n")

(* ── lspci ── *)
let cmd_lspci _args =
  ok ("00:00.0 Host bridge: Intel Corporation 440FX - 82441FX PMC [Natoma]\n"
    ^ "00:01.0 ISA bridge: Intel Corporation 82371SB PIIX3 ISA\n"
    ^ "00:02.0 VGA compatible controller: QEMU/bochs display adapter\n"
    ^ "00:03.0 Ethernet controller: Intel Corporation 82540EM Gigabit Ethernet\n"
    ^ "00:04.0 SCSI storage controller: LSI Logic BusLogic SCSI\n")

(* ── env ── *)
let cmd_env _args =
  let buf = Buffer.create 256 in
  List.iter (fun (k, v) ->
    Buffer.add_string buf (k ^ "=" ^ !v ^ "\n")
  ) env_vars;
  Buffer.add_string buf ("PWD=" ^ !cwd ^ "\n");
  Buffer.add_string buf ("OLDPWD=" ^ !oldpwd ^ "\n");
  Buffer.add_string buf ("HOSTNAME=" ^ !hostname ^ "\n");
  ok (Buffer.contents buf)

(* ── export ── *)
let cmd_export args =
  let buf = Buffer.create 64 in
  List.iter (fun a ->
    match String.split_on_char '=' a with
    | [k; v] -> setenv k v
    | [k]    ->
      Buffer.add_string buf (k ^ "=" ^ getenv k ^ "\n")
    | _      ->
      Buffer.add_string buf (csi_red ^ "export: invalid assignment: " ^ a ^ csi_reset ^ "\n")
  ) args;
  ok (Buffer.contents buf)

(* ── history ── *)
let cmd_history _args =
  let buf = Buffer.create 256 in
  let total = !hist_len in
  let start = max 0 (total - 200) in
  for i = start to total - 1 do
    Buffer.add_string buf
      (Printf.sprintf " %4d  %s\n" (i + 1) history.(i mod 200))
  done;
  ok (Buffer.contents buf)

(* ── alias ── *)
let cmd_alias args =
  match args with
  | [] ->
    let buf = Buffer.create 128 in
    List.iter (fun (k, v) ->
      Buffer.add_string buf ("alias " ^ k ^ "='" ^ v ^ "'\n")
    ) !aliases;
    ok (Buffer.contents buf)
  | _  ->
    List.iter (fun a ->
      match String.split_on_char '=' a with
      | [k; v] -> aliases := (k, v) :: List.filter (fun (x, _) -> x <> k) !aliases
      | _      -> ()
    ) args;
    empty

(* ── which / whereis ── *)
let cmd_which args =
  let buf = Buffer.create 64 in
  List.iter (fun cmd ->
    let paths = String.split_on_char ':' (getenv "PATH") in
    let found = List.exists (fun dir ->
      match Vfs.find_path (dir ^ "/" ^ cmd) with
      | Some n when n.Vfs.perm.Vfs.owner_x -> true
      | _ -> false
    ) paths in
    if found then Buffer.add_string buf ("/bin/" ^ cmd ^ "\n")
    else Buffer.add_string buf (csi_red ^ cmd ^ " not found" ^ csi_reset ^ "\n")
  ) args;
  ok (Buffer.contents buf)

(* ── file ── *)
let cmd_file args =
  let buf = Buffer.create 128 in
  List.iter (fun a ->
    let full = resolve_path a in
    match Vfs.find_path full with
    | None -> Buffer.add_string buf (a ^ ": cannot open (No such file or directory)\n")
    | Some n ->
      let kind = match n.Vfs.node_type with
        | Vfs.Directory -> "directory"
        | Vfs.Device    -> "character special"
        | Vfs.Symlink   -> "symbolic link"
        | Vfs.File when n.Vfs.perm.Vfs.owner_x -> "ELF 64-bit executable, x86-64"
        | Vfs.File when String.length n.Vfs.name > 3 &&
            String.sub n.Vfs.name (String.length n.Vfs.name - 3) 3 = ".so" ->
          "ELF 64-bit shared object"
        | Vfs.File -> "ASCII text"
      in
      Buffer.add_string buf (a ^ ": " ^ kind ^ "\n")
  ) args;
  ok (Buffer.contents buf)

(* ── ifconfig / ip addr ── *)
let cmd_ifconfig _args =
  ok ("lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536\n"
    ^ "        inet 127.0.0.1  netmask 255.0.0.0\n"
    ^ "        loop  txqueuelen 1000  (Local Loopback)\n"
    ^ "        RX packets 0  bytes 0 (0.0 B)\n"
    ^ "        TX packets 0  bytes 0 (0.0 B)\n\n"
    ^ "eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500\n"
    ^ "        inet 10.0.2.15  netmask 255.255.255.0  broadcast 10.0.2.255\n"
    ^ "        ether 52:54:00:12:34:56  txqueuelen 1000  (Ethernet)\n"
    ^ "        RX packets 1024  bytes 131072 (128.0 KiB)\n"
    ^ "        TX packets 512   bytes 65536  (64.0 KiB)\n")

(* ── ping ── *)
let cmd_ping args =
  let count = try
    let i = ref (-1) in
    List.iteri (fun idx a -> if a = "-c" then i := idx) args;
    if !i >= 0 && !i + 1 < List.length args then int_of_string (List.nth args (!i + 1)) else 4
  with _ -> 4 in
  let non_opts = List.filter (fun a ->
    if String.length a > 0 && a.[0] = '-' then false
    else if (try ignore (int_of_string a); true with _ -> false) then false
    else true
  ) args in
  let host = match non_opts with [] -> "10.0.2.2" | h :: _ -> h in
  let buf = Buffer.create 256 in
  Buffer.add_string buf (Printf.sprintf "PING %s: 56 data bytes\n" host);
  for i = 1 to count do
    let ms_str = Printf.sprintf "0.0%d ms" (8 + (i mod 5)) in
    Buffer.add_string buf
      (Printf.sprintf "64 bytes from %s: icmp_seq=%d ttl=64 time=%s\n" host i ms_str)
  done;
  Buffer.add_string buf (Printf.sprintf "\n--- %s ping statistics ---\n" host);
  Buffer.add_string buf (Printf.sprintf "%d packets transmitted, %d received, 0%% packet loss\n" count count);
  ok (Buffer.contents buf)

(* ── netstat ── *)
let cmd_netstat _args =
  ok ("Active Internet connections\n"
    ^ "Proto  Recv-Q Send-Q Local Address           Foreign Address         State\n"
    ^ "tcp         0      0 0.0.0.0:80              0.0.0.0:*               LISTEN\n"
    ^ "tcp         0      0 0.0.0.0:8080            0.0.0.0:*               ESTABLISHED\n"
    ^ "\nActive UNIX domain sockets\n"
    ^ "Proto  RefCnt Type       State       I-Node Path\n")

(* ── arp ── *)
let cmd_arp _args =
  ok ("Address                  HWtype  HWaddress           Flags Mask     Iface\n"
    ^ "10.0.2.2                 ether   52:55:0a:00:02:02   C          eth0\n")

(* ── route ── *)
let cmd_route _args =
  ok ("Kernel IP routing table\n"
    ^ "Destination     Gateway         Genmask         Flags Metric Ref    Use Iface\n"
    ^ "0.0.0.0         10.0.2.2        0.0.0.0         UG    100    0        0 eth0\n"
    ^ "10.0.2.0        0.0.0.0         255.255.255.0   U     100    0        0 eth0\n")

(* ── reboot / poweroff ── *)
let cmd_reboot _args =
  write (csi_yellow ^ "Rebooting..." ^ csi_reset ^ "\n");
  caml_reboot ();
  empty

let cmd_poweroff _args =
  write (csi_yellow ^ "Shutting down..." ^ csi_reset ^ "\n");
  caml_poweroff ();
  empty

(* ── calc / bc ── *)
let cmd_calc args =
  let expr_str = String.concat " " args in
  let tokens = tokenize expr_str in
  let rec eval_seq acc = function
    | [] -> Some acc
    | "+" :: v :: rest -> (try eval_seq (acc + int_of_string v) rest with _ -> None)
    | "-" :: v :: rest -> (try eval_seq (acc - int_of_string v) rest with _ -> None)
    | "*" :: v :: rest -> (try eval_seq (acc * int_of_string v) rest with _ -> None)
    | "/" :: v :: rest -> (try let d = int_of_string v in if d = 0 then None else eval_seq (acc / d) rest with _ -> None)
    | _ -> None
  in
  let result = match tokens with
    | [] -> None
    | v :: rest -> (try eval_seq (int_of_string v) rest with _ -> None)
  in
  match result with
  | Some v -> ok (string_of_int v ^ "\n")
  | None   -> ok (csi_red ^ "calc: invalid expression: " ^ expr_str ^ csi_reset ^ "\n")

(* ── base64 ── *)
let cmd_base64 args =
  let decode = List.mem "-d" args in
  let texts  = List.filter (fun a -> a <> "-d" && a <> "--decode") args in
  let input  = String.concat " " texts in
  let b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" in
  if decode then begin
    (* Simple base64 decode *)
    let buf = Buffer.create 64 in
    let idx c =
      try
        let pos = ref (-1) in
        String.iteri (fun i ch -> if ch = c then pos := i) b64chars;
        !pos
      with _ -> -1
    in
    let inp =
      let b = Buffer.create (String.length input) in
      String.iter (fun c -> if c <> '\n' && c <> '\r' then Buffer.add_char b c) input;
      Buffer.contents b
    in
    let len = String.length inp in
    let i = ref 0 in
    while !i + 3 < len do
      let v0 = idx inp.[!i] in
      let v1 = idx inp.[!i+1] in
      let v2 = if inp.[!i+2] = '=' then 0 else idx inp.[!i+2] in
      let v3 = if !i+3 >= len || inp.[!i+3] = '=' then 0 else idx inp.[!i+3] in
      if v0 >= 0 && v1 >= 0 then begin
        Buffer.add_char buf (Char.chr ((v0 lsl 2) lor (v1 lsr 4)));
        if inp.[!i+2] <> '=' then
          Buffer.add_char buf (Char.chr (((v1 land 0xF) lsl 4) lor (v2 lsr 2)));
        if !i+3 < len && inp.[!i+3] <> '=' then
          Buffer.add_char buf (Char.chr (((v2 land 0x3) lsl 6) lor v3))
      end;
      i := !i + 4
    done;
    ok (Buffer.contents buf ^ "\n")
  end else begin
    (* Simple base64 encode *)
    let buf = Buffer.create 64 in
    let bytes = Array.init (String.length input) (fun i -> Char.code input.[i]) in
    let len = Array.length bytes in
    let i = ref 0 in
    while !i < len do
      let b0 = bytes.(!i) in
      let b1 = if !i + 1 < len then bytes.(!i + 1) else 0 in
      let b2 = if !i + 2 < len then bytes.(!i + 2) else 0 in
      Buffer.add_char buf b64chars.[(b0 lsr 2)];
      Buffer.add_char buf b64chars.[((b0 land 3) lsl 4) lor (b1 lsr 4)];
      Buffer.add_char buf (if !i + 1 < len then b64chars.[((b1 land 0xF) lsl 2) lor (b2 lsr 6)] else '=');
      Buffer.add_char buf (if !i + 2 < len then b64chars.[b2 land 0x3F] else '=');
      i := !i + 3
    done;
    ok (Buffer.contents buf ^ "\n")
  end

(* ── sleep (busy wait — in terminal it's interactive) ── *)
let cmd_sleep args =
  (match args with
  | [n] ->
    (try
      let secs = int_of_string n in
      let _ = secs in
      ok "" (* In bare-metal we just acknowledge, real sleep would need timer *)
    with _ -> ok (csi_red ^ "sleep: invalid time interval" ^ csi_reset ^ "\n"))
  | _ -> ok "sleep: missing operand\n")

(* ── cmatrix (Matrix rain in VGA) ── *)
let cmatrix_running = ref false

let cmd_cmatrix _args =
  write (csi_clear);
  write (csi_lgreen);
  write "  [OCamlOS Matrix Rain — press any key to exit]\n\n";
  (* Print animated ascii matrix — we do a single snapshot for now *)
  let cols = 78 in
  let rows = 20 in
  let chars = "abcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+{}|:<>?" in
  let clen = String.length chars in
  let buf = Buffer.create 512 in
  for _y = 0 to rows - 1 do
    for _x = 0 to cols - 1 do
      if Random.int 5 = 0 then begin
        Buffer.add_string buf csi_lgreen;
        Buffer.add_char buf chars.[Random.int clen]
      end else if Random.int 10 = 0 then begin
        Buffer.add_string buf csi_green;
        Buffer.add_char buf chars.[Random.int clen]
      end else
        Buffer.add_char buf ' '
    done;
    Buffer.add_char buf '\n'
  done;
  Buffer.add_string buf csi_reset;
  cmatrix_running := true;
  ok (Buffer.contents buf)

(* ── fortune / cowsay ── *)
let fortunes = [|
  "Simplicity is the ultimate sophistication.";
  "The best code is no code at all.";
  "Any sufficiently advanced technology is indistinguishable from magic.";
  "First, solve the problem. Then, write the code.";
  "Code is like humor. When you have to explain it, it's bad.";
  "Make it work, make it right, make it fast.";
  "Premature optimization is the root of all evil.";
  "Programs must be written for people to read.";
  "Debugging is twice as hard as writing code.";
  "The most powerful tool we have as developers is automation.";
|]

let cmd_fortune _args =
  let f = fortunes.(Random.int (Array.length fortunes)) in
  ok (csi_lyellow ^ f ^ csi_reset ^ "\n")

let cmd_cowsay args =
  let msg = match args with [] -> "Moo!" | _ -> String.concat " " args in
  let line = String.make (String.length msg + 2) '-' in
  ok (Printf.sprintf " %s\n< %s >\n %s\n        \\   ^__^\n         \\  (oo)\\_______\n            (__)\\       )\\/\\\n                ||----w |\n                ||     ||\n" line msg line)

(* ── yes ── *)
let cmd_yes args =
  let msg = match args with [] -> "y" | _ -> String.concat " " args in
  (* Output a limited number to avoid infinite loop *)
  let buf = Buffer.create 200 in
  for _ = 1 to 20 do
    Buffer.add_string buf (msg ^ "\n")
  done;
  Buffer.add_string buf csi_dim;
  Buffer.add_string buf "(yes: use Ctrl+C to stop)\n";
  Buffer.add_string buf csi_reset;
  ok (Buffer.contents buf)

(* ── man ── *)
let man_pages : (string * string) list = [
  "ls",       "ls - list directory contents\n\nUSAGE: ls [-la] [path]\nOPTIONS:\n  -l  long listing format\n  -a  show hidden files\n  -h  human-readable sizes\n  -1  one entry per line\n";
  "cat",      "cat - concatenate and display files\n\nUSAGE: cat [-n] <file...>\nOPTIONS:\n  -n  number all output lines\n";
  "grep",     "grep - search for patterns in files\n\nUSAGE: grep [-inv] <pattern> <file...>\nOPTIONS:\n  -i  ignore case\n  -n  show line numbers\n  -v  invert match\n";
  "find",     "find - search for files in a directory hierarchy\n\nUSAGE: find [path] [-name pattern]\n";
  "ps",       "ps - report process status\n\nUSAGE: ps [aux]\n";
  "free",     "free - display memory usage\n\nUSAGE: free [-h]\nOPTIONS:\n  -h  human-readable output\n";
  "ping",     "ping - send ICMP ECHO_REQUEST to network hosts\n\nUSAGE: ping [-c count] <host>\n";
  "uname",    "uname - print system information\n\nUSAGE: uname [-a]\nOPTIONS:\n  -a  all information\n  -r  kernel release\n  -m  machine hardware\n";
]

let cmd_man args =
  match args with
  | []     -> ok "What manual page do you want?\n"
  | cmd :: _ ->
    (match List.assoc_opt cmd man_pages with
     | Some page -> ok (csi_bold ^ csi_lwhite ^ page ^ csi_reset)
     | None -> ok (csi_red ^ "No manual entry for " ^ cmd ^ csi_reset ^ "\n"))

(* ── help ── *)
let cmd_help _args =
  ok (
    csi_bold ^ csi_lcyan
    ^ "  ╔══════════════════════════════════════════════════════════════╗\n"
    ^ "  ║       OCamlOS Shell v1.0  —  Bare-Metal Linux Terminal       ║\n"
    ^ "  ╚══════════════════════════════════════════════════════════════╝\n"
    ^ csi_reset
    ^ csi_lyellow ^ "  FILESYSTEM\n" ^ csi_reset
    ^ "    ls [-lah1]    cd [path]    pwd         cat [-n]     head/tail\n"
    ^ "    touch          mkdir [-p]   rm [-r]    cp           mv\n"
    ^ "    chmod          chown        find        grep [-inv]  wc [-lwc]\n"
    ^ "    tree           stat         diff        file\n\n"
    ^ csi_lyellow ^ "  SYSTEM\n" ^ csi_reset
    ^ "    uname [-a]     uptime       whoami      id           hostname\n"
    ^ "    ps [aux]       top          kill        free [-h]    df [-h]\n"
    ^ "    du [-h]        dmesg        mount       lscpu        lspci\n"
    ^ "    env            export       date        history      reboot\n"
    ^ "    poweroff/shutdown\n\n"
    ^ csi_lyellow ^ "  NETWORK\n" ^ csi_reset
    ^ "    ifconfig       ping [-c n]  netstat     arp          route\n\n"
    ^ csi_lyellow ^ "  UTILITIES\n" ^ csi_reset
    ^ "    echo [-n]      clear        which       alias        man\n"
    ^ "    calc/bc        base64 [-d]  sleep       yes          cmatrix\n"
    ^ "    fortune        cowsay\n\n"
    ^ csi_lyellow ^ "  KEYBINDINGS\n" ^ csi_reset
    ^ "    Up/Down     history     Left/Right  cursor move\n"
    ^ "    Home/End    line start/end   Tab    auto-complete\n"
    ^ "    Ctrl+C      cancel line      Ctrl+L  clear screen\n"
    ^ "    Ctrl+D      exit (root)\n\n"
    ^ csi_dim ^ "  Tip: Use '>' to redirect output:  cat /etc/hostname > /tmp/out\n"
    ^ csi_reset)

(* ════════════════════════════════════════════════════════════════
   TAB COMPLETION
   ════════════════════════════════════════════════════════════════ *)

let all_cmds = [
  "ls"; "cd"; "pwd"; "cat"; "head"; "tail"; "wc"; "grep"; "find"; "tree";
  "stat"; "touch"; "mkdir"; "rm"; "cp"; "mv"; "chmod"; "chown"; "diff";
  "file"; "nano"; "edit"; "more"; "less"; "lsmod"; "ip";
  "uname"; "uptime"; "whoami"; "id"; "hostname"; "date"; "ps";
  "top"; "kill"; "free"; "df"; "du"; "dmesg"; "mount"; "lscpu"; "lspci";
  "env"; "export"; "history"; "alias"; "which"; "echo"; "clear"; "man";
  "help"; "calc"; "bc"; "base64"; "sleep"; "yes"; "cmatrix"; "fortune";
  "cowsay"; "ifconfig"; "ping"; "netstat"; "arp"; "route"; "exit"; "reboot";
  "poweroff"; "shutdown";
]

let complete_word prefix =
  (* Try commands first if this is the first token *)
  let cmds = List.filter (fun c ->
    let plen = String.length prefix and clen = String.length c in
    plen <= clen && String.sub c 0 plen = prefix
  ) all_cmds in
  (* Also try filesystem paths *)
  let path_completions =
    let dir, name_pfx =
      match String.rindex_opt prefix '/' with
      | None   -> !cwd, prefix
      | Some i -> resolve_path (String.sub prefix 0 (i + 1)), String.sub prefix (i + 1) (String.length prefix - i - 1)
    in
    match Vfs.ls_path dir with
    | None -> []
    | Some nodes ->
      List.filter_map (fun n ->
        let nlen = String.length n.Vfs.name and plen = String.length name_pfx in
        if plen <= nlen && String.sub n.Vfs.name 0 plen = name_pfx then
          Some (n.Vfs.name ^ (if n.Vfs.node_type = Vfs.Directory then "/" else ""))
        else None
      ) nodes
  in
  cmds @ path_completions

(* ════════════════════════════════════════════════════════════════
   OUTPUT REDIRECTION PARSER
   ════════════════════════════════════════════════════════════════ *)

type redirect = Append of string | Overwrite of string | None_redir

let parse_redirect tokens =
  let rec scan acc = function
    | [] -> List.rev acc, None_redir
    | ">>" :: file :: rest ->
      let _ = rest in
      List.rev acc, Append file
    | ">" :: file :: rest ->
      let _ = rest in
      List.rev acc, Overwrite file
    | t :: rest -> scan (t :: acc) rest
  in
  scan [] tokens

let apply_redirect redir output =
  match redir with
  | None_redir -> ()
  | Overwrite file ->
    let full = resolve_path file in
    let content = match output with Text s -> s | _ -> "" in
    (match Vfs.find_path full with
     | Some n -> n.Vfs.content <- content
     | None ->
       let parts = List.filter (fun s -> s <> "") (String.split_on_char '/' full) in
       (match List.rev parts with
        | [] -> ()
        | fname :: pp ->
          let parent = match List.rev pp with [] -> "/" | p -> "/" ^ String.concat "/" p in
          match Vfs.find_path parent with
          | Some pn when pn.Vfs.node_type = Vfs.Directory ->
            Vfs.add_child pn (Vfs.make_file fname content)
          | _ -> ()))
  | Append file ->
    let full = resolve_path file in
    let content = match output with Text s -> s | _ -> "" in
    (match Vfs.find_path full with
     | Some n -> n.Vfs.content <- n.Vfs.content ^ content
     | None ->
       let parts = List.filter (fun s -> s <> "") (String.split_on_char '/' full) in
       (match List.rev parts with
        | [] -> ()
        | fname :: pp ->
          let parent = match List.rev pp with [] -> "/" | p -> "/" ^ String.concat "/" p in
          match Vfs.find_path parent with
          | Some pn when pn.Vfs.node_type = Vfs.Directory ->
            Vfs.add_child pn (Vfs.make_file fname content)
          | _ -> ()))

(* ════════════════════════════════════════════════════════════════
   COMMAND DISPATCHER
   ════════════════════════════════════════════════════════════════ *)

let dispatch tokens =
  match tokens with
  | []            -> empty
  | cmd :: args   ->
    (* Alias expansion *)
    let (cmd, args) =
      match List.assoc_opt cmd !aliases with
      | None -> cmd, args
      | Some expanded ->
        (match tokenize expanded with
         | []    -> cmd, args
         | c :: extra -> c, extra @ args)
    in
    match cmd with
    | "ls"       -> cmd_ls args
    | "cd"       -> cmd_cd args
    | "pwd"      -> cmd_pwd args
    | "cat"      -> cmd_cat args
    | "head"     -> cmd_head args
    | "tail"     -> cmd_tail args
    | "wc"       -> cmd_wc args
    | "grep"     -> cmd_grep args
    | "find"     -> cmd_find args
    | "tree"     -> cmd_tree args
    | "stat"     -> cmd_stat args
    | "touch"    -> cmd_touch args
    | "mkdir"    -> cmd_mkdir args
    | "rm"       -> cmd_rm args
    | "cp"       -> cmd_cp args
    | "mv"       -> cmd_mv args
    | "chmod"    -> cmd_chmod args
    | "chown"    -> cmd_chown args
    | "diff"     -> cmd_diff args
    | "file"     -> cmd_file args
    | "nano" | "edit" -> cmd_nano args
    | "more" | "less" -> cmd_more args
    | "lsmod"    -> cmd_lsmod args
    | "ip"       ->
      if args = ["a"] || args = ["addr"] || args = [] then cmd_ifconfig []
      else if args = ["r"] || args = ["route"] then cmd_route []
      else ok "Usage: ip [addr|route]\n"
    | "uname"    -> cmd_uname args
    | "uptime"   -> cmd_uptime args
    | "whoami"   -> cmd_whoami args
    | "id"       -> cmd_id args
    | "hostname" -> cmd_hostname args
    | "date"     -> cmd_date args
    | "ps"       -> cmd_ps args
    | "top" | "htop" -> cmd_top args
    | "kill"     -> cmd_kill args
    | "free"     -> cmd_free args
    | "df"       -> cmd_df args
    | "du"       -> cmd_du args
    | "dmesg"    -> cmd_dmesg args
    | "mount"    -> cmd_mount args
    | "lscpu" | "cpuinfo" -> cmd_lscpu args
    | "lspci"    -> cmd_lspci args
    | "env"      -> cmd_env args
    | "export"   -> cmd_export args
    | "history"  -> cmd_history args
    | "alias"    -> cmd_alias args
    | "which" | "whereis" -> cmd_which args
    | "echo"     -> cmd_echo args
    | "ifconfig" -> cmd_ifconfig args
    | "ping"     -> cmd_ping args
    | "netstat"  -> cmd_netstat args
    | "arp"      -> cmd_arp args
    | "route"    -> cmd_route args
    | "reboot"   -> cmd_reboot args
    | "poweroff" | "shutdown" -> cmd_poweroff args
    | "calc" | "bc" -> cmd_calc args
    | "base64"   -> cmd_base64 args
    | "sleep"    -> cmd_sleep args
    | "cmatrix"  -> cmd_cmatrix args
    | "fortune"  -> cmd_fortune args
    | "cowsay"   -> cmd_cowsay args
    | "yes"      -> cmd_yes args
    | "true"     -> empty
    | "false"    -> Exit 1
    | "man"      -> cmd_man args
    | "help"     -> cmd_help args
    | "clear"    ->
      write csi_clear;
      Vga.clear_screen ();
      empty
    | "exit"     ->
      write (csi_yellow ^ "logout\n" ^ csi_reset);
      Exit 0
    | _          ->
      ok (csi_red ^ cmd ^ csi_reset ^ ": command not found\n")

(* ════════════════════════════════════════════════════════════════
   EXECUTE FULL COMMAND LINE (with redirect, alias, etc.)
   ════════════════════════════════════════════════════════════════ *)

let execute_line line =
  let line = String.trim line in
  if line = "" then empty
  else begin
    history_add line;
    let tokens = tokenize line in
    let (cmd_tokens, redir) = parse_redirect tokens in
    let result = dispatch cmd_tokens in
    (match redir with
     | None_redir -> ()
     | _          -> apply_redirect redir result);
    match redir, result with
    | None_redir, r -> r
    | _, _          -> empty
  end

(* ════════════════════════════════════════════════════════════════
   PROMPT STRING
   ════════════════════════════════════════════════════════════════ *)

let prompt_str () =
  let user   = !username in
  let host   = !hostname in
  let dir    = if !cwd = getenv "HOME" then "~" else !cwd in
  let marker = if user = "root" then "#" else "$" in
  let color  = if user = "root" then csi_lred else csi_lgreen in
  color ^ csi_bold ^ user ^ "@" ^ host ^ csi_reset
  ^ ":" ^ csi_lblue ^ csi_bold ^ dir ^ csi_reset
  ^ color ^ marker ^ csi_reset ^ " "

let prompt () =
  let p = prompt_str () in
  serial_write p;
  vga_print p
