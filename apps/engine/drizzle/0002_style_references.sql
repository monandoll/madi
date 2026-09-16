CREATE TABLE `references` (
	`id` text PRIMARY KEY NOT NULL,
	`path` text NOT NULL,
	`file_name` text NOT NULL,
	`title` text NOT NULL,
	`size_bytes` integer NOT NULL,
	`status` text DEFAULT 'queued' NOT NULL,
	`stats` text,
	`segments` text,
	`error` text,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `references_path_idx` ON `references` (`path`);