const std = @import("std");
const simstring = @import("simstring_zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var db = simstring.HashDb.init(allocator, .{ .character = simstring.CharacterNgrams.init(2, "$") });
    defer db.deinit();

    try db.insert("hello");
    try db.insert("help");
    try db.insert("halo");
    try db.insert("world");

    var searcher = simstring.Searcher.init(allocator, &db, .cosine);
    const ranked = try searcher.rankedSearch("hell", 0.5);
    defer allocator.free(ranked);

    for (ranked) |item| {
        std.debug.print("{s}\t{d:.6}\n", .{ item.text, item.score });
    }
}
