(* net/tcp.ml - TCP Finite State Machine in OCaml *)

type tcp_state = Closed | Listen | SynSent | SynReceived | Established | FinWait1 | FinWait2 | TimeWait

type tcp_conn = {
  mutable state: tcp_state;
  local_port: int;
  remote_port: int;
}

let create_conn local_port remote_port =
  { state = Closed; local_port; remote_port }
