const std = @import("std");
const curl = @import("curl");

pub fn main() anyerror!void {
    var allocator = std.heap.page_allocator;

    var cainfo = try std.process.getEnvVarOwned(allocator, "CURL_CA_BUNDLE");
    defer allocator.free(cainfo);

    var f = struct {
        fn f(data: []const u8) anyerror!usize {
            try std.io.getStdOut().writeAll(data);
            return data.len;
        }
    }.f;

    var req = curl.request{
        .allocator = allocator,
        .cb = f,
        .sslVerify = true,
        .cainfo = cainfo,
    };
    var res = try curl.get("https://google.com/", req);
    if (res != 0) {
        var msg = try curl.strerrorAlloc(allocator, res);
        defer allocator.free(msg);
        std.log.warn("{s}", .{msg});
    }
}
