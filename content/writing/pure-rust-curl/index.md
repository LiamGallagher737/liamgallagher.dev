+++
title = "Curl in pure Rust"
description = "A curl program written in pure Rust with no external dependencies"
date = 2023-11-18
draft = true
+++

## The goal of the project

My goal for this was to create a much simper version of curl with the challenge of not being allowed to use any external dependencies. This meant I'd have to communicate directly with the linux kernel.

## Making a freestanding binary

The first step was to get a simple `"Hello, world!"` program running without depending on anything. Getting the program to run was made really easy by [Philipp Oppermann's guide][1]. Getting the program to print something was a little more challenging, but after watching [Fireship's video on assembly][5] and finding [this GitHub repo][4] I finally got `"Hello, world!"` printing. To make syscalls easier to work with I created a `syscall!` macro and made some small helper functions wrapping it. Here's an example of using these syscall functions.

```rs
fn print(msg: &str) -> i64 {
    syscalls::write(
        SysFd::Stdout,
        msg.as_ptr(),
        msg.len() as u64
    )
}
```

The inline assembly being called looks something like this. If your interested you can checkout [the actual implementation up to this point](https://github.com/LiamGallagher737/pure_rust_curl/blob/014eaf3430cf7b872754425474e18c0bfa8af553/syscalls.rs).

```rs
let msg = "Hello, world!\n";
asm!(
    "syscall",
    in("rax") 1, // 1 for sys_write
    in("rdi") 1, // 1 for stdout
    in("rsi") msg.as_ptr(),
    in("rdx") msg.len(),
);
```

## Command line arguments

This is where things started getting a lot more difficult. It should've been as simple as loading argc from the `rdi` register and argv from the `rsi` register, but this turned out not to be the case. After trying many different options and getting many segfaults I eventually landed on a [stack overflow answer][6] which inspected the registers and stack with gdb. Doing the same for my app was pretty simple, add the `-g` flag when compiling then run it in gdb.

```sh
(gdb) info registers
rsi            0x0                 0
rdi            0x0                 0
```

```sh
(gdb) x/2g $sp
0x7fffffffd8a0: 1       140737488345857
```

This shows a arguments count of 1 which makes sense as I didn't pass any extra arguments. Inspecting the following address got me this.

```sh
(gdb) x 140737488345857
0x7fffffffdb01: 0x502f662f746e6d2f
```

This is when all my troubles started making sense. I thought argv pointed to an array of pointers each of which pointed to the start of an argument. But the address didn't point to another address, so I tried printing it as a string.

```sh
(gdb) x /s 140737488345857
0x7fffffffdb01: "/mnt/f/Projects/pure_rust_curl/main"
```

That's the first argument, to make sure I properly understood it now I tested with some more arguments.

## References

- [A Freestanding Rust Binary][1]
- [Rust by Example - Inline Assembly][2]
- [Linux System Call Table for x86_64][3]
- [Direct Linux Syscalls from Rust][4]
- [Assembly Language in 100 Seconds][5]
- [Inspecting with GDB][6]
- [GDB Tutorial - A Walkthrough with Examples][7]

[0]: https://github.com/LiamGallagher737/pure_rust_curl
[1]: https://os.phil-opp.com/freestanding-rust-binary/
[2]: https://doc.rust-lang.org/rust-by-example/unsafe/asm.html
[3]: https://blog.rchapman.org/posts/Linux_System_Call_Table_for_x86_64/
[4]: https://github.com/phip1611/direct-syscalls-linux-from-rust/blob/e3474487b576ec786f6cae869aa3bcb3b4006a21/src/main.rs
[5]: https://www.youtube.com/watch?v=4gwYkEK0gOk
[6]: https://stackoverflow.com/a/38154828
[7]: https://www.cs.umd.edu/~srhuang/teaching/cmsc212/gdb-tutorial-handout.pdf
