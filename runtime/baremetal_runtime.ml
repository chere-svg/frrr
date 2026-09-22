(* runtime/baremetal_runtime.ml - OCaml Bare-Metal Runtime Hooks *)

let initialize_runtime () =
  Uart.init ();
  Uart.send_string "[OCamlOS Runtime] Pure OCaml Bare-Metal Runtime Active.\n"
