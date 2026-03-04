use serde::Serialize;
use simstring_rust::{CharacterNgrams, Cosine, HashDb, Searcher};
use std::env;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::sync::Arc;
use std::time::Instant;

#[derive(Debug, Clone)]
struct Config {
    dataset_path: String,
    seconds: f64,
    iterations: usize,
}

#[derive(Serialize)]
struct Stats {
    mean: f64,
    stddev: f64,
    iterations: usize,
}

#[derive(Serialize)]
struct Parameters {
    ngram_size: usize,
    threshold: Option<f64>,
}

#[derive(Serialize)]
struct BenchmarkResult {
    language: String,
    backend: String,
    benchmark: String,
    parameters: Parameters,
    stats: Stats,
}

fn parse_args() -> anyhow::Result<Config> {
    let mut dataset_path = "benches/data/company_names.txt".to_string();
    let mut seconds = 3.0;
    let mut iterations = 50usize;

    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--dataset" => {
                dataset_path = args.next().ok_or_else(|| anyhow::anyhow!("missing value for --dataset"))?;
            }
            "--seconds" => {
                let raw = args.next().ok_or_else(|| anyhow::anyhow!("missing value for --seconds"))?;
                seconds = raw.parse()?;
            }
            "--iterations" => {
                let raw = args
                    .next()
                    .ok_or_else(|| anyhow::anyhow!("missing value for --iterations"))?;
                iterations = raw.parse()?;
            }
            other => {
                return Err(anyhow::anyhow!("unknown argument: {other}"));
            }
        }
    }

    Ok(Config {
        dataset_path,
        seconds,
        iterations,
    })
}

fn load_companies(path: &str) -> anyhow::Result<Vec<String>> {
    let file = File::open(path)?;
    let reader = BufReader::new(file);
    Ok(reader.lines().map_while(Result::ok).collect())
}

fn compute_stats(samples: &[f64]) -> Stats {
    if samples.is_empty() {
        return Stats {
            mean: 0.0,
            stddev: 0.0,
            iterations: 0,
        };
    }

    let mean = samples.iter().sum::<f64>() / samples.len() as f64;
    let stddev = if samples.len() > 1 {
        let variance = samples
            .iter()
            .map(|x| {
                let d = mean - x;
                d * d
            })
            .sum::<f64>()
            / (samples.len() - 1) as f64;
        variance.sqrt()
    } else {
        0.0
    };

    Stats {
        mean,
        stddev,
        iterations: samples.len(),
    }
}

fn bench_insert(config: &Config, companies: &[String], out: &mut Vec<BenchmarkResult>) {
    for ngram_size in [2usize, 3, 4] {
        let mut samples = Vec::new();
        let suite_start = Instant::now();

        while suite_start.elapsed().as_secs_f64() < config.seconds && samples.len() < config.iterations {
            let extractor = Arc::new(CharacterNgrams::new(ngram_size, " "));
            let mut db = HashDb::new(extractor);

            let start = Instant::now();
            for company in companies {
                db.insert(company.clone());
            }
            samples.push(start.elapsed().as_secs_f64() * 1000.0);
        }

        out.push(BenchmarkResult {
            language: "rust".to_string(),
            backend: "simstring-rust (native)".to_string(),
            benchmark: "insert".to_string(),
            parameters: Parameters {
                ngram_size,
                threshold: None,
            },
            stats: compute_stats(&samples),
        });
    }
}

fn bench_search(config: &Config, companies: &[String], out: &mut Vec<BenchmarkResult>) {
    let search_terms: Vec<String> = companies.iter().take(100).cloned().collect();

    for ngram_size in [2usize, 3, 4] {
        let extractor = Arc::new(CharacterNgrams::new(ngram_size, " "));
        let mut db = HashDb::new(extractor);
        for company in companies {
            db.insert(company.clone());
        }

        let searcher = Searcher::new(&db, Cosine);

        for threshold in [0.6f64, 0.7, 0.8, 0.9] {
            let mut samples = Vec::new();
            let suite_start = Instant::now();

            while suite_start.elapsed().as_secs_f64() < config.seconds
                && samples.len() < config.iterations
            {
                let start = Instant::now();
                for term in &search_terms {
                    let _ = searcher.search(term, threshold).unwrap();
                }
                samples.push(start.elapsed().as_secs_f64() * 1000.0);
            }

            out.push(BenchmarkResult {
                language: "rust".to_string(),
                backend: "simstring-rust (native)".to_string(),
                benchmark: "search".to_string(),
                parameters: Parameters {
                    ngram_size,
                    threshold: Some(threshold),
                },
                stats: compute_stats(&samples),
            });
        }
    }
}

fn main() -> anyhow::Result<()> {
    let config = parse_args()?;
    let companies = load_companies(&config.dataset_path)?;

    let mut results = Vec::new();
    bench_insert(&config, &companies, &mut results);
    bench_search(&config, &companies, &mut results);

    println!("{}", serde_json::to_string_pretty(&results)?);
    Ok(())
}
