(* arch/x86_64/ioport.ml - Port I/O abstraction in OCaml *)

external outb : int -> int -> unit = "caml_outb"
external inb : int -> int = "caml_inb"
external outw : int -> int -> unit = "caml_outw"
external inw : int -> int = "caml_inw"
external outl : int -> Int32.t -> unit = "caml_outl"
external inl : int -> Int32.t = "caml_inl"
