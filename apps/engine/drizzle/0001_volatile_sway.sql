CREATE TABLE `edits` (
	`id` text PRIMARY KEY NOT NULL,
	`video_id` text NOT NULL,
	`title` text NOT NULL,
	`keep` text,
	`cuts` text NOT NULL,
	`crop` text DEFAULT 'none' NOT NULL,
	`subtitles` integer DEFAULT false NOT NULL,
	`transcript_id` text,
	`subtitle_style` text NOT NULL,
	`speed` text NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`video_id`) REFERENCES `videos`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `messages` (
	`id` text PRIMARY KEY NOT NULL,
	`video_id` text NOT NULL,
	`role` text NOT NULL,
	`kind` text NOT NULL,
	`code` text NOT NULL,
	`params` text NOT NULL,
	`job_id` text,
	`output_id` text,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	FOREIGN KEY (`video_id`) REFERENCES `videos`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `messages_video_idx` ON `messages` (`video_id`,`created_at`);--> statement-breakpoint
CREATE TABLE `outputs` (
	`id` text PRIMARY KEY NOT NULL,
	`video_id` text NOT NULL,
	`edit_id` text NOT NULL,
	`title` text NOT NULL,
	`kind` text NOT NULL,
	`path` text NOT NULL,
	`duration_sec` real NOT NULL,
	`width` integer NOT NULL,
	`height` integer NOT NULL,
	`size_bytes` integer NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`video_id`) REFERENCES `videos`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`edit_id`) REFERENCES `edits`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `outputs_video_idx` ON `outputs` (`video_id`,`created_at`);--> statement-breakpoint
CREATE TABLE `transcripts` (
	`id` text PRIMARY KEY NOT NULL,
	`video_id` text NOT NULL,
	`language` text NOT NULL,
	`model` text NOT NULL,
	`segments` text NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`video_id`) REFERENCES `videos`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE UNIQUE INDEX `transcripts_video_id_unique` ON `transcripts` (`video_id`);