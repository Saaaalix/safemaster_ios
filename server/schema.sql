-- 在 phpMyAdmin 里先选中数据库「safemaster」再执行本文件（或只执行下面 CREATE TABLE 那一段）

CREATE TABLE IF NOT EXISTS `users` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `apple_sub` VARCHAR(64) NOT NULL COMMENT '由 identityToken 派生的唯一标识',
  `credits` INT NOT NULL DEFAULT 5 COMMENT '剩余分析次数',
  `plan_status` VARCHAR(16) NOT NULL DEFAULT 'inactive' COMMENT 'inactive/active',
  `plan_expires_at` DATETIME NULL COMMENT '会员到期时间',
  `daily_limit` INT NOT NULL DEFAULT 20 COMMENT '每日可用分析次数',
  `daily_used` INT NOT NULL DEFAULT 0 COMMENT '当日已用次数',
  `daily_ai_unit_limit` INT NOT NULL DEFAULT 200 COMMENT '每日 AI 点数额度',
  `daily_ai_unit_used` INT NOT NULL DEFAULT 0 COMMENT '当日已用 AI 点数',
  `daily_quota_date` CHAR(10) NOT NULL DEFAULT '' COMMENT '配额日期(Asia/Shanghai, YYYY-MM-DD)',
  `report_unlimited` TINYINT(1) NOT NULL DEFAULT 1 COMMENT '报告生成是否不限次',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_apple_sub` (`apple_sub`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ai_usage_logs` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `apple_sub` VARCHAR(64) NOT NULL COMMENT '关联 users.apple_sub',
  `feature` VARCHAR(64) NOT NULL DEFAULT '' COMMENT 'AI 功能点，如 hazard_analyze/import_extract_text_clean',
  `model` VARCHAR(64) NOT NULL DEFAULT '' COMMENT '模型名称',
  `prompt_tokens` INT NOT NULL DEFAULT 0 COMMENT '输入 token',
  `completion_tokens` INT NOT NULL DEFAULT 0 COMMENT '输出 token',
  `total_tokens` INT NOT NULL DEFAULT 0 COMMENT '总 token',
  `units_charged` INT NOT NULL DEFAULT 0 COMMENT '本次折算扣减 AI 点数',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_ai_usage_apple_sub_created` (`apple_sub`, `created_at`),
  KEY `idx_ai_usage_feature_created` (`feature`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `iap_transactions` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `apple_sub` VARCHAR(64) NOT NULL COMMENT '关联 users.apple_sub',
  `product_id` VARCHAR(128) NOT NULL COMMENT '如 com.safeMaster.aqds.monthly',
  `transaction_id` VARCHAR(64) NOT NULL COMMENT 'Apple transactionId，唯一',
  `original_transaction_id` VARCHAR(64) NOT NULL COMMENT 'Apple originalTransactionId',
  `expires_at` DATETIME NOT NULL COMMENT '本次凭证到期时间',
  `environment` VARCHAR(32) NOT NULL DEFAULT '' COMMENT 'Sandbox/Production',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_transaction_id` (`transaction_id`),
  KEY `idx_original_transaction_id` (`original_transaction_id`),
  KEY `idx_iap_apple_sub` (`apple_sub`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
