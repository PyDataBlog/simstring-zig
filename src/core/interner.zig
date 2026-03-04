const std = @import("std");
const types = @import("types.zig");
const utils = @import("utils.zig");

const CountedFeatureKey = struct {
    raw_id: types.RawFeatureId,
    occurrence: usize,
};

pub const FeatureInterner = struct {
    allocator: std.mem.Allocator,
    raw_map: std.StringHashMap(types.RawFeatureId),
    raw_values: std.ArrayList([]const u8),
    ascii_raw_map: std.AutoHashMap(u128, types.RawFeatureId),
    next_raw_id: types.RawFeatureId,
    counted_map: std.AutoHashMap(CountedFeatureKey, types.FeatureId),
    next_feature_id: types.FeatureId,

    pub fn init(allocator: std.mem.Allocator) FeatureInterner {
        return .{
            .allocator = allocator,
            .raw_map = std.StringHashMap(types.RawFeatureId).init(allocator),
            .raw_values = .empty,
            .ascii_raw_map = std.AutoHashMap(u128, types.RawFeatureId).init(allocator),
            .next_raw_id = 0,
            .counted_map = std.AutoHashMap(CountedFeatureKey, types.FeatureId).init(allocator),
            .next_feature_id = 0,
        };
    }

    pub fn deinit(self: *FeatureInterner) void {
        for (self.raw_values.items) |value| {
            self.allocator.free(value);
        }
        self.raw_values.deinit(self.allocator);
        self.raw_map.deinit();
        self.ascii_raw_map.deinit();
        self.counted_map.deinit();
    }

    pub fn clear(self: *FeatureInterner) void {
        for (self.raw_values.items) |value| {
            self.allocator.free(value);
        }
        self.raw_values.clearRetainingCapacity();
        self.raw_map.clearRetainingCapacity();
        self.ascii_raw_map.clearRetainingCapacity();
        self.next_raw_id = 0;
        self.counted_map.clearRetainingCapacity();
        self.next_feature_id = 0;
    }

    pub fn len(self: *const FeatureInterner) usize {
        return self.counted_map.count();
    }

    pub fn getOrInternRaw(self: *FeatureInterner, raw_feature: []const u8) !types.RawFeatureId {
        if (utils.packAsciiRawKey(raw_feature)) |packed_key| {
            if (self.ascii_raw_map.get(packed_key)) |id| {
                return id;
            }
        }

        if (self.raw_map.get(raw_feature)) |id| {
            return id;
        }

        const dup = try self.allocator.dupe(u8, raw_feature);
        errdefer self.allocator.free(dup);

        const id = self.next_raw_id;
        self.next_raw_id += 1;
        try self.raw_values.append(self.allocator, dup);
        errdefer {
            _ = self.raw_values.pop();
        }

        try self.raw_map.put(dup, id);

        if (utils.packAsciiRawKey(raw_feature)) |packed_key| {
            try self.ascii_raw_map.put(packed_key, id);
        }

        return id;
    }

    pub fn getOrInternRawAscii(self: *FeatureInterner, bytes: []const u8) !types.RawFeatureId {
        const packed_key = utils.packAsciiRawKey(bytes) orelse return self.getOrInternRaw(bytes);
        if (self.ascii_raw_map.get(packed_key)) |id| {
            return id;
        }

        if (self.raw_map.get(bytes)) |id| {
            try self.ascii_raw_map.put(packed_key, id);
            return id;
        }

        const id = self.next_raw_id;
        self.next_raw_id += 1;
        try self.ascii_raw_map.put(packed_key, id);
        return id;
    }

    pub fn getOrInternCounted(
        self: *FeatureInterner,
        raw_id: types.RawFeatureId,
        occurrence: usize,
    ) !types.FeatureId {
        const key = CountedFeatureKey{
            .raw_id = raw_id,
            .occurrence = occurrence,
        };
        if (self.counted_map.get(key)) |id| {
            return id;
        }

        const id = self.next_feature_id;
        self.next_feature_id += 1;
        try self.counted_map.put(key, id);
        return id;
    }
};
