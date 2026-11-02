module kernel.fs.vfs;

// enum VFS_PATH_MAX = 256;

// // #define VFS_S_IFMT   0xF000
// // #define VFS_S_IFREG  0x8000
// // #define VFS_S_IFDIR  0x4000
// // #define VFS_S_IFCHR  0x2000
// // #define VFS_S_IFBLK  0x6000
// // #define VFS_S_IFIFO  0x1000
// // #define VFS_S_IFLNK  0xA000
// // #define VFS_S_IFSOCK 0xC000

// // #define VFS_S_ISUID  0x0800
// // #define VFS_S_ISGID  0x0400
// // #define VFS_S_ISVTX  0x0200
// // #define VFS_S_IRWXU  0x01C0
// // #define VFS_S_IRWXG  0x0038
// // #define VFS_S_IRWXO  0x0007

// // #define VFS_S_ISDIR(m)  (((m) & VFS_S_IFMT) == VFS_S_IFDIR)
// // #define VFS_S_ISREG(m)  (((m) & VFS_S_IFMT) == VFS_S_IFREG)
// // #define VFS_S_ISCHR(m)  (((m) & VFS_S_IFMT) == VFS_S_IFCHR)
// // #define VFS_S_ISBLK(m)  (((m) & VFS_S_IFMT) == VFS_S_IFBLK)

// alias VfsNodeID = uint;
// alias VfsOffset = ulong;
// alias VfsMode = uint;
// alias VfsUID = ushort; // user id
// alias VfsGID = ushort; // group id
// alias VfsPID = int; // process id
// alias VfsFdID = int; // file descriptor id

// // Userspace-visible metadata
// struct VfsStat {
//     VfsNodeID ino;
//     VfsMode mode;
//     VfsUID  uid;
//     VfsGID  gid;
//     uint   nlink;
//     VfsOffset  size;
//     ulong   atime, mtime, ctime;
//     ulong   blksize, blocks;
//     uint   dev_major, dev_minor;   /* for device nodes */
// }

// // Entry type
// enum VfsDType {
//     VFS_DT_UNKNOWN = 0,
//     VFS_DT_REG, // ???
//     VFS_DT_DIR, // Directory
//     VFS_DT_CHR, // Character Device
//     VFS_DT_BLK, // Block Device
//     VFS_DT_FIFO, // First In First Out?
//     VFS_DT_LNK, // Symlink (hard or soft?)
//     VFS_DT_SOCK, // Socket
// }

// // VFS entry
// struct VfsDirEntry {
//     VfsNodeID      ino;
//     VfsDType     type;
//     char[256]    name;
// }

// struct VfsNodeOps {
//     int function(VfsNode* dir, const char* name, VfsNode**) lookup;
//     int function(VfsNode* dir, uint index, VfsDirEntry*) readdir;   /* -ENOENT = end */

//     /* --- Open-file lifecycle --- */
//     int function(VfsNode* n, VfsFile* f, int flags) open;
//     void function(VfsFile* f) close;

//     /* --- I/O --- */
//     long function(VfsFile* f, void* buf, ulong len, VfsOffset off) read;
//     long function(VfsFile* f, const void* buf, ulong len, VfsOffset off) write;
//     int function(VfsFile* f, uint cmd, void* arg) ioctl;

//     /* --- Namespace modification (optional; NULL = not supported) --- */
//     int function(VfsNode* dir, const char* name, VfsMode mode, VfsNode**) create;
//     int function(VfsNode* dir, const char* name, VfsMode mode) mkdir;
//     int function(VfsNode* dir, const char* name) unlink;
//     int function(VfsNode* dir, const char* name) rmdir;
//     int function(VfsNode* od, const char* on, VfsNode* nd, const char* nn) rename;
//     int function(VfsNode* dir, const char* name, const char* target) symlink;
//     int function(VfsNode* n, char* buf, size_t bufsz) readlink;

//     /* --- Metadata --- */
//     int function(VfsNode* n, VfsStat*) stat;
//     int function(VfsNode* n, VfsOffset size) truncate;

//     /* --- Lifecycle: called when refcount hits 0. NULL = never free. --- */
//     void function(VfsNode* n) release;
// }

// // A node is one thing in the namespace: file, directory, device, symlink, etc.
// // It carries no name - the name lives in the parent directory. This is deliberate: it makes hard links and mount points trivially expressible later.
// // Persistent node like devfs entries or a freash one placed into stack when user requests it. 
// struct VfsNode {
//     VfsNodeOps  *ops;
//     VfsMount    *mount;     /* owning mount (may be NULL for stray nodes) */
//     VfsNodeID     ino;
//     VfsMode    mode;
//     VfsUID     uid;
//     VfsGID     gid;
//     uint        nlink;
//     VfsOffset     size;
//     uint        refcount;
//     uint        flags;      /* node-private, e.g. VFS_NF_MOUNTPOINT */
//     void        *fs_data;   /* filesystem-private payload */
// }

// struct VfsFsType {
//     const char  *name;  /* "fat", "ext2", "procfs", "devfs" */
//     uint        flags;  /* FS_REQUIRES_DEV, FS_VIRTUAL, ... */

//     int function(VfsMount* mnt, const char* source, const char* opts) mount;
//     void function(VfsMount* mnt) umount;
//     int function(VfsMount* mnt) sync;

//     VfsFsType   *next;
// }

// struct VfsMount {
//     char[VFS_PATH_MAX]  path;       /* "/", "/hd0", "/dev", "/proc" */
//     uint                path_len;
//     VfsFsType           *fs;
//     VfsNode             *root;      /* fs-provided root node */
//     void                *fs_data;   /* per-instance state (e.g. FAT mount info) */
//     uint                flags;      /* MS_RDONLY, MS_NOEXEC, MS_NOSUID, ... */
//     uint                refcount;
//     VfsMount            *next;      /* list; keep sorted by path_len desc */
// }


// // One VfsFile = one open handle, owns a reference to the node
// struct VfsFile {
//     VfsNode     *node;      /* refcount held */
//     VfsMount    *mount;     /* usually node->mount */
//     VfsOffset     offset;
//     int         flags;      /* O_RDONLY/WRONLY/RDWR/APPEND/... */
//     uint        refcount;   /* for fork/dup */
//     void        *priv;      /* fs-private open state */
//     VfsCred     *cred;      /* credentials at open time */
// }

// // Described but isn't enforced
// struct VfsCred {
//     VfsUID     uid;
//     VfsGID     gid;
//     VfsGID[8]  groups;
//     uint        ngroups;
//     uint        caps;       /* capability bitmask; 0xFFFFFFFF = full */
// }
