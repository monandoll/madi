CREATE TABLE `events` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`name` text NOT NULL,
	`props` text,
	`duration_ms` integer,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `jobs` (
	`id` text PRIMARY KEY NOT NULL,
	`type` text NOT NULL,
	`status` text DEFAULT 'queued' NOT NULL,
	`progress` real DEFAULT 0 NOT NULL,
	`video_id` text,
	`payload` text NOT NULL,
	`error` text,
	`attempts` integer DEFAULT 0 NOT NULL,
	`created_at` integer NOT NULL,
	`started_at` integer,
	`finished_at` integer
);
--> statement-breakpoint
CREATE INDEX `jobs_status_type_idx` ON `jobs` (`status`,`type`,`created_at`);--> statement-breakpoint
CREATE INDEX `jobs_video_idx` ON `jobs` (`video_id`);--> statement-breakpoint
CREATE TABLE `kv` (
	`key` text PRIMARY KEY NOT NULL,
	`value` text NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `proxies` (
	`id` text PRIMARY KEY NOT NULL,
	`video_id` text NOT NULL,
	`path` text NOT NULL,
	`width` integer NOT NULL,
	`height` integer NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`video_id`) REFERENCES `videos`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE TABLE `videos` (
	`id` text PRIMARY KEY NOT NULL,
	`path` text NOT NULL,
	`file_name` text NOT NULL,
	`title` text NOT NULL,
	`kind` text DEFAULT 'long' NOT NULL,
	`status` text DEFAULT 'registered' NOT NULL,
	`duration_sec` real,
	`width` integer,
	`height` integer,
	`fps` real,
	`has_audio` integer,
	`size_bytes` integer NOT NULL,
	`recorded_at` integer NOT NULL,
	`thumbnail_path` text,
	`error` text,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `videos_path_idx` ON `videos` (`path`);--> statement-breakpoint
CREATE INDEX `videos_recorded_idx` ON `videos` (`recorded_at`);