const std = @import("std");
const sim = @import("../root.zig");

test "character ngrams deterministic for same interner and input" {
    const allocator = std.testing.allocator;

    var interner = sim.FeatureInterner.init(allocator);
    defer interner.deinit();

    const extractor = sim.CharacterNgrams.init(2, "$");
    const a = try extractor.features(allocator, "abab", &interner);
    defer allocator.free(a);

    const b = try extractor.features(allocator, "abab", &interner);
    defer allocator.free(b);

    try std.testing.expectEqual(@as(usize, 5), a.len);
    try std.testing.expectEqualSlices(sim.FeatureId, a, b);
}

test "character ngrams handles unicode input" {
    const allocator = std.testing.allocator;

    var interner = sim.FeatureInterner.init(allocator);
    defer interner.deinit();

    const extractor = sim.CharacterNgrams.init(2, "$");
    const features = try extractor.features(allocator, "你好世界", &interner);
    defer allocator.free(features);

    try std.testing.expect(features.len > 0);
}

test "word ngrams basic extraction and n zero" {
    const allocator = std.testing.allocator;

    var interner = sim.FeatureInterner.init(allocator);
    defer interner.deinit();

    const extractor = sim.WordNgrams.init(2, " ", " ");
    const features = try extractor.features(allocator, "a b c", &interner);
    defer allocator.free(features);
    try std.testing.expectEqual(@as(usize, 4), features.len);

    const zero = sim.WordNgrams.init(0, " ", " ");
    const empty = try zero.features(allocator, "a b c", &interner);
    defer allocator.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
}

test "word ngrams splitter-empty uses utf8 codepoints" {
    const allocator = std.testing.allocator;

    var interner = sim.FeatureInterner.init(allocator);
    defer interner.deinit();

    const extractor = sim.WordNgrams.init(2, "", "#");
    const features = try extractor.features(allocator, "ab", &interner);
    defer allocator.free(features);
    try std.testing.expectEqual(@as(usize, 3), features.len);

    const invalid_utf8 = [_]u8{0xff};
    try std.testing.expectError(
        sim.SimstringError.InvalidUtf8,
        extractor.features(allocator, invalid_utf8[0..], &interner),
    );
}
