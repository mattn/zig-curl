const std = @import("std");
const c = @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cInclude("curl/curl.h");
    @cInclude("string.h");
});
const testing = std.testing;

const func = fn (context, []const u8) anyerror!usize;

pub const context = struct {
    allocator: std.mem.Allocator,
    cb: func,
    headers: ?*headers = null,
    body: ?*[]const u8 = null,
    timeout: i32 = -1,
    sslVerify: bool = true,
};

pub const header = struct {
    name: []const u8,
    value: []const u8,
};

pub const headers = std.ArrayList(header);

fn writeFn(ptr: [*]const u8, size: usize, nmemb: usize, userp: *context) usize {
    const resp = ptr[0 .. size * nmemb];
    const ctx = userp.*;
    return ctx.cb(ctx, resp) catch 0;
}

pub fn request(method: []const u8, url: []const u8, ctx: context) !u32 {
    var curl: ?*c.CURL = undefined;
    var res: c.CURLcode = undefined;
    curl = c.curl_easy_init();
    if (curl == null) {
        return 0;
    }
    defer c.curl_easy_cleanup(curl);
    if (std.mem.eql(u8, method, "POST")) {
        _ = c.curl_easy_setopt(curl, @bitCast(c_uint, c.CURLOPT_POST), @as(c_long, 1));
    } else if (!std.mem.eql(u8, method, "GET")) {
        _ = c.curl_easy_setopt(curl, @bitCast(c_uint, c.CURLOPT_CUSTOMREQUEST), @ptrCast([*]const u8, method));
    }
    _ = c.curl_easy_setopt(curl, @bitCast(c_uint, c.CURLOPT_URL), @ptrCast([*]const u8, url));
    _ = c.curl_easy_setopt(curl, @bitCast(c_uint, c.CURLOPT_CAINFO), "c:/msys64/usr/ssl/certs/ca-bundle.crt");
    _ = c.curl_easy_setopt(curl, @bitCast(c_uint, c.CURLOPT_FOLLOWLOCATION), @as(c_long, 1));
    _ = c.curl_easy_setopt(curl, @bitCast(c_uint, c.CURLOPT_WRITEFUNCTION), writeFn);
    _ = c.curl_easy_setopt(curl, @bitCast(c_uint, c.CURLOPT_WRITEDATA), ctx);
    if (ctx.headers != null) {
        var headerlist: *c.curl_slist = undefined;
        for (ctx.headers.?.items) |he| {
            var bytes = std.ArrayList(u8).init(ctx.allocator);
            defer bytes.deinit();
            try bytes.writer().print("{s}: {s}", .{ he.name, he.value });
            headerlist = c.curl_slist_append(headerlist, @ptrCast([*]const u8, bytes.items));
        }
        _ = c.curl_easy_setopt(curl, c.CURLOPT_HTTPHEADER, headerlist);
    }
    if (ctx.body != null) {
        _ = c.curl_easy_setopt(curl, @bitCast(c_uint, c.CURLOPT_POST), @as(c_long, 1));
        _ = c.curl_easy_setopt(curl, @bitCast(c_uint, c.CURLOPT_POSTFIELDS), @ptrCast([*]const u8, ctx.body));
    }
    res = c.curl_easy_perform(curl);
    return @as(u32, res);
}

pub fn put(url: []const u8, ctx: context) !u32 {
    return request("PUT", url, ctx);
}

pub fn patch(url: []const u8, ctx: context) !u32 {
    return request("PATCH", url, ctx);
}

pub fn post(url: []const u8, ctx: context) !u32 {
    return request("POST", url, ctx);
}

pub fn delete(url: []const u8, ctx: context) !u32 {
    return request("DELETE", url, ctx);
}

pub fn get(url: []const u8, ctx: context) !u32 {
    return request("GET", url, ctx);
}

pub fn strerrorAlloc(allocator: std.mem.Allocator, res: u32) ![]const u8 {
    const msg = c.curl_easy_strerror(res);
    const len = c.strlen(msg);
    var mem = try allocator.alloc(u8, len + 1);
    var i: usize = 0;
    while (i <= len) : (i += 1) {
        mem[i] = msg[i];
    }
    return mem;
}

test "basic test" {
    var allocator = std.heap.page_allocator;
    var f = struct {
        fn f(_: context, resp: []const u8) anyerror!usize {
            try std.io.getStdOut().writeAll(resp);
            return resp.len;
        }
    }.f;
    var res = try get("https://google.com/", .{ .allocator = allocator, .cb = f });
    try std.testing.expectEqual(@as(u32, 0), res);
}
