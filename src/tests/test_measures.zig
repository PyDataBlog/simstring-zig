const std = @import("std");
const sim = @import("../root.zig");

fn approxEq(a: f64, b: f64) bool {
    return @abs(a - b) < 1e-9;
}

test "measure formulas" {
    const allocator = std.testing.allocator;

    var db = sim.HashDb.init(allocator, .{ .character = sim.CharacterNgrams.init(2, "$") });
    defer db.deinit();
    try db.insert("123456789");

    try std.testing.expectEqual(@as(usize, 5), sim.Measure.cosine.minFeatureSize(5, 1.0));
    try std.testing.expectEqual(@as(usize, 2), sim.Measure.cosine.minFeatureSize(5, 0.5));
    try std.testing.expectEqual(@as(usize, 5), sim.Measure.cosine.maxFeatureSize(5, 1.0, &db));
    try std.testing.expectEqual(@as(usize, 10), sim.Measure.cosine.maxFeatureSize(5, 0.5, &db));
}

test "measure similarity scores" {
    const x: [3]sim.FeatureId = .{ 1, 2, 3 };
    const y: [4]sim.FeatureId = .{ 1, 2, 4, 5 };

    try std.testing.expect(approxEq(0.5773502691896258, sim.Measure.cosine.similarity(&x, &y)));
    try std.testing.expect(approxEq(0.5714285714285714, sim.Measure.dice.similarity(&x, &y)));
    try std.testing.expect(approxEq(0.4, sim.Measure.jaccard.similarity(&x, &y)));
    try std.testing.expect(approxEq(2.0 / 3.0, sim.Measure.overlap.similarity(&x, &y)));
}

test "exact match similarity" {
    const x: [3]sim.FeatureId = .{ 1, 2, 3 };
    const y: [3]sim.FeatureId = .{ 1, 2, 3 };
    const z: [3]sim.FeatureId = .{ 1, 2, 4 };

    try std.testing.expect(approxEq(1.0, sim.Measure.exact_match.similarity(&x, &y)));
    try std.testing.expect(approxEq(0.0, sim.Measure.exact_match.similarity(&x, &z)));
}
