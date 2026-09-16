CREATE TABLE `chapters` (
	`video_id` text PRIMARY KEY NOT NULL,
	`items` text NOT NULL,
	`from_transcript` integer DEFAULT false NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`video_id`) REFERENCES `videos`(`id`) ON UPDATE no action ON DELETE cascade
);
