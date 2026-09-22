(* fs/vfs.ml - Virtual Filesystem Abstraction in OCaml *)

type node_type = File | Directory | Symlink | Device

type file_perm = {
  owner_r: bool; owner_w: bool; owner_x: bool;
  group_r: bool; group_w: bool; group_x: bool;
  other_r: bool; other_w: bool; other_x: bool;
}

type vfs_node = {
  name:      string;
  node_type: node_type;
  perm:      file_perm;
  owner:     string;
  group:     string;
  size:      int;
  mutable content:  string;
  mutable children: vfs_node list;
}

let perm_dir  = { owner_r=true; owner_w=true; owner_x=true;
                  group_r=true; group_w=false; group_x=true;
                  other_r=true; other_w=false; other_x=true }
let perm_exec = { owner_r=true; owner_w=true; owner_x=true;
                  group_r=true; group_w=false; group_x=true;
                  other_r=true; other_w=false; other_x=true }
let perm_file = { owner_r=true; owner_w=true; owner_x=false;
                  group_r=true; group_w=false; group_x=false;
                  other_r=true; other_w=false; other_x=false }
let perm_priv = { owner_r=true; owner_w=true; owner_x=false;
                  group_r=false; group_w=false; group_x=false;
                  other_r=false; other_w=false; other_x=false }

(* Format a permission triplet as rwxrwxrwx *)
let perm_to_string p =
  let b x c = if x then c else '-' in
  Printf.sprintf "%c%c%c%c%c%c%c%c%c"
    (b p.owner_r 'r') (b p.owner_w 'w') (b p.owner_x 'x')
    (b p.group_r 'r') (b p.group_w 'w') (b p.group_x 'x')
    (b p.other_r 'r') (b p.other_w 'w') (b p.other_x 'x')

let type_char = function
  | Directory -> 'd' | Symlink -> 'l' | Device -> 'c' | File -> '-'

let make_node ?(perm=perm_file) ?(owner="root") ?(group="root")
              ?(content="") node_type name =
  { name; node_type; perm; owner; group;
    size = String.length content; content; children = [] }

let make_dir  name = make_node ~perm:perm_dir  Directory name
let make_file ?(perm=perm_file) name content =
  make_node ~perm ~content File name
let make_exec name = make_node ~perm:perm_exec ~content:"" File name
let make_dev  name = make_node ~perm:perm_file Device name

let root = make_dir "/"

let add_child parent child =
  parent.children <- child :: parent.children

(* Resolve a path from root, returning Some node or None *)
let find_path path =
  let parts = List.filter (fun s -> s <> "")
                (String.split_on_char '/' path) in
  let rec walk node = function
    | [] -> Some node
    | seg :: rest ->
      (match List.find_opt (fun c -> c.name = seg) node.children with
       | Some child -> walk child rest
       | None -> None)
  in
  walk root parts

(* List children of a directory node *)
let ls_node node =
  List.rev node.children

let ls_path path =
  match find_path path with
  | Some n when n.node_type = Directory -> Some (ls_node n)
  | _ -> None

let perm_string n =
  Printf.sprintf "%c%s" (type_char n.node_type) (perm_to_string n.perm)

let size_string n =
  if n.node_type = Directory then "4096"
  else string_of_int (max n.size 1)
