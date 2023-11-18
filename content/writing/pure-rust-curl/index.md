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

The inline assembly being called looks something like this. If your interested you can checkout [the actual implementation](https://github.com/LiamGallagher737/pure_rust_curl/blob/014eaf3430cf7b872754425474e18c0bfa8af553/syscalls.rs) up to this point.

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

This is where things started getting a lot more difficult.

## References

- [A Freestanding Rust Binary][1]
- [Rust by Example - Inline Assembly][2]
- [Linux System Call Table for x86_64][3]
- [Direct Linux Syscalls from Rust][4]
- [Assembly Language in 100 Seconds][5]

[0]: https://github.com/LiamGallagher737/pure_rust_curl
[1]: https://os.phil-opp.com/freestanding-rust-binary/
[2]: https://doc.rust-lang.org/rust-by-example/unsafe/asm.html
[3]: https://blog.rchapman.org/posts/Linux_System_Call_Table_for_x86_64/
[4]: https://github.com/phip1611/direct-syscalls-linux-from-rust/blob/e3474487b576ec786f6cae869aa3bcb3b4006a21/src/main.rs
[5]: https://www.youtube.com/watch?v=4gwYkEK0gOk
