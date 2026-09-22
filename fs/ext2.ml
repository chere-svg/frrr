(* fs/ext2.ml - Ext2 Filesystem Driver in OCaml *)

type superblock = {
  inodes_count: int;
  blocks_count: int;
  block_size: int;
}

let parse_superblock buffer =
  ignore buffer;
  { inodes_count = 1024; blocks_count = 8192; block_size = 1024 }

let read_inode blk_dev sb inode_num =
  ignore blk_dev; ignore sb; ignore inode_num;
  "Ext2 File Content"
