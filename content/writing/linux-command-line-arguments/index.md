+++
title = "Linux command line args with no runtime"
description = "Getting command line arguments in Linux x86_64 without a runtime"
date = 2023-11-19
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

## Getting these values in Rust

Now I know where they are, accessing them from Rust shouldn't be to hard, right? It should be as easy as getting the pointer to the argument count and then using some pointer math to get the values. Since the argument count is at the top of the stack all I need is the stack pointer which is in the `rsp` register.

```rs
pub unsafe extern "C" fn _start() {
    let argc_ptr: *const usize;
    asm!("mov {}, rsp", out(reg) argc_ptr);
    let first_arg = *argc_ptr.add(8);
    // ...
}
```

```sh
28      pub unsafe extern "C" fn _start() {
(gdb) info registers rsp
rsp            0x7fffffffd8a0      0x7fffffffd8a0 # Correct value
(gdb) step
Breakpoint 1, main::_start () at main.rs:31
31          asm!("mov {}, rsp", out(reg) argc_ptr);
(gdb) step
32          let first_arg = *argc_ptr.add(8);
(gdb) info local
argc_ptr = 0x7fffffffd878 # Incorrect value
```

However when stepping though in gdb we can see that the initial `rsp` value is not the same as what ends up in the local variable.

```sh
(gdb) x/8g $sp
0x7fffffffd878: 93824992235552  140737488345208
0x7fffffffd888: 0       0
0x7fffffffd898: 140737354019530 1
0x7fffffffd8a8: 140737488345857 0
```
This seems to be because stuff has been added to the stack after the start of the `_start` function but before my first line. TO try and get the original value I moved `rsp` in to `r8` instead of creating a local variable which I thought could be messing with things.

```rs
pub unsafe extern "C" fn _start() {
    asm!("mov r8, rsp");
}
```

```sh
28      pub unsafe extern "C" fn _start() {
(gdb) info registers rsp r8
rsp            0x7fffffffd8a0      0x7fffffffd8a0 # Correct value
r8             0x0                 0
(gdb) step

Breakpoint 1, main::_start () at main.rs:29
29          asm!("mov r8, rsp");
(gdb) info registers rsp r8
rsp            0x7fffffffd898      0x7fffffffd898 # Value changes
r8             0x0                 0
(gdb) step
34          syscalls::exit(0);
(gdb) info registers rsp r8
rsp            0x7fffffffd898      0x7fffffffd898
r8             0x7fffffffd898      140737488345240 # Wrong value
```

Here `r8` should be `0x7fffffffd8a0` but for some reason in between the app starting and moving `rsp` in to `r8`, stuff is being added to the stack, therefore changing `rsp`.

<div id="weird-instruction" aria-hidden></div>

```asm
_start:
    pushq    %rax ; Not my instruction
    #APP
    movq    %rsp, %r8 ; My instruction
    #NO_APP
    xorl    %eax, %eax
```

The assembly emitted by rustc shows some other instruction being ran before mine. The value of the `rax` register is being pushed on to the stack. Remember this for later.

```sh
(gdb) info registers rax
rax            0x1c                28
(gdb) step
29          asm!("mov r8, rsp");
(gdb) x/8g $sp
0x7fffffffd898: 28      1
0x7fffffffd8a8: 140737488345857 0
0x7fffffffd8b8: 140737488345893 140737488345909
0x7fffffffd8c8: 140737488345933 140737488345956
```

Going back to gdb shows that it is in fact the `rax` register being push onto the stack.

```sh
(gdb) x/s 140737488345857
0x7fffffffdb01: "/mnt/f/Projects/pure_rust_curl/main"
```

Then printing the 3rd element as a string shows that it is just the single 28 from `rax` being pushed. This means I should be able offset the pointer by 8 bytes to get the argument count I want.

```sh
(gdb) info registers rsp r8
rsp            0x7fffffffd8a0      0x7fffffffd8a0
r8             0x0                 0
# ...
(gdb) info registers rsp r8
rsp            0x7fffffffd878      0x7fffffffd878
r8             0x7fffffffd878      140737488345208
```

Not quite. The difference between the initial stack pointer (to argc) and the pointer being moved in to `r8` is 40 bytes, lucky for me, all I have to do is add some extra bytes.

```sh
(gdb) info locals
first_arg_ptr = 0x7fffffffd8a0
(gdb) x 0x7fffffffd8a0
0x7fffffffd8a0: 0x00000001 # Argument count
```

And there we have it. It only took 2 days.

```sh
(gdb) run hello world
# ...
(gdb) info locals
first_arg_ptr = 0x7fffffffd880
(gdb) x 0x7fffffffd880
0x7fffffffd880: 0x00000003
```

Just to make sure it works I tested adding some arguments and it worked like a charm.

## One last problem

Remember that [weird extra instruction](#weird-instruction) than runs before mine from earlier? It changes. This means the 40 byte offset I was doing also needs to be changed.

```asm,diff
_start:
-   pushq    %rax ; Previous not my instruction
+   subq    $24, %rsp ; New not my instruction
    #APP
    movq    %rsp, %r8 ; My first instruction
    #NO_APP
```

For some reason when I start adding logic like checking the value of argc and exiting if not enough arguments were provided, the compiler feels the need to change this instruction. According to the [x64 Cheat Sheet][3] this line allocates 24 bytes on the stack. After some more time in gdb I found the new offset was 88 bytes. By keeping the code in `_setup` to a minimum and moving everything else in to a separate `main` function I should't have to keep changing this offset, hopefully.

## The result

```sh
$ ./main https://google.com
https://google.com
```

My app can now repeat the users first argument back to them and even return a error if one is not provided. Truly a marvel of engineering. If you're interested go ahead and [checkout the amazing code](https://github.com/LiamGallagher737/pure_rust_curl/blob/5075639c071d3e86809aa32d2fb15a84e1f8d379/main.rs#L14-L45).

## References

- [Inspecting with GDB (StackOverflow)][1]
- [GDB x command][2]
- [x64 Cheat Sheet][3]

[0]: https://github.com/LiamGallagher737/pure_rust_curl
[1]: https://stackoverflow.com/a/38154828
[2]: https://visualgdb.com/gdbreference/commands/x
[3]: https://cs.brown.edu/courses/cs033/docs/guides/x64_cheatsheet.pdf
