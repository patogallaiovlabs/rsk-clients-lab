# One node per machine

Only one client runs on a machine at a time: this Mac's Docker VM, Boton box A, Boton box B.
Two at once measure each other through the shared disk and CPU. Anything heavy on this Mac (a
replay, a release build, a Docker build) runs under the shared Docker slot
(`bin/with-lock.sh <command>` or `lock_acquire docker`). On a box, take `box_lock <A|B> 2`
and run `box_quiesce` first.
