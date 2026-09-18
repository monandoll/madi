CREATE TABLE `plans` (
	`video_id` text PRIMARY KEY NOT NULL,
	`plan` text NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`video_id`) REFERENCES `videos`(`id`) ON UPDATE no action ON DELETE cascade
);
