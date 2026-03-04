const std = @import("std");
const sim = @import("../root.zig");

fn approxEq(a: f64, b: f64) bool {
    return @abs(a - b) < 1e-9;
}

test "cosine search basic" {
    const allocator = std.testing.allocator;

    var db = sim.HashDb.init(allocator, .{ .character = sim.CharacterNgrams.init(2, "$") });
    defer db.deinit();

    try db.insert("foo");
    try db.insert("bar");
    try db.insert("fooo");

    var searcher = sim.Searcher.init(allocator, &db, .cosine);
    const ranked = try searcher.rankedSearch("foo", 0.8);
    defer allocator.free(ranked);

    try std.testing.expectEqual(@as(usize, 2), ranked.len);
    try std.testing.expectEqualStrings("foo", ranked[0].text);
    try std.testing.expect(approxEq(1.0, ranked[0].score));
    try std.testing.expectEqualStrings("fooo", ranked[1].text);
    try std.testing.expect(approxEq(0.8944271909999159, ranked[1].score));
}

test "unranked search sorted" {
    const allocator = std.testing.allocator;

    var db = sim.HashDb.init(allocator, .{ .character = sim.CharacterNgrams.init(2, "$") });
    defer db.deinit();

    try db.insert("fooo");
    try db.insert("bar");
    try db.insert("foo");

    var searcher = sim.Searcher.init(allocator, &db, .cosine);
    const matches = try searcher.search("foo", 0.8);
    defer allocator.free(matches);

    try std.testing.expectEqual(@as(usize, 2), matches.len);
    try std.testing.expectEqualStrings("foo", matches[0]);
    try std.testing.expectEqualStrings("fooo", matches[1]);
}

test "threshold validation" {
    const allocator = std.testing.allocator;

    var db = sim.HashDb.init(allocator, .{ .character = sim.CharacterNgrams.init(2, "$") });
    defer db.deinit();

    try db.insert("foo");

    var searcher = sim.Searcher.init(allocator, &db, .cosine);
    try std.testing.expectError(sim.SimstringError.InvalidThreshold, searcher.search("foo", 0.0));
    try std.testing.expectError(sim.SimstringError.InvalidThreshold, searcher.search("foo", 1.1));
}

test "unicode handling" {
    const allocator = std.testing.allocator;

    var db = sim.HashDb.init(allocator, .{ .character = sim.CharacterNgrams.init(2, "$") });
    defer db.deinit();

    try db.insert("🦀🚀");
    try db.insert("你好世界");
    try db.insert("hello world 🌍");

    var searcher = sim.Searcher.init(allocator, &db, .cosine);

    const emoji = try searcher.search("🦀🚀", 1.0);
    defer allocator.free(emoji);
    try std.testing.expectEqual(@as(usize, 1), emoji.len);
    try std.testing.expectEqualStrings("🦀🚀", emoji[0]);

    const cjk = try searcher.search("你好世界", 1.0);
    defer allocator.free(cjk);
    try std.testing.expectEqual(@as(usize, 1), cjk.len);
    try std.testing.expectEqualStrings("你好世界", cjk[0]);

    const mixed = try searcher.search("hello 🌍", 0.5);
    defer allocator.free(mixed);
    try std.testing.expectEqual(@as(usize, 1), mixed.len);
    try std.testing.expectEqualStrings("hello world 🌍", mixed[0]);
}

test "ascii and unicode extraction paths interoperate" {
    const allocator = std.testing.allocator;

    var db = sim.HashDb.init(allocator, .{ .character = sim.CharacterNgrams.init(2, "$") });
    defer db.deinit();

    try db.insert("hello");
    try db.insert("world");

    var searcher = sim.Searcher.init(allocator, &db, .cosine);
    const mixed = try searcher.search("hello🌍", 0.2);
    defer allocator.free(mixed);

    try std.testing.expectEqual(@as(usize, 1), mixed.len);
    try std.testing.expectEqualStrings("hello", mixed[0]);
}

test "search parity with brute force" {
    const allocator = std.testing.allocator;
    const corpus = [_][]const u8{
        "foo",
        "fooo",
        "food",
        "fool",
        "bar",
        "baz",
        "你好",
        "hello world",
        "hello 🌍",
        "🦀🚀",
    };

    var db = sim.HashDb.init(allocator, .{ .character = sim.CharacterNgrams.init(2, "$") });
    defer db.deinit();
    for (corpus) |s| {
        try db.insert(s);
    }

    const queries = [_][]const u8{ "foo", "fo", "hello 🌍", "你好", "🦀", "qux" };
    const thresholds = [_]f64{ 0.6, 0.8, 0.9 };
    const all_measures = [_]sim.Measure{ .cosine, .dice, .jaccard, .overlap, .exact_match };

    for (all_measures) |measure| {
        var searcher = sim.Searcher.init(allocator, &db, measure);

        for (queries) |query| {
            for (thresholds) |alpha| {
                const indexed = try searcher.search(query, alpha);
                defer allocator.free(indexed);

                const query_features = try db.extractor.features(allocator, query, &db.interner);
                defer allocator.free(query_features);

                var brute: std.ArrayList([]const u8) = .empty;
                defer brute.deinit(allocator);

                for (0..db.totalStrings()) |id| {
                    const text = db.getString(id).?;
                    const features = db.getFeatures(id).?;
                    const score = measure.similarity(query_features, features);
                    if (score >= alpha) {
                        try brute.append(allocator, text);
                    }
                }

                std.sort.heap([]const u8, brute.items, {}, struct {
                    fn lt(_: void, a: []const u8, b: []const u8) bool {
                        return std.mem.order(u8, a, b) == .lt;
                    }
                }.lt);
                try std.testing.expectEqual(@as(usize, brute.items.len), indexed.len);
                for (indexed, brute.items) |a, b| {
                    try std.testing.expectEqualStrings(b, a);
                }
            }
        }
    }
}
