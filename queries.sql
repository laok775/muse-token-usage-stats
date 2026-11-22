-- Token 用量统计：查询（PostgreSQL；通过 muse.db 执行）
-- 表 agent.agent_message_token_usage：agent_id, message_id, input_tokens, output_tokens, created_at（bigint，epoch 秒）
-- 按天 / 按小时聚合以用户本地时区为准，下例用 Asia/Shanghai，请按实际时区替换。
-- 注意：muse.db 只接受查询规则里列出的函数；epoch 秒转时间戳用
--   timezone('Asia/Shanghai', timestamp 'epoch' + make_interval(secs => created_at::double precision))
-- 这一写法（to_timestamp 不可用）。以下查询均已在真实环境验证通过。

-- 1. 累计总量
SELECT COUNT(*) AS message_count,
       SUM(input_tokens) AS total_input_tokens,
       SUM(output_tokens) AS total_output_tokens
FROM agent.agent_message_token_usage;

-- 2. 近 14 天每日用量（按天聚合）
SELECT date_trunc('day', timezone('Asia/Shanghai', timestamp 'epoch' + make_interval(secs => created_at::double precision))) AS day,
       SUM(input_tokens) AS day_input_tokens,
       SUM(output_tokens) AS day_output_tokens,
       COUNT(*) AS day_messages
FROM agent.agent_message_token_usage
WHERE created_at >= (EXTRACT(epoch FROM now())::bigint - 14 * 86400)
GROUP BY day
ORDER BY day;

-- 3. 按 agent 分组（来源占比；主对话 agent 需在应用层标为「主对话」）
SELECT agent_id,
       SUM(input_tokens) AS agent_input_tokens,
       SUM(output_tokens) AS agent_output_tokens,
       COUNT(*) AS agent_messages
FROM agent.agent_message_token_usage
GROUP BY agent_id
ORDER BY SUM(input_tokens) + SUM(output_tokens) DESC;

-- 4. 按小时 + 星期分布（时间段统计）
SELECT EXTRACT(hour FROM timezone('Asia/Shanghai', timestamp 'epoch' + make_interval(secs => created_at::double precision))) AS hour_of_day,
       EXTRACT(dow FROM timezone('Asia/Shanghai', timestamp 'epoch' + make_interval(secs => created_at::double precision))) AS weekday,
       SUM(input_tokens) AS hour_input_tokens,
       SUM(output_tokens) AS hour_output_tokens,
       COUNT(*) AS hour_messages
FROM agent.agent_message_token_usage
GROUP BY hour_of_day, weekday
ORDER BY weekday, hour_of_day;

-- 5. 最近 7 天按 agent 的用量（花钱大户的基础数据；任务归属还需结合 runtime.requests / scheduler.job_runs，见 BUILD.md）
SELECT agent_id,
       SUM(input_tokens) + SUM(output_tokens) AS week_total_tokens,
       COUNT(*) AS week_messages
FROM agent.agent_message_token_usage
WHERE created_at >= (EXTRACT(epoch FROM now())::bigint - 7 * 86400)
GROUP BY agent_id
ORDER BY week_total_tokens DESC
LIMIT 10;

-- 6. 压缩事件
SELECT id AS compaction_id,
       agent_id AS compaction_agent_id,
       trigger AS compaction_trigger,
       tokens_before AS tokens_before_count,
       tokens_after AS tokens_after_count,
       timezone('Asia/Shanghai', timestamp 'epoch' + make_interval(secs => created_at::double precision)) AS compacted_at
FROM agent.agent_compactions
ORDER BY created_at DESC;

-- 7. 消息内容（关键词云与话题分布的基础数据；body 可能为空）
SELECT message_id, role, created_at, body
FROM runtime.messages
WHERE body IS NOT NULL
ORDER BY created_at;

-- 注意：agent.token_usage 明细表（input/output/cached/reasoning）经核查是空表，
-- 缓存 token 与推理 token 没有数据源，不要用这张表。
