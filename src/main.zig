const std = @import("std");
const c = @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cInclude("curl/curl.h");
    @cInclude("string.h");
});
const testing = std.testing;

const func = fn ([]const u8) anyerror!usize;

pub const context = struct {
    resp: response,
    curl: ?*c.CURL,
    cb: ?func,
};

pub const response = struct {
    allocator: std.mem.Allocator,
    status: c_long,
    headers: headers,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .status = 0,
            .headers = std.ArrayList(header).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.headers.items) |h| {
            self.allocator.free(h.name);
            self.allocator.free(h.value);
        }
        self.headers.deinit();
    }
};

pub const request = struct {
    allocator: std.mem.Allocator,
    cb: ?func = null,
    headers: ?*headers = null,
    body: ?*[]const u8 = null,
    timeout: i32 = -1,
    sslVerify: bool = true,
    cainfo: ?[]const u8 = null,
    response: ?*response = null,
};

pub const header = struct {
    name: []const u8,
    value: []const u8,
};

pub const headers = std.ArrayList(header);

fn headerFn(ptr: [*]const u8, size: usize, nmemb: usize, ctx: *context) usize {
    const data = ptr[0 .. size * nmemb];
    if (ctx.resp.status == 0) {
        _ = c.curl_easy_getinfo(ctx.curl, c.CURLINFO_RESPONSE_CODE, &ctx.resp.status);
    }
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        if (data[i] == ':') {
            var h: header = undefined;
            h.name = ctx.resp.allocator.dupe(u8, data[0..i]) catch unreachable;
            while (i < data.len and std.ascii.isSpace(data[i + 1])) : (i += 1) {}
            h.value = ctx.resp.allocator.dupe(u8, data[i..]) catch unreachable;
            ctx.resp.headers.append(h) catch unreachable;
            break;
        }
    }
    return size * nmemb;
}

fn writeFn(ptr: [*]const u8, size: usize, nmemb: usize, ctx: *context) usize {
    const data = ptr[0 .. size * nmemb];
    return ctx.cb.?(data) catch 0;
}

pub fn send(method: []const u8, url: []const u8, req: request) !u32 {
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

    if (req.sslVerify) {
        _ = c.curl_easy_setopt(curl, @bitCast(c_uint, c.CURLOPT_SSL_VERIFYPEER), @as(c_long, 1));
    }
    if (req.timeout >= 0) {
        _ = c.curl_easy_setopt(curl, @bitCast(c_uint, c.CURLOPT_TIMEOUT), @as(c_long, req.timeout));
    }
    if (req.cainfo != null) {
        _ = c.curl_easy_setopt(curl, @bitCast(c_uint, c.CURLOPT_CAINFO), req.cainfo.?);
    }

    var ctx: context = .{
        .resp = .{
            .allocator = req.allocator,
            .status = 0,
            .headers = headers.init(req.allocator),
        },
        .curl = curl,
        .cb = req.cb,
    };
    defer {
        if (req.response == null) {
            for (ctx.resp.headers.items) |h| {
                req.allocator.free(h.name);
                req.allocator.free(h.value);
            }
            ctx.resp.headers.deinit();
        } else {
            req.response.?.* = ctx.resp;
        }
    }
    _ = c.curl_easy_setopt(curl, @bitCast(c_uint, c.CURLOPT_URL), @ptrCast([*]const u8, url));
    _ = c.curl_easy_setopt(curl, @bitCast(c_uint, c.CURLOPT_FOLLOWLOCATION), @as(c_long, 1));
    _ = c.curl_easy_setopt(curl, @bitCast(c_uint, c.CURLOPT_HEADERFUNCTION), headerFn);
    _ = c.curl_easy_setopt(curl, @bitCast(c_uint, c.CURLOPT_HEADERDATA), &ctx);
    if (req.cb != null) {
        _ = c.curl_easy_setopt(curl, @bitCast(c_uint, c.CURLOPT_WRITEFUNCTION), writeFn);
        _ = c.curl_easy_setopt(curl, @bitCast(c_uint, c.CURLOPT_WRITEDATA), &ctx);
    }

    if (req.headers != null) {
        var headerlist: *c.curl_slist = undefined;
        for (req.headers.?.items) |he| {
            var bytes = std.ArrayList(u8).init(req.allocator);
            defer bytes.deinit();
            try bytes.writer().print("{s}: {s}", .{ he.name, he.value });
            headerlist = c.curl_slist_append(headerlist, @ptrCast([*]const u8, bytes.items));
        }
        _ = c.curl_easy_setopt(curl, c.CURLOPT_HTTPHEADER, headerlist);
        defer c.curl_slist_free_all(headerlist);
    }
    if (req.body != null) {
        _ = c.curl_easy_setopt(curl, @bitCast(c_uint, c.CURLOPT_POST), @as(c_long, 1));
        _ = c.curl_easy_setopt(curl, @bitCast(c_uint, c.CURLOPT_POSTFIELDS), @ptrCast([*]const u8, req.body));
    }
    res = c.curl_easy_perform(curl);
    return @as(u32, res);
}

pub fn put(url: []const u8, req: request) !u32 {
    return send("PUT", url, req);
}

pub fn patch(url: []const u8, req: request) !u32 {
    return send("PATCH", url, req);
}

pub fn post(url: []const u8, req: request) !u32 {
    return send("POST", url, req);
}

pub fn delete(url: []const u8, req: request) !u32 {
    return send("DELETE", url, req);
}

pub fn get(url: []const u8, req: request) !u32 {
    return send("GET", url, req);
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
    var allocator = std.testing.allocator;
    var f = struct {
        fn f(data: []const u8) anyerror!usize {
            try std.io.getStdOut().writeAll(data);
            return data.len;
        }
    }.f;

    var cainfo = try std.process.getEnvVarOwned(allocator, "CURL_CA_BUNDLE");
    defer allocator.free(cainfo);

    var req = request{
        .allocator = allocator,
        .sslVerify = true,
        .cainfo = cainfo,
    };
    var res = try get("http://google.com/", req);
    try std.testing.expectEqual(@as(u32, 0), res);

    req = request{
        .allocator = allocator,
        .cb = f,
        .sslVerify = true,
        .cainfo = cainfo,
    };
    res = try get("http://google.com/", req);
    try std.testing.expectEqual(@as(u32, 0), res);

    req = request{
        .allocator = allocator,
        .cb = f,
        .sslVerify = true,
        .cainfo = cainfo,
        .response = &response.init(allocator),
    };
    defer req.response.?.deinit();
    res = try get("http://google.com/", req);
    try std.testing.expectEqual(@as(u32, 0), res);
}
