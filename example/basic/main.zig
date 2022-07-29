const std = @import("std");
const curl = @import("curl");

pub fn main() anyerror!void {
    var allocator = std.heap.page_allocator;
    var f = struct {
        fn f(_: curl.context, resp: []const u8) anyerror!usize {
            try std.io.getStdOut().writeAll(resp);
            return resp.len;
        }
    }.f;
    var res = try curl.get("https://google.com/", .{ .allocator = allocator, .cb = f });
    if (res != 0) {
        var msg = try curl.strerrorAlloc(allocator, res);
        defer allocator.free(msg);
        std.log.warn("{s}", .{msg});
    }
}
