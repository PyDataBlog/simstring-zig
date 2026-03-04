const std = @import("std");
const db_mod = @import("../database/mod.zig");
const types = @import("../core/types.zig");

pub const Measure = enum {
    cosine,
    dice,
    jaccard,
    overlap,
    exact_match,

    pub fn minFeatureSize(self: Measure, query_size: usize, alpha: f64) usize {
        switch (self) {
            .cosine => {
                return @as(usize, @intFromFloat(@ceil(alpha * alpha * @as(f64, @floatFromInt(query_size)))));
            },
            .dice => {
                if (alpha > 2.0) return 0;
                return @as(usize, @intFromFloat(@ceil((alpha / (2.0 - alpha)) * @as(f64, @floatFromInt(query_size)))));
            },
            .jaccard => {
                return @as(usize, @intFromFloat(@ceil(alpha * @as(f64, @floatFromInt(query_size)))));
            },
            .overlap => return 1,
            .exact_match => return query_size,
        }
    }

    pub fn maxFeatureSize(self: Measure, query_size: usize, alpha: f64, db: *const db_mod.HashDb) usize {
        switch (self) {
            .cosine => {
                if (alpha == 0.0) return db.maxFeatureLen();
                const calc = @as(usize, @intFromFloat(@floor(@as(f64, @floatFromInt(query_size)) / (alpha * alpha))));
                return @min(calc, db.maxFeatureLen());
            },
            .dice => {
                if (alpha == 0.0) return db.maxFeatureLen();
                const calc = @as(usize, @intFromFloat(@floor(((2.0 - alpha) / alpha) * @as(f64, @floatFromInt(query_size)))));
                return @min(calc, db.maxFeatureLen());
            },
            .jaccard => {
                return @as(usize, @intFromFloat(@floor(@as(f64, @floatFromInt(query_size)) / alpha)));
            },
            .overlap => return db.maxFeatureLen(),
            .exact_match => return query_size,
        }
    }

    pub fn minimumCommonFeatureCount(self: Measure, query_size: usize, y_size: usize, alpha: f64) usize {
        switch (self) {
            .cosine => {
                return @as(usize, @intFromFloat(@ceil(alpha * @sqrt(@as(f64, @floatFromInt(query_size * y_size))))));
            },
            .dice => {
                return @as(usize, @intFromFloat(@ceil(0.5 * alpha * @as(f64, @floatFromInt(query_size + y_size)))));
            },
            .jaccard => {
                if (alpha == -1.0) return 0;
                return @as(usize, @intFromFloat(@ceil((alpha * @as(f64, @floatFromInt(query_size + y_size))) / (1.0 + alpha))));
            },
            .overlap => {
                const min_size = @min(query_size, y_size);
                return @as(usize, @intFromFloat(@ceil(alpha * @as(f64, @floatFromInt(min_size)))));
            },
            .exact_match => return query_size,
        }
    }

    pub fn similarity(self: Measure, x: []const types.FeatureId, y: []const types.FeatureId) f64 {
        switch (self) {
            .cosine => {
                if (x.len == 0 or y.len == 0) return 0.0;
                const intersection = computeIntersectionSize(x, y);
                const denom = @sqrt(@as(f64, @floatFromInt(x.len)) * @as(f64, @floatFromInt(y.len)));
                if (denom == 0.0 or !std.math.isFinite(denom)) return 0.0;
                return @as(f64, @floatFromInt(intersection)) / denom;
            },
            .dice => {
                if (x.len == 0 and y.len == 0) return 1.0;
                if (x.len == 0 or y.len == 0) return 0.0;
                const intersection = computeIntersectionSize(x, y);
                const denom = @as(f64, @floatFromInt(x.len + y.len));
                if (denom == 0.0) return 0.0;
                return 2.0 * @as(f64, @floatFromInt(intersection)) / denom;
            },
            .jaccard => {
                if (x.len == 0 and y.len == 0) return 1.0;
                if (x.len == 0 or y.len == 0) return 0.0;
                const intersection = computeIntersectionSize(x, y);
                const union_size = @as(f64, @floatFromInt(x.len + y.len - intersection));
                if (union_size == 0.0) return 0.0;
                return @as(f64, @floatFromInt(intersection)) / union_size;
            },
            .overlap => {
                if (x.len == 0 and y.len == 0) return 1.0;
                if (x.len == 0 or y.len == 0) return 0.0;
                const intersection = computeIntersectionSize(x, y);
                const denom = @as(f64, @floatFromInt(@min(x.len, y.len)));
                if (denom == 0.0) return 0.0;
                return @as(f64, @floatFromInt(intersection)) / denom;
            },
            .exact_match => {
                if (x.len != y.len) return 0.0;
                if (std.mem.eql(types.FeatureId, x, y)) return 1.0;
                return 0.0;
            },
        }
    }
};

fn computeIntersectionSize(x: []const types.FeatureId, y: []const types.FeatureId) usize {
    var intersection: usize = 0;
    var i: usize = 0;
    var j: usize = 0;

    while (i < x.len and j < y.len) {
        if (x[i] == y[j]) {
            intersection += 1;
            i += 1;
            j += 1;
        } else if (x[i] < y[j]) {
            i += 1;
        } else {
            j += 1;
        }
    }

    return intersection;
}
