+++
title = "Linux command line args with no runtime"
description = "Getting command line arguments in Linux x86_64 without a runtime"
date = 2023-11-19
draft = true
+++

I have been working on a [simple curl app in pure rust][0] with the challenge of not being allowed to use any external dependencies, this includes anything like the C runtime. One of the things this app needed to do is parse command line arguments so a url can be passed to it `curl http://google.com`.

## Where are they?

Most places I looked said argc would be in the `rdi` register and argv would be in the `rsi` register. But trying these resulted in endless segfaults, not exactly what I wanted. After more than a few hours of trying different registers and other ways of getting args I stumbled upon a [stack overflow answer][1] here they inspected the registers and stack using gdb.

## Inspecting with GDB

Getting gdb to work with rust wa as simple as building with the `-g` flag. After setting a breakpoint at `_start` and running I executed the following gdb commands.

```sh
(gdb) info registers
rsi            0x0                 0
rdi            0x0                 0
```

The registers `rsi` and `rdi` were both empty, this explains the segfaults I was getting as I was trying to dereference a null pointer. The [next command][2] prints the first 2 64-bit values on the stack.

```sh
(gdb) x/2g $sp
0x7fffffffd8a0: 1       140737488345857
```

This looked a lot more promising. I didn't pass any extra arguments when running it so a argument count of 1 is expected. The second value should then be the pointer to the array of pointers pointing to the arguments.

```sh
(gdb) x 140737488345857
0x7fffffffdb01: 0x502f662f746e6d2f
(gdb) x 0x502f662f746e6d2f
0x502f662f746e6d2f: Cannot access memory at address 0x502f662f746e6d2f
```

Turns out it wasn't a pointer. What if I try print it as a string?

```sh
(gdb) x/s 140737488345857
0x7fffffffdb01: "/mnt/f/Projects/pure_rust_curl/main"
```

Testing it with the arguments `hello` and `world` resulted in the following.

```sh
(gdb) x/5g $sp
0x7fffffffd880: 3       140737488345845
0x7fffffffd890: 140737488345881 140737488345887
0x7fffffffd8a0: 0
```

```sh
(gdb) x/s 140737488345845
0x7fffffffdaf5: "/mnt/f/Projects/pure_rust_curl/main"
(gdb) x/s 140737488345881
0x7fffffffdb19: "hello"
(gdb) x/s 140737488345887
0x7fffffffdb1f: "world"
```

That's what I wanted. The reason I was struggling so much at the start is when I tried loading argv from the stack I was treating it as a `char**` like the C runtime makes it. Every time I ended up dereferencing a null pointer. That way it's actually laid out is argc at the top of the stack followed by a number of pointers to the argument strings then a null pointer.

# Poking around

Looking a bit further seems to uncover the environment variables.

```sh
(gdb) x/6g $sp
0x7fffffffd8a0: 1       140737488345857
0x7fffffffd8b0: 0       140737488345893
0x7fffffffd8c0: 140737488345909 140737488345933
```

```sh
(gdb) x/s 140737488345893
0x7fffffffdb25: "SHELL=/bin/bash"
(gdb) x/s 140737488345909
0x7fffffffdb35: "WSL2_GUI_APPS_ENABLED=1"
(gdb) x/s 140737488345933
0x7fffffffdb4d: "WSL_DISTRO_NAME=Ubuntu"
```

## References

- [Inspecting with GDB (StackOverflow)][1]
- [GDB x command][2]

[0]: https://github.com/LiamGallagher737/pure_rust_curl
[1]: https://stackoverflow.com/a/38154828
[2]: https://visualgdb.com/gdbreference/commands/x
