(* arch/x86_64/cpu.ml - CPU control and instruction primitives in OCaml *)

external cli : unit -> unit = "caml_cli"
external sti : unit -> unit = "caml_sti"
external hlt : unit -> unit = "caml_hlt"
external read_cr3 : unit -> Int64.t = "caml_read_cr3"
external write_cr3 : Int64.t -> unit = "caml_write_cr3"

let disable_interrupts () = cli ()
let enable_interrupts () = sti ()
let halt () = hlt ()
