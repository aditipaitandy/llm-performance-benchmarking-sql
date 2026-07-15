USE ai_arena;

-- Q1: Top 10 rows for Coding & Reasoning Domains
WITH ModelWins AS (
    SELECT 
        m.model_name,
        b.prompt_category,
        COUNT(b.battle_id) AS total_battles,
        COUNT(CASE 
            WHEN b.winner = 'model_a' AND b.model_a = m.model_id THEN 1
            WHEN b.winner = 'model_b' AND b.model_b = m.model_id THEN 1
        END) AS total_wins
    FROM models m
    JOIN arena_battles b ON m.model_id = b.model_a OR m.model_id = b.model_b
    WHERE b.prompt_category IN ('Coding', 'Reasoning')
    GROUP BY m.model_name, b.prompt_category
)
SELECT 
    prompt_category,
    model_name,
    total_wins,
    total_battles,
    ROUND((CAST(total_wins AS DECIMAL(10,2)) / total_battles) * 100, 1) AS win_rate_pct,
    DENSE_RANK() OVER (PARTITION BY prompt_category ORDER BY (CAST(total_wins AS DECIMAL(10,2)) / total_battles) DESC) AS category_rank
FROM ModelWins
ORDER BY prompt_category, category_rank
LIMIT 10;

-- Q2: Top 5 Commercial Models Ranked by ROI
WITH GlobalWins AS (
    SELECT 
        m.model_name,
        (m.input_cost_per_1m + m.output_cost_per_1m) / 2 AS avg_cost_per_1m,
        COUNT(b.battle_id) AS total_battles,
        COUNT(CASE 
            WHEN b.winner = 'model_a' AND b.model_a = m.model_id THEN 1
            WHEN b.winner = 'model_b' AND b.model_b = m.model_id THEN 1
        END) AS total_wins
    FROM models m
    JOIN arena_battles b ON m.model_id = b.model_a OR m.model_id = b.model_b
    WHERE m.input_cost_per_1m > 0
    GROUP BY m.model_id, m.model_name, m.input_cost_per_1m, m.output_cost_per_1m
)
SELECT 
    model_name,
    ROUND((CAST(total_wins AS DECIMAL(10,2)) / total_battles) * 100, 1) AS win_rate_pct,
    ROUND(avg_cost_per_1m, 2) AS avg_cost_per_1m_usd,
    ROUND(((CAST(total_wins AS DECIMAL(10,2)) / total_battles) * 100) / avg_cost_per_1m, 2) AS cost_efficiency_score
FROM GlobalWins
ORDER BY cost_efficiency_score DESC
LIMIT 5;

-- Q3: Head-to-Head Flagship Matchup
SELECT 
    m_a.model_name AS model_a_name,
    m_b.model_name AS model_b_name,
    COUNT(CASE WHEN winner = 'model_a' THEN 1 END) AS model_a_wins,
    COUNT(CASE WHEN winner = 'model_b' THEN 1 END) AS model_b_wins,
    COUNT(CASE WHEN winner = 'tie' THEN 1 END) AS total_ties,
    COUNT(*) AS total_matches,
    ROUND((COUNT(CASE WHEN winner = 'model_a' THEN 1 END) / CAST(COUNT(*) AS DECIMAL(10,2))) * 100, 1) AS model_a_win_pct
FROM arena_battles b
JOIN models m_a ON b.model_a = m_a.model_id
JOIN models m_b ON b.model_b = m_b.model_id
WHERE (b.model_a = 'gpt-4o' AND b.model_b = 'claude-3-5-sonnet')
   OR (b.model_a = 'claude-3-5-sonnet' AND b.model_b = 'gpt-4o')
GROUP BY m_a.model_name, m_b.model_name
LIMIT 1;

-- Q4: Top 5 Fastest High-Quality Models
WITH LatencyMetrics AS (
    SELECT 
        model_id,
        ROUND(AVG(latency_ms), 0) AS avg_latency_ms,
        ROUND(AVG(tokens_generated / (latency_ms / 1000.0)), 1) AS tokens_per_second
    FROM performance_logs
    WHERE is_successful = 1
    GROUP BY model_id
),
QualityMetrics AS (
    SELECT 
        m.model_id,
        m.model_name,
        ROUND((COUNT(CASE 
            WHEN b.winner = 'model_a' AND b.model_a = m.model_id THEN 1
            WHEN b.winner = 'model_b' AND b.model_b = m.model_id THEN 1
        END) / CAST(COUNT(b.battle_id) AS DECIMAL(10,2))) * 100, 1) AS win_rate_pct
    FROM models m
    JOIN arena_battles b ON m.model_id = b.model_a OR m.model_id = b.model_b
    GROUP BY m.model_id, m.model_name
)
SELECT 
    q.model_name,
    q.win_rate_pct,
    l.avg_latency_ms,
    l.tokens_per_second
FROM QualityMetrics q
JOIN LatencyMetrics l ON q.model_id = l.model_id
ORDER BY q.win_rate_pct DESC, l.tokens_per_second DESC
LIMIT 5;

-- Q5: Top 5 Highest Operational Risk Points
SELECT 
    m.model_name,
    CASE 
        WHEN tokens_generated < 500 THEN 'Short (0-499 tokens)'
        WHEN tokens_generated BETWEEN 500 AND 2000 THEN 'Medium (500-1999 tokens)'
        ELSE 'Long Sequence (2000+ tokens)'
    END AS payload_size,
    COUNT(*) AS total_requests,
    ROUND((COUNT(CASE WHEN is_successful = 0 THEN 1 END) / CAST(COUNT(*) AS DECIMAL(10,2))) * 100, 1) AS failure_rate_pct,
    ROUND(AVG(latency_ms), 0) AS avg_latency_ms
FROM performance_logs l
JOIN models m ON l.model_id = m.model_id
GROUP BY m.model_name, payload_size
HAVING failure_rate_pct > 0
ORDER BY failure_rate_pct DESC, avg_latency_ms DESC
LIMIT 5;