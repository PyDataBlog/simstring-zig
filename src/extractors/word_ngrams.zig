const std = @import("std");
const interner_mod = @import("../core/interner.zig");
const types = @import("../core/types.zig");

pub const WordNgrams = struct {
    n: usize = 2,
    splitter: []const u8 = " ",
    padder: []const u8 = " ",

    pub fn init(n: usize, splitter: []const u8, padder: []const u8) WordNgrams {
        return .{ .n = n, .splitter = splitter, .padder = padder };
    }

    pub fn features(
        self: WordNgrams,
        allocator: std.mem.Allocator,
        text: []const u8,
        interner: *interner_mod.FeatureInterner,
    ) ![]types.FeatureId {
        if (self.n == 0) {
            return allocator.alloc(types.FeatureId, 0);
        }

        var arena_impl = std.heap.ArenaAllocator.init(allocator);
        defer arena_impl.deinit();
        const arena = arena_impl.allocator();

        var tokens: std.ArrayList([]const u8) = .empty;
        defer tokens.deinit(arena);

        if (self.splitter.len == 0) {
            var view = std.unicode.Utf8View.init(text) catch return types.SimstringError.InvalidUtf8;
            var it = view.iterator();
            while (it.nextCodepoint()) |cp| {
                var bytes: std.ArrayList(u8) = .empty;
                defer bytes.deinit(arena);
                var utf8_buf: [4]u8 = undefined;
                const len = try std.unicode.utf8Encode(cp, &utf8_buf);
                try bytes.appendSlice(arena, utf8_buf[0..len]);
                const dup = try arena.dupe(u8, bytes.items);
                try tokens.append(arena, dup);
            }
        } else {
            var split_it = std.mem.splitSequence(u8, text, self.splitter);
            while (split_it.next()) |token| {
                if (token.len == 0) continue;
                try tokens.append(arena, token);
            }
        }

        var padded_tokens: std.ArrayList([]const u8) = .empty;
        defer padded_tokens.deinit(arena);
        try padded_tokens.ensureTotalCapacity(arena, tokens.items.len + 2);
        try padded_tokens.append(arena, self.padder);
        try padded_tokens.appendSlice(arena, tokens.items);
        try padded_tokens.append(arena, self.padder);

        if (padded_tokens.items.len < self.n) {
            return allocator.alloc(types.FeatureId, 0);
        }

        const windows = padded_tokens.items.len - self.n + 1;

        var counter = std.AutoHashMap(types.RawFeatureId, usize).init(arena);
        defer counter.deinit();

        var feature_ids = try std.ArrayList(types.FeatureId).initCapacity(allocator, windows);
        defer feature_ids.deinit(allocator);

        var join_buffer: std.ArrayList(u8) = .empty;
        defer join_buffer.deinit(arena);

        for (0..windows) |start| {
            join_buffer.clearRetainingCapacity();
            const window = padded_tokens.items[start .. start + self.n];
            for (window, 0..) |token, idx| {
                if (idx > 0) {
                    try join_buffer.append(arena, ' ');
                }
                try join_buffer.appendSlice(arena, token);
            }

            const raw_id = try interner.getOrInternRaw(join_buffer.items);
            const count_entry = try counter.getOrPut(raw_id);
            if (!count_entry.found_existing) {
                count_entry.value_ptr.* = 0;
            }
            count_entry.value_ptr.* += 1;

            const feature_id = try interner.getOrInternCounted(raw_id, count_entry.value_ptr.*);
            feature_ids.appendAssumeCapacity(feature_id);
        }

        std.sort.heap(types.FeatureId, feature_ids.items, {}, std.sort.asc(types.FeatureId));
        return feature_ids.toOwnedSlice(allocator);
    }
};
