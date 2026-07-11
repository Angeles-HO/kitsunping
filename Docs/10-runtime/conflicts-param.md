# Conflicts whit the sistem for some props can cause inestability in the system, this section describes the props that can cause conflicts and how to avoid them.

When use Kitsune-Re and enable bootloader spoofer if you change some values on post-fs-data.d exactly

ro.debuggeable 0 (default)
ro.adb.secure 1 (default)

if invert these values, and reboot if you try to join Develeper setting, the app Setting will crash and the system will be unstable, to avoid this problem you can use the following props:

You can rever this manual or disabling and enabling the bootloader spoofer.