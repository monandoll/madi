CREATE TABLE `memory` (
	`id` text PRIMARY KEY NOT NULL,
	`text` text NOT NULL,
	`kind` text DEFAULT 'style' NOT NULL,
	`scope` text DEFAULT 'all' NOT NULL,
	`topics` text DEFAULT '[]' NOT NULL,
	`video_id` text,
	`source` text NOT NULL,
	`evidence` text DEFAULT '[]' NOT NULL,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE INDEX `memory_scope_idx` ON `memory` (`scope`,`video_id`);--> statement-breakpoint
ALTER TABLE `references` ADD `insight` text;