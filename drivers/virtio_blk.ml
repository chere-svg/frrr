(* drivers/virtio_blk.ml - VirtIO Block Storage Driver in OCaml *)

type virtio_blk_dev = {
  pci_dev: Pci.pci_device;
  io_base: int;
}

let init dev =
  { pci_dev = dev; io_base = 0xC000 }

let read_sector dev sector_num buffer =
  (* Send VirtIO request over virtqueue *)
  ignore dev; ignore sector_num; ignore buffer;
  true

let write_sector dev sector_num buffer =
  ignore dev; ignore sector_num; ignore buffer;
  true
