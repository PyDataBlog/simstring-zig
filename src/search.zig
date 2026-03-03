const std = @import("std");
const db_mod = @import("database/mod.zig");
const measures = @import("measures/mod.zig");
const types = @import("core/types.zig");

pub const Searcher = struct {
    allocator: std.mem.Allocator,
    db: *db_mod.HashDb,
    measure: measures.Measure,

    pub fn init(allocator: std.mem.Allocator, db: *db_mod.HashDb, measure: measures.Measure) Searcher {
        return .{
            .allocator = allocator,
            .db = db,
            .measure = measure,
        };
    }

    pub fn search(self: *Searcher, query: []const u8, alpha: f64) ![][]const u8 {
        const candidate_info = try self.searchCandidates(query, alpha);
        defer self.allocator.free(candidate_info.ids);
        defer self.allocator.free(candidate_info.query_features);

        var results: std.ArrayList([]const u8) = .empty;
        defer results.deinit(self.allocator);

        for (candidate_info.ids) |id| {
            const str = self.db.getString(id) orelse continue;
            try results.append(self.allocator, str);
        }

        std.sort.heap([]const u8, results.items, {}, stringLessThan);
        return results.toOwnedSlice(self.allocator);
    }

    pub fn rankedSearch(self: *Searcher, query: []const u8, alpha: f64) ![]types.RankedMatch {
        const candidate_info = try self.searchCandidates(query, alpha);
        defer self.allocator.free(candidate_info.ids);
        defer self.allocator.free(candidate_info.query_features);

        var ranked: std.ArrayList(types.RankedMatch) = .empty;
        defer ranked.deinit(self.allocator);

        for (candidate_info.ids) |id| {
            const candidate_str = self.db.getString(id) orelse continue;
            const candidate_features = self.db.getFeatures(id) orelse continue;
            const score = self.measure.similarity(candidate_info.query_features, candidate_features);
            if (score >= alpha) {
                try ranked.append(self.allocator, .{ .text = candidate_str, .score = score });
            }
        }

        std.sort.heap(types.RankedMatch, ranked.items, {}, rankedLessThan);
        return ranked.toOwnedSlice(self.allocator);
    }

    const CandidateSearchResult = struct {
        ids: []types.StringId,
        query_features: []types.FeatureId,
    };

    fn searchCandidates(self: *Searcher, query: []const u8, alpha: f64) !CandidateSearchResult {
        if (!(alpha > 0.0 and alpha <= 1.0)) {
            return types.SimstringError.InvalidThreshold;
        }

        const query_features = try self.db.extractor.features(self.allocator, query, &self.db.interner);
        errdefer self.allocator.free(query_features);

        const candidate_ids = try self.searchForIds(query_features, alpha);

        return .{ .ids = candidate_ids, .query_features = query_features };
    }

    fn searchForIds(self: *Searcher, query_features: []const types.FeatureId, alpha: f64) ![]types.StringId {
        const query_size = query_features.len;
        if (query_size == 0) {
            return self.allocator.alloc(types.StringId, 0);
        }

        const min_size = self.measure.minFeatureSize(query_size, alpha);
        const max_size = self.measure.maxFeatureSize(query_size, alpha, self.db);
        if (min_size > max_size) {
            return self.allocator.alloc(types.StringId, 0);
        }

        var candidate_set = std.AutoHashMap(types.StringId, void).init(self.allocator);
        defer candidate_set.deinit();

        var size = min_size;
        while (size <= max_size) : (size += 1) {
            const tau = self.measure.minimumCommonFeatureCount(query_size, size, alpha);
            if (tau == 0 or tau > query_size) continue;

            const ids = try self.overlapJoin(query_features, tau, size);
            defer self.allocator.free(ids);

            for (ids) |id| {
                try candidate_set.put(id, {});
            }
        }

        var out = try self.allocator.alloc(types.StringId, candidate_set.count());
        var idx: usize = 0;
        var it = candidate_set.keyIterator();
        while (it.next()) |id_ptr| {
            out[idx] = id_ptr.*;
            idx += 1;
        }

        return out;
    }

    fn overlapJoin(
        self: *Searcher,
        query_features: []const types.FeatureId,
        tau: usize,
        candidate_size: usize,
    ) ![]types.StringId {
        if (query_features.len == 0 or tau == 0) {
            return self.allocator.alloc(types.StringId, 0);
        }

        var feature_sets = try self.allocator.alloc(?[]const types.StringId, query_features.len);
        defer self.allocator.free(feature_sets);

        var available_features: usize = 0;
        for (query_features, 0..) |feature, i| {
            feature_sets[i] = self.db.lookupStrings(candidate_size, feature);
            if (feature_sets[i] != null) available_features += 1;
        }

        if (available_features < tau) {
            return self.allocator.alloc(types.StringId, 0);
        }

        var feature_indices = try self.allocator.alloc(usize, query_features.len);
        defer self.allocator.free(feature_indices);

        for (feature_indices, 0..) |*slot, i| {
            slot.* = i;
        }

        const sort_ctx = FeatureIndexSortContext{ .feature_sets = feature_sets };
        std.sort.heap(usize, feature_indices, sort_ctx, featureIndexLessThan);

        var candidate_counts = std.AutoHashMap(types.StringId, usize).init(self.allocator);
        defer candidate_counts.deinit();

        const q_len = query_features.len;
        const first_pass_count = q_len - tau + 1;

        for (feature_indices[0..first_pass_count]) |feature_idx| {
            const ids = feature_sets[feature_idx] orelse continue;
            for (ids) |id| {
                const entry = try candidate_counts.getOrPut(id);
                if (!entry.found_existing) {
                    entry.value_ptr.* = 0;
                }
                entry.value_ptr.* += 1;
            }
        }

        if (tau == 1) {
            var quick = try self.allocator.alloc(types.StringId, candidate_counts.count());
            var qi: usize = 0;
            var key_it = candidate_counts.keyIterator();
            while (key_it.next()) |id_ptr| {
                quick[qi] = id_ptr.*;
                qi += 1;
            }
            return quick;
        }

        var results: std.ArrayList(types.StringId) = .empty;
        defer results.deinit(self.allocator);

        var count_it = candidate_counts.iterator();
        while (count_it.next()) |entry| {
            const candidate_id = entry.key_ptr.*;
            var count = entry.value_ptr.*;

            if (count >= tau) {
                try results.append(self.allocator, candidate_id);
                continue;
            }

            var i = first_pass_count;
            while (i < q_len) : (i += 1) {
                const feature_idx = feature_indices[i];
                if (feature_sets[feature_idx]) |ids| {
                    if (containsSortedId(ids, candidate_id)) {
                        count += 1;
                    }
                }

                if (count >= tau) {
                    try results.append(self.allocator, candidate_id);
                    break;
                }

                const remaining = q_len - 1 - i;
                if (count + remaining < tau) {
                    break;
                }
            }
        }

        return results.toOwnedSlice(self.allocator);
    }
};

const FeatureIndexSortContext = struct {
    feature_sets: []const ?[]const types.StringId,
};

fn featureIndexLessThan(ctx: FeatureIndexSortContext, lhs: usize, rhs: usize) bool {
    const lhs_set = ctx.feature_sets[lhs];
    const rhs_set = ctx.feature_sets[rhs];

    const lhs_len = if (lhs_set) |s| s.len else std.math.maxInt(usize);
    const rhs_len = if (rhs_set) |s| s.len else std.math.maxInt(usize);
    return lhs_len < rhs_len;
}

fn stringLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn rankedLessThan(_: void, lhs: types.RankedMatch, rhs: types.RankedMatch) bool {
    if (lhs.score > rhs.score) return true;
    if (lhs.score < rhs.score) return false;
    return std.mem.order(u8, lhs.text, rhs.text) == .lt;
}

fn containsSortedId(ids: []const types.StringId, target: types.StringId) bool {
    var low: usize = 0;
    var high: usize = ids.len;

    while (low < high) {
        const mid = low + (high - low) / 2;
        const value = ids[mid];
        if (value == target) return true;
        if (value < target) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }

    return false;
}
