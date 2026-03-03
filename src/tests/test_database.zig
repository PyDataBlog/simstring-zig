const std = @import("std");
const sim = @import("../root.zig");

fn containsId(ids: []const sim.StringId, target: sim.StringId) bool {
    for (ids) |id| {
        if (id == target) return true;
    }
    return false;
}

test "database insert and lookup separate by feature size" {
    const allocator = std.testing.allocator;

    var db = sim.HashDb.init(allocator, .{ .character = sim.CharacterNgrams.init(2, "$") });
    defer db.deinit();

    try db.insert("hello");
    try db.insert("hellos");

    try std.testing.expectEqualStrings("hello", db.getString(0).?);
    try std.testing.expectEqualStrings("hellos", db.getString(1).?);

    const f0 = db.getFeatures(0).?;
    const f1 = db.getFeatures(1).?;
    try std.testing.expect(f0.len != f1.len);

    const ids0 = db.lookupStrings(f0.len, f0[0]).?;
    try std.testing.expect(containsId(ids0, 0));
    try std.testing.expect(!containsId(ids0, 1));
}

test "database clear resets state" {
    const allocator = std.testing.allocator;

    var db = sim.HashDb.init(allocator, .{ .character = sim.CharacterNgrams.init(2, "$") });
    defer db.deinit();

    try db.insert("test");
    try std.testing.expectEqual(@as(usize, 1), db.totalStrings());
    try std.testing.expect(db.maxFeatureLen() > 0);

    db.clear();

    try std.testing.expectEqual(@as(usize, 0), db.totalStrings());
    try std.testing.expectEqual(@as(usize, 0), db.maxFeatureLen());
    try std.testing.expect(db.getString(0) == null);
    try std.testing.expect(db.getFeatures(0) == null);
    try std.testing.expectEqual(@as(usize, 0), db.interner.len());
}

test "database reserve and total strings" {
    const allocator = std.testing.allocator;

    var db = sim.HashDb.init(allocator, .{ .character = sim.CharacterNgrams.init(3, "$") });
    defer db.deinit();

    try db.reserveForWorkload(32, 16);
    try db.insert("foo");
    try db.insert("bar");
    try db.insert("baz");

    try std.testing.expectEqual(@as(usize, 3), db.totalStrings());
}
