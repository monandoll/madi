DROP INDEX `transcripts_video_id_unique`;--> statement-breakpoint
ALTER TABLE `transcripts` ADD `is_source` integer DEFAULT true NOT NULL;--> statement-breakpoint
CREATE INDEX `transcripts_video_created_idx` ON `transcripts` (`video_id`,`created_at`);
--> statement-breakpoint
UPDATE `edits` SET `transcript_id` = (SELECT `id` FROM `transcripts` WHERE `transcripts`.`video_id` = `edits`.`video_id` LIMIT 1)
WHERE `subtitles` = 1 AND `transcript_id` IS NULL;
