const std = @import("std");
const interner_mod = @import("../core/interner.zig");
const extractors = @import("../extractors/mod.zig");
const types = @import("../core/types.zig");
const utils = @import("../core/utils.zig");

const FeatureKey = struct {
    size: usize,
    feature: types.FeatureId,
};

pub const HashDb = struct {
    allocator: std.mem.Allocator,
    extractor: extractors.FeatureExtractor,
    interner: interner_mod.FeatureInterner,
    strings: std.ArrayList([]const u8),
    string_features: std.ArrayList([]types.FeatureId),
    feature_map: std.AutoHashMap(FeatureKey, std.ArrayList(types.StringId)),
    scratch_raw_counts: std.ArrayList(types.RawCount),
    scratch_feature_ids: std.ArrayList(types.FeatureId),
    scratch_ngram_buf: std.ArrayList(u8),
    max_feature_len_value: usize,

    pub fn init(allocator: std.mem.Allocator, extractor: extractors.FeatureExtractor) HashDb {
        return .{
            .allocator = allocator,
            .extractor = extractor,
            .interner = interner_mod.FeatureInterner.init(allocator),
            .strings = .empty,
            .string_features = .empty,
            .feature_map = std.AutoHashMap(FeatureKey, std.ArrayList(types.StringId)).init(allocator),
            .scratch_raw_counts = .empty,
            .scratch_feature_ids = .empty,
            .scratch_ngram_buf = .empty,
            .max_feature_len_value = 0,
        };
    }

    pub fn deinit(self: *HashDb) void {
        self.clear();
        self.strings.deinit(self.allocator);
        self.string_features.deinit(self.allocator);
        var postings_it = self.feature_map.valueIterator();
        while (postings_it.next()) |posting_list| {
            posting_list.deinit(self.allocator);
        }
        self.feature_map.deinit();
        self.scratch_raw_counts.deinit(self.allocator);
        self.scratch_feature_ids.deinit(self.allocator);
        self.scratch_ngram_buf.deinit(self.allocator);
        self.interner.deinit();
    }

    pub fn clear(self: *HashDb) void {
        for (self.strings.items) |text| {
            self.allocator.free(text);
        }
        self.strings.clearRetainingCapacity();

        for (self.string_features.items) |features| {
            self.allocator.free(features);
        }
        self.string_features.clearRetainingCapacity();

        var map_it = self.feature_map.valueIterator();
        while (map_it.next()) |posting_list| {
            posting_list.deinit(self.allocator);
        }
        self.feature_map.clearRetainingCapacity();

        self.interner.clear();
        self.scratch_raw_counts.clearRetainingCapacity();
        self.scratch_feature_ids.clearRetainingCapacity();
        self.scratch_ngram_buf.clearRetainingCapacity();
        self.max_feature_len_value = 0;
    }

    pub fn insert(self: *HashDb, text: []const u8) !void {
        const features = try self.extractFeaturesForInsert(text);
        errdefer self.allocator.free(features);

        const owned_text = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned_text);

        const string_id: types.StringId = self.strings.items.len;

        try self.strings.append(self.allocator, owned_text);
        errdefer _ = self.strings.pop();

        try self.string_features.append(self.allocator, features);
        errdefer _ = self.string_features.pop();

        const feature_size = features.len;
        if (feature_size > self.max_feature_len_value) {
            self.max_feature_len_value = feature_size;
        }

        for (features) |feature| {
            const key = FeatureKey{
                .size = feature_size,
                .feature = feature,
            };
            const posting_entry = try self.feature_map.getOrPut(key);
            if (!posting_entry.found_existing) {
                posting_entry.value_ptr.* = .empty;
            }
            try posting_entry.value_ptr.append(self.allocator, string_id);
        }
    }

    pub fn lookupStrings(
        self: *const HashDb,
        size: usize,
        feature: types.FeatureId,
    ) ?[]const types.StringId {
        const posting_list = self.feature_map.getPtr(.{ .size = size, .feature = feature }) orelse return null;
        return posting_list.items;
    }

    pub fn getString(self: *const HashDb, id: types.StringId) ?[]const u8 {
        if (id >= self.strings.items.len) return null;
        return self.strings.items[id];
    }

    pub fn getFeatures(self: *const HashDb, id: types.StringId) ?[]const types.FeatureId {
        if (id >= self.string_features.items.len) return null;
        return self.string_features.items[id];
    }

    pub fn maxFeatureLen(self: *const HashDb) usize {
        return self.max_feature_len_value;
    }

    pub fn totalStrings(self: *const HashDb) usize {
        return self.strings.items.len;
    }

    pub fn reserveForWorkload(
        self: *HashDb,
        expected_strings: usize,
        expected_features_per_string: usize,
    ) !void {
        try self.strings.ensureTotalCapacity(self.allocator, expected_strings);
        try self.string_features.ensureTotalCapacity(self.allocator, expected_strings);
        try self.scratch_raw_counts.ensureTotalCapacity(self.allocator, expected_features_per_string);
        try self.scratch_feature_ids.ensureTotalCapacity(self.allocator, expected_features_per_string);
        try self.scratch_ngram_buf.ensureTotalCapacity(self.allocator, expected_features_per_string);
    }

    fn extractFeaturesForInsert(self: *HashDb, text: []const u8) ![]types.FeatureId {
        return switch (self.extractor) {
            .character => |extractor| self.extractCharacterFeaturesForInsert(extractor, text),
            .word => |_| self.extractor.features(self.allocator, text, &self.interner),
        };
    }

    fn extractCharacterFeaturesForInsert(
        self: *HashDb,
        extractor: extractors.CharacterNgrams,
        text: []const u8,
    ) ![]types.FeatureId {
        if (extractor.n == 0) {
            return self.allocator.alloc(types.FeatureId, 0);
        }
        if (!(extractor.endmarker.len == 1 and utils.isAsciiSlice(text))) {
            return extractor.features(self.allocator, text, &self.interner);
        }

        const padding_len = extractor.n -| 1;
        const total_len = text.len + 2 * padding_len;
        if (total_len < extractor.n) {
            return self.allocator.alloc(types.FeatureId, 0);
        }

        const windows = total_len - extractor.n + 1;
        self.scratch_raw_counts.clearRetainingCapacity();
        self.scratch_feature_ids.clearRetainingCapacity();
        try self.scratch_raw_counts.ensureTotalCapacity(self.allocator, windows);
        try self.scratch_feature_ids.ensureTotalCapacity(self.allocator, windows);

        try self.scratch_ngram_buf.resize(self.allocator, extractor.n);
        const ngram_buf = self.scratch_ngram_buf.items[0..extractor.n];
        const marker_byte = extractor.endmarker[0];

        for (0..windows) |start| {
            for (0..extractor.n) |j| {
                const idx = start + j;
                ngram_buf[j] = if (idx < padding_len)
                    marker_byte
                else if (idx < padding_len + text.len)
                    text[idx - padding_len]
                else
                    marker_byte;
            }

            const raw_id = try self.interner.getOrInternRawAscii(ngram_buf);
            var occurrence: usize = 1;
            var found = false;
            for (self.scratch_raw_counts.items) |*entry| {
                if (entry.raw_id == raw_id) {
                    entry.count += 1;
                    occurrence = entry.count;
                    found = true;
                    break;
                }
            }
            if (!found) {
                self.scratch_raw_counts.appendAssumeCapacity(.{ .raw_id = raw_id, .count = 1 });
            }

            const feature_id = try self.interner.getOrInternCounted(raw_id, occurrence);
            self.scratch_feature_ids.appendAssumeCapacity(feature_id);
        }

        std.sort.heap(types.FeatureId, self.scratch_feature_ids.items, {}, std.sort.asc(types.FeatureId));
        return self.allocator.dupe(types.FeatureId, self.scratch_feature_ids.items);
    }
};
