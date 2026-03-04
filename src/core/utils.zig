const std = @import("std");
const types = @import("types.zig");

pub fn appendCodepoints(
    list: *std.ArrayList(u21),
    allocator: std.mem.Allocator,
    text: []const u8,
) !void {
    var view = std.unicode.Utf8View.init(text) catch return types.SimstringError.InvalidUtf8;
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| {
        try list.append(allocator, cp);
    }
}

pub fn packAsciiRawKey(bytes: []const u8) ?u128 {
    if (bytes.len > 15) return null;
    var key = @as(u128, @intCast(bytes.len)) << 120;
    const Shift = std.math.Log2Int(u128);
    for (bytes, 0..) |b, i| {
        key |= @as(u128, b) << @as(Shift, @intCast(i * 8));
    }
    return key;
}

pub fn isAsciiSlice(text: []const u8) bool {
    for (text) |b| {
        if (!std.ascii.isAscii(b)) return false;
    }
    return true;
}
