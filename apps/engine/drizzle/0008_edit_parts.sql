ALTER TABLE `edits` ADD `parts` text DEFAULT '[]' NOT NULL;--> statement-breakpoint
ALTER TABLE `edits` ADD `crop_focus` real;--> statement-breakpoint
ALTER TABLE `edits` ADD `subtitle_auto` integer DEFAULT true NOT NULL;