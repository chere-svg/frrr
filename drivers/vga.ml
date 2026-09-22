(* drivers/vga.ml - VGA Text Mode Console Driver interface *)

external vga_print        : string -> unit = "caml_vga_print"
external vga_clear_screen : unit -> unit   = "caml_vga_clear"

let clear_screen () = vga_clear_screen ()

let put_string s = vga_print s

let put_char c = vga_print (String.make 1 c)

(* Legacy color helpers for backward compatibility *)
let color_normal  = 0x0F
let color_bright  = 0x0B
let color_prompt  = 0x0A
let color_dir     = 0x09
let color_exec    = 0x0A
let color_dev     = 0x0E
let color_link    = 0x0B
let color_yellow  = 0x0E

let set_color _ = ()
let put_string_color s _ = vga_print s
let put_header s = vga_print (s ^ "\n")
