const std = @import("std");
const interner_mod = @import("../core/interner.zig");
const types = @import("../core/types.zig");
const utils = @import("../core/utils.zig");

pub const CharacterNgrams = struct {
    n: usize = 2,
    endmarker: []const u8 = "$",

    pub fn init(n: usize, endmarker: []const u8) CharacterNgrams {
        return .{ .n = n, .endmarker = endmarker };
    }

    pub fn features(
        self: CharacterNgrams,
        allocator: std.mem.Allocator,
        text: []const u8,
        interner: *interner_mod.FeatureInterner,
    ) ![]types.FeatureId {
        if (self.n == 0) {
            return allocator.alloc(types.FeatureId, 0);
        }

        if (self.endmarker.len == 1 and utils.isAsciiSlice(text)) {
            return self.featuresAscii(allocator, text, interner);
        }

        var arena_impl = std.heap.ArenaAllocator.init(allocator);
        defer arena_impl.deinit();
        const arena = arena_impl.allocator();

        var marker_cps: std.ArrayList(u21) = .empty;
        defer marker_cps.deinit(arena);
        try utils.appendCodepoints(&marker_cps, arena, self.endmarker);

        var text_cps: std.ArrayList(u21) = .empty;
        defer text_cps.deinit(arena);
        try utils.appendCodepoints(&text_cps, arena, text);

        const padding_len = self.n -| 1;
        const marker_repeat_len = marker_cps.items.len * padding_len;

        var all_cps = try std.ArrayList(u21).initCapacity(
            arena,
            marker_repeat_len + text_cps.items.len + marker_repeat_len,
        );
        defer all_cps.deinit(arena);

        for (0..padding_len) |_| {
            try all_cps.appendSlice(arena, marker_cps.items);
        }
        try all_cps.appendSlice(arena, text_cps.items);
        for (0..padding_len) |_| {
            try all_cps.appendSlice(arena, marker_cps.items);
        }

        if (all_cps.items.len < self.n) {
            return allocator.alloc(types.FeatureId, 0);
        }

        var ngram_buffer: std.ArrayList(u8) = .empty;
        defer ngram_buffer.deinit(arena);

        const windows = all_cps.items.len - self.n + 1;

        var counter = std.AutoHashMap(types.RawFeatureId, usize).init(arena);
        defer counter.deinit();

        var feature_ids = try std.ArrayList(types.FeatureId).initCapacity(allocator, windows);
        defer feature_ids.deinit(allocator);

        for (0..windows) |start| {
            ngram_buffer.clearRetainingCapacity();
            const window = all_cps.items[start .. start + self.n];
            for (window) |cp| {
                var buf: [4]u8 = undefined;
                const len = try std.unicode.utf8Encode(cp, &buf);
                try ngram_buffer.appendSlice(arena, buf[0..len]);
            }
            const raw_id = try interner.getOrInternRaw(ngram_buffer.items);

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

    fn featuresAscii(
        self: CharacterNgrams,
        allocator: std.mem.Allocator,
        text: []const u8,
        interner: *interner_mod.FeatureInterner,
    ) ![]types.FeatureId {
        const padding_len = self.n -| 1;
        const total_len = text.len + 2 * padding_len;

        if (total_len < self.n) {
            return allocator.alloc(types.FeatureId, 0);
        }

        const windows = total_len - self.n + 1;

        var feature_ids = try std.ArrayList(types.FeatureId).initCapacity(allocator, windows);
        defer feature_ids.deinit(allocator);

        var raw_counts = try std.ArrayList(types.RawCount).initCapacity(allocator, windows);
        defer raw_counts.deinit(allocator);

        var ngram_buf = try allocator.alloc(u8, self.n);
        defer allocator.free(ngram_buf);

        const marker_byte = self.endmarker[0];

        for (0..windows) |start| {
            for (0..self.n) |j| {
                const idx = start + j;
                ngram_buf[j] = if (idx < padding_len)
                    marker_byte
                else if (idx < padding_len + text.len)
                    text[idx - padding_len]
                else
                    marker_byte;
            }

            const raw_id = try interner.getOrInternRawAscii(ngram_buf);
            var occurrence: usize = 1;
            var found = false;
            for (raw_counts.items) |*entry| {
                if (entry.raw_id == raw_id) {
                    entry.count += 1;
                    occurrence = entry.count;
                    found = true;
                    break;
                }
            }
            if (!found) {
                raw_counts.appendAssumeCapacity(.{ .raw_id = raw_id, .count = 1 });
            }

            const feature_id = try interner.getOrInternCounted(raw_id, occurrence);
            feature_ids.appendAssumeCapacity(feature_id);
        }

        std.sort.heap(types.FeatureId, feature_ids.items, {}, std.sort.asc(types.FeatureId));
        return feature_ids.toOwnedSlice(allocator);
    }
};
