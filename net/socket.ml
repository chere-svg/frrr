(* net/socket.ml - Sockets Interface in OCaml *)

type socket_type = Stream | Datagram

type socket = {
  sock_type: socket_type;
  mutable bound_port: int;
}

let create sock_type =
  { sock_type; bound_port = 0 }

let bind sock port =
  sock.bound_port <- port
