(* drivers/virtio_net.ml - VirtIO Network Card Driver in OCaml *)

type mac_address = string

type virtio_net_dev = {
  pci_dev: Pci.pci_device;
  mac: mac_address;
}

let init dev =
  { pci_dev = dev; mac = "\x52\x54\x00\x12\x34\x56" }

let send_packet dev packet =
  ignore dev; ignore packet;
  ()

let receive_packet dev =
  ignore dev;
  None
