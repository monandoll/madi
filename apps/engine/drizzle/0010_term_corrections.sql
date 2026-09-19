CREATE TABLE `term_corrections` (
	`id` text PRIMARY KEY NOT NULL,
	`wrong` text NOT NULL,
	`right` text NOT NULL,
	`count` integer DEFAULT 1 NOT NULL,
	`video_id` text,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `term_corrections_pair_idx` ON `term_corrections` (`wrong`,`right`);