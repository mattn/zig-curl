# zig-curl

cURL binding for Zig

## Usage

```zig
var allocator = std.heap.page_allocator;
var f = struct {
    fn f(data: []const u8) anyerror!usize {
        try std.io.getStdOut().writeAll(data);
        return data.len;
    }
}.f;
var res = try curl.get("https://google.com/", .{ .allocator = allocator, .cb = f });
if (res != 0) {
    var msg = try curl.strerrorAlloc(allocator, res);
    defer allocator.free(msg);
    std.log.warn("{s}", .{msg});
}
```

## Requirements

* libcurl

## Installation

```
$ zig build
```

## Link to zig-curl

add following function into your build.zig.

```zig
fn linkToCurl(step: *std.build.LibExeObjStep) void {
    var libs = if (builtin.os.tag == .windows) [_][]const u8{ "c", "curl", "bcrypt", "crypto", "crypt32", "ws2_32", "wldap32", "ssl", "psl", "iconv", "idn2", "unistring", "z", "zstd", "nghttp2", "ssh2", "brotlienc", "brotlidec", "brotlicommon" } else [_][]const u8{ "c", "curl" };
    for (libs) |i| {
        step.linkSystemLibrary(i);
    }
    if (builtin.os.tag == .linux) {
        step.linkSystemLibraryNeeded("libcurl");
    }
    if (builtin.os.tag == .windows) {
        step.include_dirs.append(.{ .raw_path = "c:/msys64/mingw64/include" }) catch unreachable;
        step.lib_paths.append("c:/msys64/mingw64/lib") catch unreachable;
    }
}
```

Then, call for the step.

```zig
const exe = b.addExecutable("zig-curl-example", "src/main.zig");
exe.setTarget(target);
exe.setBuildMode(mode);
pkgs.addAllTo(exe);
linkToCurl(exe); // DO THIS
exe.install();
```

## License

MIT

## Author

Yasuhiro Matsumoto (a.k.a. mattn)
