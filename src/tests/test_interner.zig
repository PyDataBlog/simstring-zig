const std = @import("std");
const sim = @import("../root.zig");

test "raw ascii interning is consistent across ascii and generic paths" {
    const allocator = std.testing.allocator;

    var interner = sim.FeatureInterner.init(allocator);
    defer interner.deinit();

    const raw = "hello";
    const id_a = try interner.getOrInternRaw(raw);
    const id_b = try interner.getOrInternRawAscii(raw);
    const id_c = try interner.getOrInternRaw(raw);

    try std.testing.expectEqual(id_a, id_b);
    try std.testing.expectEqual(id_a, id_c);
}

test "raw unicode interning falls back correctly" {
    const allocator = std.testing.allocator;

    var interner = sim.FeatureInterner.init(allocator);
    defer interner.deinit();

    const raw = "你好";
    const id_a = try interner.getOrInternRawAscii(raw);
    const id_b = try interner.getOrInternRaw(raw);

    try std.testing.expectEqual(id_a, id_b);
}

test "counted feature ids are stable per raw id and occurrence" {
    const allocator = std.testing.allocator;

    var interner = sim.FeatureInterner.init(allocator);
    defer interner.deinit();

    const raw_id = try interner.getOrInternRaw("ab");
    const f1 = try interner.getOrInternCounted(raw_id, 1);
    const f1_again = try interner.getOrInternCounted(raw_id, 1);
    const f2 = try interner.getOrInternCounted(raw_id, 2);

    try std.testing.expectEqual(f1, f1_again);
    try std.testing.expect(f2 != f1);
}
