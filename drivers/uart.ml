(* drivers/uart.ml - 16550 Serial UART Driver in OCaml *)

let com1 = 0x3F8

let init () =
  Ioport.outb (com1 + 1) 0x00;
  Ioport.outb (com1 + 3) 0x80;
  Ioport.outb (com1 + 0) 0x03;
  Ioport.outb (com1 + 1) 0x00;
  Ioport.outb (com1 + 3) 0x03;
  Ioport.outb (com1 + 2) 0xC7;
  Ioport.outb (com1 + 4) 0x0B

let is_transmit_empty () =
  (Ioport.inb (com1 + 5) land 0x20) <> 0

let send_char c =
  while not (is_transmit_empty ()) do () done;
  Ioport.outb com1 (Char.code c)

let send_string str =
  String.iter (fun c ->
    if c = '\n' then send_char '\r';
    send_char c
  ) str
