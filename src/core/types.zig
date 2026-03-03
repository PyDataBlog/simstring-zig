pub const StringId = usize;
pub const FeatureId = usize;
pub const RawFeatureId = usize;

pub const SimstringError = error{
    InvalidThreshold,
    InvalidUtf8,
};

pub const RankedMatch = struct {
    text: []const u8,
    score: f64,
};

pub const RawCount = struct {
    raw_id: RawFeatureId,
    count: usize,
};
